import { Injectable, HttpStatus } from '@nestjs/common';
import { InjectRepository } from '@nestjs/typeorm';
import { Repository, DataSource, EntityManager } from 'typeorm';
import { Wallet } from './entities/wallet.entity';
import { LedgerEntry } from '../ledger/entities/ledger-entry.entity';
import { LedgerService } from '../ledger/ledger.service';
import { DomainException } from '../common/domain.exception';
import { ErrorCode } from '../common/error-codes';
import {
  Currency,
  LedgerDirection,
  LedgerEntryType,
  WalletStatus,
} from '../common/enums';

/**
 * Everything a single balance movement needs to describe itself in the ledger.
 *
 * `referenceType` + `referenceId` identify the *business* operation (a trip, a
 * withdrawal, a provider reference). Together with the wallet and entry type
 * they form a unique key, which is what makes replays impossible at the
 * database level.
 */
export interface WalletMutationContext {
  entryType: LedgerEntryType;
  /** The financial transaction this movement belongs to, when one exists. */
  transactionId?: string;
  referenceType?: string;
  referenceId?: string;
  description?: string;
  /** Expected currency; a mismatch with the wallet is refused, never converted. */
  currency?: Currency;
  /** Domain error for a debit that exceeds the balance (default WALLET_INSUFFICIENT_BALANCE). */
  insufficientBalanceCode?: ErrorCode;
}

export interface WalletMutationResult {
  wallet: Wallet;
  balanceBefore: number;
  balanceAfter: number;
}

export interface TransferContext {
  debit: WalletMutationContext;
  credit: WalletMutationContext;
  currency?: Currency;
}

/**
 * The only place a wallet balance is allowed to change.
 *
 * Every balance change follows the same shape:
 *
 *   1. lock the wallet row (pessimistic write)
 *   2. validate status, currency and — for a debit — sufficient funds
 *   3. write `balanceBefore` / `amount` / `balanceAfter` on the wallet
 *   4. append exactly one ledger entry describing that same arithmetic
 *
 * Callers must supply a transaction-scoped `EntityManager`; a mutation outside a
 * transaction would allow a balance change whose ledger entry never lands.
 * PostgreSQL enforces the same invariants independently (`balance >= 0`, ledger
 * amount > 0, `balanceAfter = balanceBefore ± amount`), so a bug here cannot
 * silently corrupt the ledger.
 */
@Injectable()
export class WalletsService {
  constructor(
    @InjectRepository(Wallet)
    private readonly walletRepository: Repository<Wallet>,
    private readonly ledgerService: LedgerService,
    private readonly dataSource: DataSource,
  ) {}

  // ─── Reads ─────────────────────────────────────────────────────────────────

  /**
   * Returns the user's wallet, opening one (zero balance) on first use.
   *
   * Wallets are created lazily, so this can be a user's first-ever financial
   * action — including two of them at the same time. The insert is
   * `ON CONFLICT DO NOTHING` against the unique `wallets."userId"` constraint,
   * so concurrent first uses converge on a single row instead of racing into a
   * unique-violation error.
   */
  async getWalletByUserId(userId: string): Promise<Wallet> {
    return this.ensureWallet(this.dataSource.manager, userId);
  }

  async getWalletByUserIdOrFail(userId: string): Promise<Wallet> {
    const wallet = await this.walletRepository.findOne({
      where: { user: { id: userId } },
    });
    if (!wallet) {
      throw new DomainException(
        'Wallet not found',
        HttpStatus.NOT_FOUND,
        ErrorCode.WALLET_NOT_FOUND,
      );
    }
    return wallet;
  }

  async getWalletTransactions(userId: string, limit = 50) {
    const wallet = await this.getWalletByUserIdOrFail(userId);
    return this.dataSource.getRepository(LedgerEntry).find({
      where: { walletId: wallet.id },
      order: { createdAt: 'DESC' },
      take: limit,
    });
  }

  // ─── The single balance-mutation mechanism ─────────────────────────────────

  /** Credits a wallet and records exactly one matching ledger entry. */
  async creditWallet(
    manager: EntityManager,
    userId: string,
    amount: number,
    ctx: WalletMutationContext,
  ): Promise<WalletMutationResult> {
    const wallet = await this.lockWalletForUser(manager, userId);
    return this.applyMutation(manager, wallet, LedgerDirection.CREDIT, amount, ctx);
  }

  /** Debits a wallet and records exactly one matching ledger entry. */
  async debitWallet(
    manager: EntityManager,
    userId: string,
    amount: number,
    ctx: WalletMutationContext,
  ): Promise<WalletMutationResult> {
    const wallet = await this.lockWalletForUser(manager, userId);
    return this.applyMutation(manager, wallet, LedgerDirection.DEBIT, amount, ctx);
  }

  /**
   * Moves money between two wallets: one debit, one credit, one transaction.
   *
   * Both wallets are resolved first and then locked in a deterministic order
   * (ascending UUID), so two opposing transfers — A→B and B→A — can never hold
   * each other's lock and deadlock. Balances are validated only after both locks
   * are held, which makes "insufficient funds" decisions race-free.
   */
  async transferWallet(
    manager: EntityManager,
    fromUserId: string,
    toUserId: string,
    amount: number,
    ctx: TransferContext,
  ): Promise<{ debit: WalletMutationResult; credit: WalletMutationResult }> {
    this.assertPositiveAmount(amount);

    const fromWallet = await this.ensureWallet(manager, fromUserId);
    const toWallet = await this.ensureWallet(manager, toUserId);

    if (fromWallet.id === toWallet.id) {
      // A transfer to oneself would write two offsetting entries and move
      // nothing. It is always a caller bug, never a legitimate operation.
      throw new DomainException(
        'A transfer must be between two different wallets',
        HttpStatus.BAD_REQUEST,
        ErrorCode.VALIDATION_ERROR,
      );
    }

    const lockOrder = [fromWallet.id, toWallet.id].sort();
    const locked = new Map<string, Wallet>();
    for (const walletId of lockOrder) {
      locked.set(walletId, await this.lockWallet(manager, walletId));
    }

    const debit = await this.applyMutation(
      manager,
      locked.get(fromWallet.id)!,
      LedgerDirection.DEBIT,
      amount,
      ctx.debit,
    );
    const credit = await this.applyMutation(
      manager,
      locked.get(toWallet.id)!,
      LedgerDirection.CREDIT,
      amount,
      ctx.credit,
    );

    return { debit, credit };
  }

  /**
   * Credits a wallet for a confirmed top-up, exactly once per provider
   * reference.
   *
   * The reference check runs *after* the wallet lock, inside the same
   * transaction as the credit, so a replayed confirmation observes the first
   * credit instead of a stale "not credited yet" read.
   */
  async topUp(
    userId: string,
    amount: number,
    providerReference: string,
  ): Promise<Wallet> {
    this.assertPositiveAmount(amount);

    return this.dataSource.transaction(async (manager: EntityManager) => {
      const wallet = await this.lockWalletForUser(manager, userId);

      const existing = await manager.findOne(LedgerEntry, {
        where: {
          walletId: wallet.id,
          referenceType: 'TOP_UP',
          referenceId: providerReference,
        },
      });
      if (existing) {
        // A replayed confirmation is not an error: the money is already here.
        return wallet;
      }

      const result = await this.applyMutation(
        manager,
        wallet,
        LedgerDirection.CREDIT,
        amount,
        {
          entryType: LedgerEntryType.TOP_UP,
          referenceType: 'TOP_UP',
          referenceId: providerReference,
          description: 'Wallet top-up',
        },
      );

      return result.wallet;
    });
  }

  // ─── Internals ─────────────────────────────────────────────────────────────

  /**
   * The single point where a balance changes.
   *
   * Walks the direction-specific arithmetic explicitly so the wallet row and the
   * ledger entry can never disagree, and so an impossible amount is refused
   * before any write.
   */
  private async applyMutation(
    manager: EntityManager,
    wallet: Wallet,
    direction: LedgerDirection,
    amount: number,
    ctx: WalletMutationContext,
  ): Promise<WalletMutationResult> {
    this.assertPositiveAmount(amount);

    if (wallet.status !== WalletStatus.ACTIVE) {
      throw new DomainException(
        'Wallet is not active',
        HttpStatus.BAD_REQUEST,
        ErrorCode.WALLET_FROZEN,
      );
    }

    if (ctx.currency && ctx.currency !== wallet.currency) {
      throw new DomainException(
        `Wallet is held in ${wallet.currency} and cannot settle a ${ctx.currency} operation`,
        HttpStatus.BAD_REQUEST,
        ErrorCode.CURRENCY_MISMATCH,
      );
    }

    const balanceBefore = wallet.balance;
    let balanceAfter: number;

    if (direction === LedgerDirection.CREDIT) {
      // CREDIT: balanceAfter = balanceBefore + amount
      balanceAfter = balanceBefore + amount;
    } else {
      // DEBIT: balanceAfter = balanceBefore - amount, and never below zero.
      if (balanceBefore < amount) {
        throw new DomainException(
          'Insufficient wallet balance',
          HttpStatus.BAD_REQUEST,
          ctx.insufficientBalanceCode ?? ErrorCode.WALLET_INSUFFICIENT_BALANCE,
        );
      }
      balanceAfter = balanceBefore - amount;
    }

    wallet.balance = balanceAfter;
    await manager.save(wallet);

    await this.ledgerService.recordEntry(manager, {
      walletId: wallet.id,
      transactionId: ctx.transactionId,
      entryType: ctx.entryType,
      direction,
      amount,
      currency: wallet.currency,
      balanceBefore,
      balanceAfter,
      referenceType: ctx.referenceType,
      referenceId: ctx.referenceId,
      description: ctx.description,
    });

    return { wallet, balanceBefore, balanceAfter };
  }

  /**
   * Money is integer minor units. A fractional or non-positive movement is
   * rejected here as well as at the DTO edge: services may be reached from
   * callbacks and jobs that never pass through a controller.
   */
  private assertPositiveAmount(amount: number): void {
    if (!Number.isInteger(amount) || amount <= 0) {
      throw new DomainException(
        'Amount must be a positive integer in minor units',
        HttpStatus.BAD_REQUEST,
        ErrorCode.VALIDATION_ERROR,
      );
    }
  }

  /** Finds or creates the user's wallet. Safe under concurrent first use. */
  private async ensureWallet(
    manager: EntityManager,
    userId: string,
  ): Promise<Wallet> {
    const existing = await manager.findOne(Wallet, {
      where: { user: { id: userId } },
    });
    if (existing) return existing;

    await manager.query(
      `INSERT INTO "wallets" ("userId") VALUES ($1) ON CONFLICT ("userId") DO NOTHING`,
      [userId],
    );

    const created = await manager.findOne(Wallet, {
      where: { user: { id: userId } },
    });
    if (!created) {
      throw new DomainException(
        'Wallet could not be created',
        HttpStatus.INTERNAL_SERVER_ERROR,
        ErrorCode.INTERNAL_ERROR,
      );
    }
    return created;
  }

  /** Ensures the wallet exists, then locks it for this transaction. */
  private async lockWalletForUser(
    manager: EntityManager,
    userId: string,
  ): Promise<Wallet> {
    const wallet = await this.ensureWallet(manager, userId);
    return this.lockWallet(manager, wallet.id);
  }

  private async lockWallet(
    manager: EntityManager,
    walletId: string,
  ): Promise<Wallet> {
    const wallet = await manager.findOne(Wallet, {
      where: { id: walletId },
      lock: { mode: 'pessimistic_write' },
    });
    if (!wallet) {
      throw new DomainException(
        'Wallet not found',
        HttpStatus.NOT_FOUND,
        ErrorCode.WALLET_NOT_FOUND,
      );
    }
    return wallet;
  }
}
