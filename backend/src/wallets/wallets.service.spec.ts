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
import { DomainException } from '../common/domain.exception';
import { ErrorCode } from '../common/error-codes';

describe('WalletsService', () => {
  let service: WalletsService;
  let walletRepo: any;
  let ledgerService: any;
  let dataSource: any;

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
      transaction: jest.fn().mockImplementation(async (cb) => {
        const manager: any = {
          findOne: jest.fn(),
          save: jest.fn().mockImplementation((e) => e),
          create: jest.fn(),
        };
        return cb(manager);
      }),
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

  describe('topUp', () => {
    it('should skip duplicate top-ups sharing the same idempotency key', async () => {
      const existingWallet = { id: 'w1', balance: 50000, status: WalletStatus.ACTIVE, currency: Currency.ETB };
      ledgerService.findByReference.mockResolvedValue({ id: 'ledger-exists' });
      walletRepo.findOne.mockResolvedValue(existingWallet);

      const result = await service.topUp('user1', 10000, 'idem-key-1');
      expect(result.balance).toBe(50000);
      expect(dataSource.transaction).not.toHaveBeenCalled();
    });

    it('should increase balance and record CREDIT ledger entry on new top-up', async () => {
      ledgerService.findByReference.mockResolvedValue(null);
      const existingWallet = { id: 'w1', balance: 50000, status: WalletStatus.ACTIVE, currency: Currency.ETB };

      dataSource.transaction = jest.fn().mockImplementation(async (cb) => {
        const manager: any = {
          findOne: jest.fn().mockImplementation((entity: any, _opts: any) => {
            if (entity === LedgerEntry.name) return null;
            if (entity === Wallet || entity?.name === 'Wallet') return existingWallet;
            return null;
          }),
          save: jest.fn().mockImplementation((e: any) => {
            if (e && typeof e.balance === 'number') Object.assign(existingWallet, e);
            return e;
          }),
        };
        return cb(manager);
      });

      const result = await service.topUp('user1', 25000, 'new-topup-key');
      expect(result.balance).toBe(75000);
      expect(ledgerService.recordEntry).toHaveBeenCalledWith(
        expect.anything(),
        expect.objectContaining({
          walletId: 'w1',
          entryType: LedgerEntryType.TOP_UP,
          direction: LedgerDirection.CREDIT,
          amount: 25000,
          balanceBefore: 50000,
          balanceAfter: 75000,
          referenceId: 'new-topup-key',
        }),
      );
    });
  });

  describe('atomicTransferFromTrip', () => {
    const makeManager = (passenger: any, driver: any): any => ({
      findOne: jest.fn().mockImplementation((entity: any, opts: any) => {
        const uid = opts?.where?.user?.id;
        if (uid === 'pass-u') return passenger;
        if (uid === 'driver-u') return driver;
        return null;
      }),
      save: jest.fn().mockImplementation((e: any) => {
        if (e && e.id === passenger.id) Object.assign(passenger, e);
        if (e && e.id === driver.id) Object.assign(driver, e);
        return e;
      }),
    });

    it('should debit passenger, credit driver, and emit exactly 2 ledger rows', async () => {
      const passenger = {
        id: 'pw1', balance: 50000, status: WalletStatus.ACTIVE, currency: Currency.ETB,
      };
      const driver = {
        id: 'dw1', balance: 20000, status: WalletStatus.ACTIVE, currency: Currency.ETB,
      };
      const manager = makeManager(passenger, driver);

      await service.atomicTransferFromTrip(
        manager as any,
        'pass-u',
        'driver-u',
        8500,
        'pay-1',
        'trip-1',
      );

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

    it('CRITICAL: on insufficient balance — NO state change on either wallet, no ledger rows, throws WALLET_INSUFFICIENT_BALANCE', async () => {
      const passenger = {
        id: 'pw2', balance: 500, status: WalletStatus.ACTIVE, currency: Currency.ETB,
      };
      const driver = {
        id: 'dw2', balance: 20000, status: WalletStatus.ACTIVE, currency: Currency.ETB,
      };
      const manager = makeManager(passenger, driver);

      await expect(
        service.atomicTransferFromTrip(manager as any, 'pass-u', 'driver-u', 8500, 'pay-x', 'trip-x'),
      ).rejects.toThrow(DomainException);
      await expect(
        service.atomicTransferFromTrip(manager as any, 'pass-u', 'driver-u', 8500, 'pay-x', 'trip-x'),
      ).rejects.toMatchObject({ code: ErrorCode.WALLET_INSUFFICIENT_BALANCE });

      expect(passenger.balance).toBe(500);
      expect(driver.balance).toBe(20000);
      expect(ledgerService.recordEntry).not.toHaveBeenCalled();
      expect(manager.save).not.toHaveBeenCalledWith(expect.objectContaining({ id: 'pw2' }));
      expect(manager.save).not.toHaveBeenCalledWith(expect.objectContaining({ id: 'dw2' }));
    });

    it('should throw WALLET_FROZEN if either wallet is not ACTIVE', async () => {
      const passenger = { id: 'pz', balance: 50000, status: WalletStatus.FROZEN, currency: Currency.ETB };
      const driver = { id: 'dz', balance: 20000, status: WalletStatus.ACTIVE, currency: Currency.ETB };
      const manager = makeManager(passenger, driver);

      await expect(
        service.atomicTransferFromTrip(manager as any, 'pass-u', 'driver-u', 1000, 'pay-z', 'trip-z'),
      ).rejects.toMatchObject({ code: ErrorCode.WALLET_FROZEN });
      expect(passenger.balance).toBe(50000);
      expect(driver.balance).toBe(20000);
    });
  });

  describe('debitForWithdrawal', () => {
    it('debits wallet and records WITHDRAWAL ledger DEBIT row', async () => {
      const wallet = {
        id: 'wdraw-w1', balance: 50000, status: WalletStatus.ACTIVE, currency: Currency.ETB,
      };
      const manager: any = {
        findOne: jest.fn().mockResolvedValue(wallet),
        save: jest.fn().mockImplementation((e: any) => {
          if (e && e.id === wallet.id) Object.assign(wallet, e);
          return e;
        }),
      };

      const result = await service.debitForWithdrawal(manager, 'u1', 10000, 'wd-1');
      expect(result.balance).toBe(40000);
      expect(ledgerService.recordEntry).toHaveBeenCalledWith(
        manager,
        expect.objectContaining({
          entryType: LedgerEntryType.WITHDRAWAL,
          direction: LedgerDirection.DEBIT,
          amount: 10000,
          balanceBefore: 50000,
          balanceAfter: 40000,
          referenceId: 'wd-1',
        }),
      );
    });

    it('throws WITHDRAWAL_INSUFFICIENT_BALANCE and leaves wallet untouched', async () => {
      const wallet = {
        id: 'wdraw-w2', balance: 500, status: WalletStatus.ACTIVE, currency: Currency.ETB,
      };
      const manager: any = {
        findOne: jest.fn().mockResolvedValue(wallet),
        save: jest.fn(),
      };
      await expect(
        service.debitForWithdrawal(manager, 'u1', 2000, 'wd-2'),
      ).rejects.toMatchObject({ code: ErrorCode.WITHDRAWAL_INSUFFICIENT_BALANCE });
      expect(wallet.balance).toBe(500);
      expect(manager.save).not.toHaveBeenCalled();
      expect(ledgerService.recordEntry).not.toHaveBeenCalled();
    });
  });
});
