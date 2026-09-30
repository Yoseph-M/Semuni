import { Injectable, HttpStatus } from '@nestjs/common';
import { InjectRepository } from '@nestjs/typeorm';
import { Repository, DataSource, EntityManager } from 'typeorm';
import { Wallet } from './entities/wallet.entity';
import { LedgerEntry } from '../ledger/entities/ledger-entry.entity';
import { LedgerService } from '../ledger/ledger.service';
import { DomainException } from '../common/domain.exception';
import { ErrorCode } from '../common/error-codes';
import {
  LedgerDirection,
  LedgerEntryType,
  WalletStatus,
} from '../common/enums';

@Injectable()
export class WalletsService {
  constructor(
    @InjectRepository(Wallet)
    private readonly walletRepository: Repository<Wallet>,
    private readonly ledgerService: LedgerService,
    private readonly dataSource: DataSource,
  ) {}

  async getWalletByUserId(userId: string): Promise<Wallet> {
    let wallet = await this.walletRepository.findOne({
      where: { user: { id: userId } },
    });
    if (!wallet) {
      wallet = this.walletRepository.create({ user: { id: userId } });
      wallet = await this.walletRepository.save(wallet);
    }
    return wallet;
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
    const repo = this.dataSource.getRepository('LedgerEntry');
    return repo.find({
      where: { walletId: wallet.id },
      order: { createdAt: 'DESC' },
      take: limit,
    });
  }

  async topUp(
    userId: string,
    amount: number,
    idempotencyKey: string,
  ): Promise<Wallet> {
    const existingRef = await this.ledgerService.findByReference(
      'TOP_UP',
      idempotencyKey,
    );
    if (existingRef) {
      return this.getWalletByUserId(userId);
    }

    return this.dataSource.transaction(async (manager: EntityManager) => {
      const ledgerInsideTx = await manager.findOne(LedgerEntry.name as any, {
        where: { referenceType: 'TOP_UP', referenceId: idempotencyKey },
      });
      if (ledgerInsideTx) {
        return manager.findOne(Wallet, {
          where: { user: { id: userId } },
        }) as Promise<Wallet>;
      }

      const wallet = await manager.findOne(Wallet, {
        where: { user: { id: userId } },
        lock: { mode: 'pessimistic_write' },
      });

      if (!wallet) {
        throw new DomainException(
          'Wallet not found',
          HttpStatus.NOT_FOUND,
          ErrorCode.WALLET_NOT_FOUND,
        );
      }

      if (wallet.status !== WalletStatus.ACTIVE) {
        throw new DomainException(
          'Wallet is not active',
          HttpStatus.BAD_REQUEST,
          ErrorCode.WALLET_FROZEN,
        );
      }

      const balanceBefore = wallet.balance;
      wallet.balance += amount;
      const balanceAfter = wallet.balance;
      await manager.save(wallet);

      await this.ledgerService.recordEntry(manager, {
        walletId: wallet.id,
        entryType: LedgerEntryType.TOP_UP,
        direction: LedgerDirection.CREDIT,
        amount,
        currency: wallet.currency,
        balanceBefore,
        balanceAfter,
        referenceType: 'TOP_UP',
        referenceId: idempotencyKey,
        description: 'Wallet top-up',
      });

      return wallet;
    });
  }

  async atomicTransferFromTrip(
    manager: EntityManager,
    passengerUserId: string,
    driverUserId: string,
    amount: number,
    paymentId: string,
    tripId: string,
  ): Promise<void> {
    // Wallets are created lazily, so either party may not have one yet. Receiving
    // or making a payment must never fail because a wallet was never opened —
    // the wallet is an artifact of being a user, not a prerequisite for it.
    const passengerWallet = await this.findOrCreateWalletInTx(
      manager,
      passengerUserId,
    );
    const driverWallet = await this.findOrCreateWalletInTx(
      manager,
      driverUserId,
    );

    if (
      passengerWallet.status !== WalletStatus.ACTIVE ||
      driverWallet.status !== WalletStatus.ACTIVE
    ) {
      throw new DomainException(
        'Wallet is not active',
        HttpStatus.BAD_REQUEST,
        ErrorCode.WALLET_FROZEN,
      );
    }

    if (passengerWallet.balance < amount) {
      throw new DomainException(
        'Insufficient wallet balance',
        HttpStatus.BAD_REQUEST,
        ErrorCode.WALLET_INSUFFICIENT_BALANCE,
      );
    }

    const passengerBefore = passengerWallet.balance;
    passengerWallet.balance -= amount;
    const passengerAfter = passengerWallet.balance;
    await manager.save(passengerWallet);

    const driverBefore = driverWallet.balance;
    driverWallet.balance += amount;
    const driverAfter = driverWallet.balance;
    await manager.save(driverWallet);

    await this.ledgerService.recordEntry(manager, {
      walletId: passengerWallet.id,
      transactionId: paymentId,
      entryType: LedgerEntryType.TRIP_PAYMENT,
      direction: LedgerDirection.DEBIT,
      amount,
      currency: passengerWallet.currency,
      balanceBefore: passengerBefore,
      balanceAfter: passengerAfter,
      referenceType: 'TRIP',
      referenceId: tripId,
      description: `Trip payment - ${amount / 100} ETB`,
    });

    await this.ledgerService.recordEntry(manager, {
      walletId: driverWallet.id,
      transactionId: paymentId,
      entryType: LedgerEntryType.DRIVER_EARNING,
      direction: LedgerDirection.CREDIT,
      amount,
      currency: driverWallet.currency,
      balanceBefore: driverBefore,
      balanceAfter: driverAfter,
      referenceType: 'TRIP',
      referenceId: tripId,
      description: `Trip earnings - ${amount / 100} ETB`,
    });
  }

  /**
   * Locks the owner's wallet, creating it first if the user never had one.
   *
   * A freshly-created row is only visible to this transaction, so it needs no
   * row lock.
   */
  private async findOrCreateWalletInTx(
    manager: EntityManager,
    userId: string,
  ): Promise<Wallet> {
    const existing = await manager.findOne(Wallet, {
      where: { user: { id: userId } },
      lock: { mode: 'pessimistic_write' },
    });
    if (existing) return existing;

    return manager.save(
      manager.create(Wallet, { user: { id: userId } }),
    ) as Promise<Wallet>;
  }

  async debitForWithdrawal(
    manager: EntityManager,
    userId: string,
    amount: number,
    withdrawalId: string,
  ): Promise<Wallet> {
    const wallet = await manager.findOne(Wallet, {
      where: { user: { id: userId } },
      lock: { mode: 'pessimistic_write' },
    });

    if (!wallet) {
      throw new DomainException(
        'Wallet not found',
        HttpStatus.NOT_FOUND,
        ErrorCode.WALLET_NOT_FOUND,
      );
    }

    if (wallet.status !== WalletStatus.ACTIVE) {
      throw new DomainException(
        'Wallet is not active',
        HttpStatus.BAD_REQUEST,
        ErrorCode.WALLET_FROZEN,
      );
    }

    if (wallet.balance < amount) {
      throw new DomainException(
        'Insufficient wallet balance for withdrawal',
        HttpStatus.BAD_REQUEST,
        ErrorCode.WITHDRAWAL_INSUFFICIENT_BALANCE,
      );
    }

    const balanceBefore = wallet.balance;
    wallet.balance -= amount;
    const balanceAfter = wallet.balance;
    await manager.save(wallet);

    await this.ledgerService.recordEntry(manager, {
      walletId: wallet.id,
      transactionId: withdrawalId,
      entryType: LedgerEntryType.WITHDRAWAL,
      direction: LedgerDirection.DEBIT,
      amount,
      currency: wallet.currency,
      balanceBefore,
      balanceAfter,
      referenceType: 'WITHDRAWAL',
      referenceId: withdrawalId,
      description: 'Withdrawal from wallet',
    });

    return wallet;
  }
}
