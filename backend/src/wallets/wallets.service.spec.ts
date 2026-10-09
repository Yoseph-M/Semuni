import { Test, TestingModule } from '@nestjs/testing';
import { WalletsService } from './wallets.service';
import { getRepositoryToken } from '@nestjs/typeorm';
import { Wallet } from './entities/wallet.entity';
import { LedgerEntry } from '../ledger/entities/ledger-entry.entity';
import { LedgerService } from '../ledger/ledger.service';
import { DataSource } from 'typeorm';
import {
  WalletStatus,
  Currency,
  LedgerEntryType,
  LedgerDirection,
} from '../common/enums';
import { ErrorCode } from '../common/error-codes';

/**
 * Unit coverage for the single wallet-mutation mechanism.
 *
 * The database enforces the same rules independently (Phase 6 migration), so
 * these tests are about the service refusing to *attempt* an impossible
 * movement: no save, no ledger row, no partial state.
 */
describe('WalletsService', () => {
  let service: WalletsService;
  let walletRepo: any;
  let ledgerService: any;
  let dataSource: any;

  interface FakeWallet {
    id: string;
    balance: number;
    status: WalletStatus;
    currency: Currency;
  }

  const walletOf = (
    id: string,
    balance: number,
    status: WalletStatus = WalletStatus.ACTIVE,
  ): FakeWallet => ({ id, balance, status, currency: Currency.ETB });

  /**
   * A transaction manager over a fixed wallet table. Records which wallet ids
   * were locked and in what order, so lock ordering is directly assertable.
   */
  const makeManager = (
    byUser: Record<string, FakeWallet>,
    ledgerEntries: Record<string, unknown> = {},
  ) => {
    const locks: string[] = [];
    const saves: FakeWallet[] = [];
    const events: string[] = [];

    const manager: any = {
      query: jest.fn().mockResolvedValue([]),
      findOne: jest
        .fn()
        .mockImplementation(async (entity: any, opts: any = {}) => {
          if (entity === LedgerEntry) {
            const ref = opts?.where?.referenceId;
            return ref ? (ledgerEntries[ref] ?? null) : null;
          }
          const userId = opts?.where?.user?.id;
          if (userId) return byUser[userId] ?? null;

          const id = opts?.where?.id;
          if (id) {
            if (opts?.lock) {
              locks.push(id);
              events.push(`lock:${id}`);
            }
            return Object.values(byUser).find((w) => w.id === id) ?? null;
          }
          return null;
        }),
      save: jest.fn().mockImplementation(async (wallet: FakeWallet) => {
        saves.push(wallet);
        events.push(`save:${wallet.id}`);
        return wallet;
      }),
      create: jest.fn((_entity: any, data: any) => data),
    };

    return { manager, locks, saves, events };
  };

  beforeEach(async () => {
    walletRepo = {
      findOne: jest.fn(),
      save: jest.fn(),
      create: jest.fn().mockImplementation((data) => ({ id: 'new-wallet', ...data })),
    };

    ledgerService = {
      recordEntry: jest.fn().mockResolvedValue(true),
      findByReference: jest.fn().mockResolvedValue(null),
    };

    dataSource = {
      transaction: jest.fn(),
      manager: { findOne: jest.fn(), query: jest.fn() },
      getRepository: jest.fn().mockReturnValue({
        find: jest.fn().mockResolvedValue([]),
      }),
    };

    const module: TestingModule = await Test.createTestingModule({
      providers: [
        WalletsService,
        { provide: getRepositoryToken(Wallet), useValue: walletRepo },
        { provide: getRepositoryToken(LedgerEntry), useValue: {} },
        { provide: LedgerService, useValue: ledgerService },
        { provide: DataSource, useValue: dataSource },
      ],
    }).compile();

    service = module.get<WalletsService>(WalletsService);
  });

  it('should be defined', () => {
    expect(service).toBeDefined();
  });

  describe('creditWallet / debitWallet', () => {
    it('credits with balanceAfter = balanceBefore + amount and one ledger CREDIT', async () => {
      const wallet = walletOf('w1', 50000);
      const { manager } = makeManager({ 'user-1': wallet });

      const result = await service.creditWallet(manager, 'user-1', 25000, {
        entryType: LedgerEntryType.TOP_UP,
        referenceType: 'TOP_UP',
        referenceId: 'ref-1',
      });

      expect(result.balanceBefore).toBe(50000);
      expect(result.balanceAfter).toBe(75000);
      expect(wallet.balance).toBe(75000);
      expect(ledgerService.recordEntry).toHaveBeenCalledTimes(1);
      expect(ledgerService.recordEntry).toHaveBeenCalledWith(
        manager,
        expect.objectContaining({
          walletId: 'w1',
          entryType: LedgerEntryType.TOP_UP,
          direction: LedgerDirection.CREDIT,
          amount: 25000,
          balanceBefore: 50000,
          balanceAfter: 75000,
          referenceId: 'ref-1',
        }),
      );
    });

    it('debits with balanceAfter = balanceBefore - amount and one ledger DEBIT', async () => {
      const wallet = walletOf('w2', 50000);
      const { manager } = makeManager({ 'user-1': wallet });

      const result = await service.debitWallet(manager, 'user-1', 8500, {
        entryType: LedgerEntryType.TRIP_PAYMENT,
        transactionId: 'pay-1',
        referenceType: 'TRIP',
        referenceId: 'trip-1',
      });

      expect(result.balanceBefore).toBe(50000);
      expect(result.balanceAfter).toBe(41500);
      expect(ledgerService.recordEntry).toHaveBeenCalledTimes(1);
      expect(ledgerService.recordEntry).toHaveBeenCalledWith(
        manager,
        expect.objectContaining({
          direction: LedgerDirection.DEBIT,
          amount: 8500,
          balanceBefore: 50000,
          balanceAfter: 41500,
          transactionId: 'pay-1',
        }),
      );
    });

    it('refuses a debit beyond the balance: no save, no ledger row, balance untouched', async () => {
      const wallet = walletOf('w3', 500);
      const { manager, saves } = makeManager({ 'user-1': wallet });

      await expect(
        service.debitWallet(manager, 'user-1', 8500, {
          entryType: LedgerEntryType.TRIP_PAYMENT,
        }),
      ).rejects.toMatchObject({ code: ErrorCode.WALLET_INSUFFICIENT_BALANCE });

      expect(wallet.balance).toBe(500);
      expect(saves).toHaveLength(0);
      expect(ledgerService.recordEntry).not.toHaveBeenCalled();
    });

    it('honours a caller-specific insufficient-balance code (withdrawals)', async () => {
      const wallet = walletOf('w4', 500);
      const { manager } = makeManager({ 'user-1': wallet });

      await expect(
        service.debitWallet(manager, 'user-1', 2000, {
          entryType: LedgerEntryType.WITHDRAWAL,
          referenceId: 'wd-1',
          insufficientBalanceCode: ErrorCode.WITHDRAWAL_INSUFFICIENT_BALANCE,
        }),
      ).rejects.toMatchObject({
        code: ErrorCode.WITHDRAWAL_INSUFFICIENT_BALANCE,
      });
    });

    it('refuses a frozen wallet', async () => {
      const wallet = walletOf('w5', 50000, WalletStatus.FROZEN);
      const { manager, saves } = makeManager({ 'user-1': wallet });

      await expect(
        service.creditWallet(manager, 'user-1', 1000, {
          entryType: LedgerEntryType.TOP_UP,
        }),
      ).rejects.toMatchObject({ code: ErrorCode.WALLET_FROZEN });

      expect(saves).toHaveLength(0);
      expect(ledgerService.recordEntry).not.toHaveBeenCalled();
    });

    it('refuses a currency mismatch rather than converting implicitly', async () => {
      const wallet = walletOf('w6', 50000);
      const { manager } = makeManager({ 'user-1': wallet });

      await expect(
        service.creditWallet(manager, 'user-1', 1000, {
          entryType: LedgerEntryType.TOP_UP,
          currency: 'USD' as Currency,
        }),
      ).rejects.toMatchObject({ code: ErrorCode.CURRENCY_MISMATCH });
    });

    it.each([0, -100, 12.5, NaN])(
      'refuses a non-positive or fractional amount (%p)',
      async (amount) => {
        const wallet = walletOf('w7', 50000);
        const { manager, saves } = makeManager({ 'user-1': wallet });

        await expect(
          service.creditWallet(manager, 'user-1', amount, {
            entryType: LedgerEntryType.TOP_UP,
          }),
        ).rejects.toMatchObject({ code: ErrorCode.VALIDATION_ERROR });

        expect(saves).toHaveLength(0);
      },
    );
  });

  describe('transferWallet', () => {
    it('debits one wallet and credits the other with exactly two ledger rows', async () => {
      const passenger = walletOf('pw1', 50000);
      const driver = walletOf('dw1', 20000);
      const { manager } = makeManager({ 'pass-u': passenger, 'driver-u': driver });

      await service.transferWallet(manager, 'pass-u', 'driver-u', 8500, {
        debit: {
          entryType: LedgerEntryType.TRIP_PAYMENT,
          transactionId: 'pay-1',
          referenceType: 'TRIP',
          referenceId: 'trip-1',
        },
        credit: {
          entryType: LedgerEntryType.DRIVER_EARNING,
          transactionId: 'pay-1',
          referenceType: 'TRIP',
          referenceId: 'trip-1',
        },
      });

      expect(passenger.balance).toBe(41500);
      expect(driver.balance).toBe(28500);
      expect(ledgerService.recordEntry).toHaveBeenCalledTimes(2);
      expect(ledgerService.recordEntry).toHaveBeenNthCalledWith(
        1,
        manager,
        expect.objectContaining({
          walletId: 'pw1',
          direction: LedgerDirection.DEBIT,
          entryType: LedgerEntryType.TRIP_PAYMENT,
          amount: 8500,
          balanceBefore: 50000,
          balanceAfter: 41500,
        }),
      );
      expect(ledgerService.recordEntry).toHaveBeenNthCalledWith(
        2,
        manager,
        expect.objectContaining({
          walletId: 'dw1',
          direction: LedgerDirection.CREDIT,
          entryType: LedgerEntryType.DRIVER_EARNING,
          amount: 8500,
          balanceBefore: 20000,
          balanceAfter: 28500,
        }),
      );
    });

    it('CRITICAL: acquires both wallet locks in a deterministic order (deadlock avoidance)', async () => {
      // The passenger's wallet id sorts *after* the driver's, so a naive
      // from-then-to lock order would be zzz → aaa. The service must lock in
      // ascending id order regardless of which side of the transfer each is.
      const passenger = walletOf('zzz-passenger', 50000);
      const driver = walletOf('aaa-driver', 20000);
      const { manager, locks } = makeManager({
        'pass-u': passenger,
        'driver-u': driver,
      });

      await service.transferWallet(manager, 'pass-u', 'driver-u', 8500, {
        debit: { entryType: LedgerEntryType.TRIP_PAYMENT },
        credit: { entryType: LedgerEntryType.DRIVER_EARNING },
      });

      expect(locks).toEqual(['aaa-driver', 'zzz-passenger']);
    });

    it('CRITICAL: insufficient balance changes nothing on either side', async () => {
      const passenger = walletOf('pw2', 500);
      const driver = walletOf('dw2', 20000);
      const { manager, saves } = makeManager({ 'pass-u': passenger, 'driver-u': driver });

      await expect(
        service.transferWallet(manager, 'pass-u', 'driver-u', 8500, {
          debit: { entryType: LedgerEntryType.TRIP_PAYMENT },
          credit: { entryType: LedgerEntryType.DRIVER_EARNING },
        }),
      ).rejects.toMatchObject({ code: ErrorCode.WALLET_INSUFFICIENT_BALANCE });

      expect(passenger.balance).toBe(500);
      expect(driver.balance).toBe(20000);
      expect(saves).toHaveLength(0);
      expect(ledgerService.recordEntry).not.toHaveBeenCalled();
    });

    it('refuses a frozen wallet before any money moves', async () => {
      const passenger = walletOf('pw3', 50000, WalletStatus.FROZEN);
      const driver = walletOf('dw3', 20000);
      const { manager, saves } = makeManager({ 'pass-u': passenger, 'driver-u': driver });

      await expect(
        service.transferWallet(manager, 'pass-u', 'driver-u', 1000, {
          debit: { entryType: LedgerEntryType.TRIP_PAYMENT },
          credit: { entryType: LedgerEntryType.DRIVER_EARNING },
        }),
      ).rejects.toMatchObject({ code: ErrorCode.WALLET_FROZEN });

      expect(passenger.balance).toBe(50000);
      expect(driver.balance).toBe(20000);
      expect(saves).toHaveLength(0);
    });

    it('refuses a transfer between the same wallet', async () => {
      const wallet = walletOf('same-wallet', 50000);
      const { manager } = makeManager({ 'user-a': wallet });

      await expect(
        service.transferWallet(manager, 'user-a', 'user-a', 1000, {
          debit: { entryType: LedgerEntryType.TRIP_PAYMENT },
          credit: { entryType: LedgerEntryType.DRIVER_EARNING },
        }),
      ).rejects.toMatchObject({ code: ErrorCode.VALIDATION_ERROR });
    });
  });

  describe('topUp replay protection', () => {
    it('does not credit twice for the same provider reference', async () => {
      const wallet = walletOf('w-top', 50000);
      const { manager, saves } = makeManager(
        { 'user-1': wallet },
        {
          // The ledger already holds a TOP_UP entry for this provider reference.
          'provider-ref-1': { id: 'ledger-existing' },
        },
      );
      dataSource.transaction.mockImplementation(async (cb: any) => cb(manager));

      const result = await service.topUp('user-1', 25000, 'provider-ref-1');

      expect(result.balance).toBe(50000);
      expect(saves).toHaveLength(0);
      expect(ledgerService.recordEntry).not.toHaveBeenCalled();
    });

    it('credits once and records the provider reference on a first confirmation', async () => {
      const wallet = walletOf('w-top2', 0);
      const { manager } = makeManager({ 'user-1': wallet });
      dataSource.transaction.mockImplementation(async (cb: any) => cb(manager));

      const result = await service.topUp('user-1', 25000, 'provider-ref-2');

      expect(result.balance).toBe(25000);
      expect(ledgerService.recordEntry).toHaveBeenCalledTimes(1);
      expect(ledgerService.recordEntry).toHaveBeenCalledWith(
        manager,
        expect.objectContaining({
          entryType: LedgerEntryType.TOP_UP,
          direction: LedgerDirection.CREDIT,
          amount: 25000,
          referenceType: 'TOP_UP',
          referenceId: 'provider-ref-2',
        }),
      );
    });
  });

  describe('wallet creation', () => {
    it('creates a missing wallet through a conflict-tolerant insert', async () => {
      const created = walletOf('w-new', 0);
      let inserted = false;
      const manager: any = {
        findOne: jest.fn().mockImplementation(async (_entity: any, opts: any = {}) => {
          if (opts?.where?.id) return created; // the lock lookup
          return inserted ? created : null; // pre-insert: no wallet yet
        }),
        query: jest.fn().mockImplementation(async () => {
          inserted = true;
          return [];
        }),
        save: jest.fn().mockImplementation(async (e: FakeWallet) => e),
      };

      await service.creditWallet(manager, 'fresh-user', 1000, {
        entryType: LedgerEntryType.TOP_UP,
      });

      // ON CONFLICT ("userId") DO NOTHING is what makes two simultaneous
      // first-time operations converge on one wallet instead of racing.
      expect(manager.query).toHaveBeenCalledWith(
        expect.stringContaining('ON CONFLICT ("userId") DO NOTHING'),
        ['fresh-user'],
      );
    });
  });
});
