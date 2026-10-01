import { Injectable, HttpStatus } from '@nestjs/common';
import { InjectRepository } from '@nestjs/typeorm';
import { Repository } from 'typeorm';
import { TopUpIntent } from './entities/top-up-intent.entity';
import { Wallet } from './entities/wallet.entity';
import { WalletsService } from './wallets.service';
import { TopUpWalletDto } from './dto/wallet.dto';
import { PaymentProviderRegistry } from '../payments/providers/payment-provider.registry';
import { DomainException } from '../common/domain.exception';
import { ErrorCode } from '../common/error-codes';
import { Currency, PaymentProvider, TopUpIntentStatus } from '../common/enums';
import { CustomLogger } from '../common/logger/custom.logger';

export interface TopUpResult {
  intent: TopUpIntent;
  wallet: Wallet;
}

/**
 * Wallet top-ups, as a three-step flow:
 *
 *   1. initiate()  — record the intent, hand it to the provider. No money moves.
 *   2. provider    — the user pays outside Semuni (mock provider here).
 *   3. confirm() / settleByProviderReference() — verify with the provider, then
 *      credit the wallet.
 *
 * The balance is never credited on the client's word alone, and both the
 * verification callback and the wallet credit are idempotent so a replayed
 * webhook cannot double-credit.
 */
@Injectable()
export class TopUpService {
  constructor(
    @InjectRepository(TopUpIntent)
    private readonly intentRepository: Repository<TopUpIntent>,
    private readonly walletsService: WalletsService,
    private readonly providerRegistry: PaymentProviderRegistry,
    private readonly logger: CustomLogger,
  ) {}

  /** Step 1 — create the intent and register it with the provider. */
  async initiate(userId: string, dto: TopUpWalletDto): Promise<TopUpIntent> {
    const provider = dto.provider ?? PaymentProvider.MOCK;

    // Idempotency keys are scoped to the user who generated them: one user's key
    // must never resolve to (or block) another user's top-up.
    const existing = await this.intentRepository.findOne({
      where: { userId, idempotencyKey: dto.idempotencyKey },
    });
    if (existing) {
      // Same key with the same payload means the same top-up: return the
      // original rather than creating a second one. A different amount/provider
      // is a different request wearing the same key, which is a conflict.
      if (existing.amountMinor !== dto.amount || existing.provider !== provider) {
        throw new DomainException(
          'This idempotency key was already used for a different top-up',
          HttpStatus.CONFLICT,
          ErrorCode.IDEMPOTENCY_CONFLICT,
        );
      }

      this.logger.log('Idempotent top-up initiation', TopUpService.name, {
        userId,
        intentId: existing.id,
        status: existing.status,
      });
      return existing;
    }

    const providerName = provider;
    const gateway = this.providerRegistry.get(providerName);

    const intent = await this.intentRepository.save(
      this.intentRepository.create({
        userId,
        amountMinor: dto.amount,
        currency: Currency.ETB,
        provider: providerName,
        status: TopUpIntentStatus.PENDING,
        idempotencyKey: dto.idempotencyKey,
      }),
    );

    const initiation = await gateway.initiateTopUp({
      userId,
      amountMinor: dto.amount,
      currency: intent.currency,
      idempotencyKey: dto.idempotencyKey,
    });

    intent.providerReference = initiation.providerReference;
    const saved = await this.intentRepository.save(intent);

    this.logger.log('Top-up initiated (awaiting provider confirmation)', TopUpService.name, {
      userId,
      intentId: saved.id,
      provider: saved.provider,
      amountMinor: saved.amountMinor,
    });

    return saved;
  }

  /** Step 3 (user path) — the client reports the payment is done; we verify. */
  async confirm(userId: string, intentId: string): Promise<TopUpResult> {
    const intent = await this.intentRepository.findOne({
      where: { id: intentId },
    });
    if (!intent) {
      throw new DomainException(
        'Top-up intent not found',
        HttpStatus.NOT_FOUND,
        ErrorCode.PAYMENT_NOT_FOUND,
      );
    }
    if (intent.userId !== userId) {
      throw new DomainException(
        'Top-up intent does not belong to this user',
        HttpStatus.FORBIDDEN,
        ErrorCode.AUTH_FORBIDDEN,
      );
    }
    return this.settle(intent);
  }

  /** Step 3 (provider path) — webhook / reconciliation entry point. */
  async settleByProviderReference(
    providerReference: string,
  ): Promise<TopUpResult> {
    const intent = await this.intentRepository.findOne({
      where: { providerReference },
    });
    if (!intent) {
      throw new DomainException(
        'Unknown top-up reference',
        HttpStatus.NOT_FOUND,
        ErrorCode.PAYMENT_NOT_FOUND,
      );
    }
    return this.settle(intent);
  }

  async listMine(userId: string): Promise<TopUpIntent[]> {
    return this.intentRepository.find({
      where: { userId },
      order: { createdAt: 'DESC' },
      take: 50,
    });
  }

  /**
   * Verifies with the provider and credits the wallet exactly once.
   *
   * Safe to call concurrently or repeatedly: an already-SUCCESS intent returns
   * its existing state, and WalletsService.topUp is itself idempotent on the
   * provider reference.
   */
  private async settle(intent: TopUpIntent): Promise<TopUpResult> {
    if (intent.status === TopUpIntentStatus.SUCCESS) {
      const wallet = await this.walletsService.getWalletByUserId(intent.userId);
      return { intent, wallet };
    }

    if (intent.status !== TopUpIntentStatus.PENDING) {
      throw new DomainException(
        `Top-up is ${intent.status.toLowerCase()} and can no longer be confirmed`,
        HttpStatus.CONFLICT,
        ErrorCode.PAYMENT_ALREADY_PROCESSED,
      );
    }

    const gateway = this.providerRegistry.get(intent.provider);
    const verification = await gateway.verifyTransaction(
      intent.providerReference ?? '',
    );

    if (!verification.verified) {
      intent.status = TopUpIntentStatus.FAILED;
      intent.failureReason =
        verification.failureReason ?? 'Provider did not confirm the payment';
      await this.intentRepository.save(intent);

      this.logger.warn('Top-up rejected by provider', TopUpService.name, {
        intentId: intent.id,
        userId: intent.userId,
        failureReason: intent.failureReason,
      });

      throw new DomainException(
        'Top-up was not confirmed by the payment provider',
        HttpStatus.PAYMENT_REQUIRED,
        ErrorCode.PAYMENT_FAILED,
      );
    }

    // A brand-new user has no wallet row yet — wallets are created lazily. Without
    // this, the very first top-up by a fresh account would fail.
    await this.walletsService.getWalletByUserId(intent.userId);

    // Only now does the balance change. Keyed by providerReference so a
    // duplicate callback cannot credit twice.
    const wallet = await this.walletsService.topUp(
      intent.userId,
      intent.amountMinor,
      intent.providerReference!,
    );

    intent.status = TopUpIntentStatus.SUCCESS;
    intent.completedAt = new Date();
    await this.intentRepository.save(intent);

    this.logger.log('Top-up confirmed and wallet credited', TopUpService.name, {
      intentId: intent.id,
      userId: intent.userId,
      amountMinor: intent.amountMinor,
      balanceAfter: wallet.balance,
    });

    return { intent, wallet };
  }
}
