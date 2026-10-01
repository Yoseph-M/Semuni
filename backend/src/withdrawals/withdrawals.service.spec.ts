import { Test, TestingModule } from '@nestjs/testing';
import { WithdrawalsService } from './withdrawals.service';
import { getRepositoryToken } from '@nestjs/typeorm';
import { Withdrawal } from './entities/withdrawal.entity';
import { WalletsService } from '../wallets/wallets.service';
import { DataSource } from 'typeorm';
import {
  WalletStatus,
  WithdrawalStatus,
  WithdrawalDestinationType,
  PaymentProvider,
  Currency,
  UserRole,
  DriverStatus,
} from '../common/enums';
import { RequestWithdrawalDto } from './dto/withdrawal.dto';
import { DomainException } from '../common/domain.exception';
import { ErrorCode } from '../common/error-codes';
import { User } from '../users/entities/user.entity';

describe('WithdrawalsService', () => {
  let service: WithdrawalsService;
  let withdrawalRepo: any;
  let walletsService: any;
  let dataSource: any;
  let userRepoFindOne: jest.Mock;
  let driverRepoFindOne: jest.Mock;

  beforeEach(async () => {
    withdrawalRepo = {
      findOne: jest.fn(),
      find: jest.fn(),
    };

    walletsService = {
      debitForWithdrawal: jest.fn(),
    };

    // assertOperationalDriver resolves the user (role) and the driver profile
    // (status) through the DataSource. The defaults describe an operational
    // driver; individual tests override them to exercise the policy.
    userRepoFindOne = jest
      .fn()
      .mockResolvedValue({ id: 'driver-u-1', role: UserRole.DRIVER });
    driverRepoFindOne = jest.fn().mockResolvedValue({
      id: 'driver-1',
      userId: 'driver-u-1',
      status: DriverStatus.ACTIVE,
    });

    dataSource = {
      getRepository: jest
        .fn()
        .mockImplementation((entity: unknown) =>
          entity === User
            ? { findOne: userRepoFindOne }
            : { findOne: driverRepoFindOne },
        ),
      transaction: jest.fn().mockImplementation(async (cb) => {
        const manager: any = {
          findOne: jest.fn(),
          save: jest.fn().mockImplementation((e: any) => ({ id: 'wd-id', ...e })),
          create: jest.fn().mockImplementation((_, data) => ({ id: 'wd-id', ...data })),
        };
        return cb(manager);
      }),
    };

    const module: TestingModule = await Test.createTestingModule({
      providers: [
        WithdrawalsService,
        { provide: getRepositoryToken(Withdrawal), useValue: withdrawalRepo },
        { provide: WalletsService, useValue: walletsService },
        { provide: DataSource, useValue: dataSource },
      ],
    }).compile();

    service = module.get<WithdrawalsService>(WithdrawalsService);
  });

  it('should be defined', () => {
    expect(service).toBeDefined();
  });

  describe('requestWithdrawal', () => {
    const baseDto: RequestWithdrawalDto = {
      amount: 2000,
      destinationType: WithdrawalDestinationType.BANK,
      destination: 'Commercial Bank of Ethiopia',
      destinationAccount: '10001234567890',
      provider: PaymentProvider.MOCK,
      idempotencyKey: 'wd-driver-1-20260928-001',
    };

    it('returns existing record (idempotent) on same idempotencyKey without debiting again', async () => {
      const existing = {
        id: 'wd-1',
        status: WithdrawalStatus.SUCCESS,
        amount: 2000,
        destinationType: baseDto.destinationType,
        destination: baseDto.destination,
        destinationAccount: baseDto.destinationAccount,
        provider: PaymentProvider.MOCK,
      };
      withdrawalRepo.findOne.mockResolvedValue(existing);

      const result = await service.requestWithdrawal('driver-u-1', baseDto);
      expect(result).toEqual(existing);
      expect(dataSource.transaction).not.toHaveBeenCalled();
      expect(walletsService.debitForWithdrawal).not.toHaveBeenCalled();
    });

    it('debits wallet atomically, marks PROCESSING, and returns the withdrawal record', async () => {
      withdrawalRepo.findOne.mockResolvedValue(null);
      const wallet = { id: 'w1', balance: 10000, status: WalletStatus.ACTIVE, currency: Currency.ETB };
      walletsService.debitForWithdrawal.mockResolvedValue(wallet);

      const result = await service.requestWithdrawal('driver-u-1', baseDto);

      expect(dataSource.transaction).toHaveBeenCalled();
      expect(walletsService.debitForWithdrawal).toHaveBeenCalledWith(
        expect.anything(),
        'driver-u-1',
        2000,
        expect.any(String),
      );
      expect(result.status).toEqual(WithdrawalStatus.PROCESSING);
      expect(result.amount).toBe(2000);
      expect(result.userId).toBe('driver-u-1');
    });

    it('rejects a non-driver caller at the service level, beyond the role guard', async () => {
      userRepoFindOne.mockResolvedValue({
        id: 'passenger-u-1',
        role: UserRole.PASSENGER,
      });

      await expect(
        service.requestWithdrawal('passenger-u-1', baseDto),
      ).rejects.toMatchObject({ code: ErrorCode.AUTH_FORBIDDEN });
      expect(dataSource.transaction).not.toHaveBeenCalled();
      expect(walletsService.debitForWithdrawal).not.toHaveBeenCalled();
    });

    it('rejects a driver profile that is not ACTIVE', async () => {
      driverRepoFindOne.mockResolvedValue({
        id: 'driver-1',
        userId: 'driver-u-1',
        status: DriverStatus.PENDING,
      });

      await expect(
        service.requestWithdrawal('driver-u-1', baseDto),
      ).rejects.toMatchObject({ code: ErrorCode.DRIVER_NOT_ACTIVE });
      expect(walletsService.debitForWithdrawal).not.toHaveBeenCalled();
    });

    it('rejects an idempotency key reused with a different amount', async () => {
      withdrawalRepo.findOne.mockResolvedValue({
        id: 'wd-1',
        status: WithdrawalStatus.PROCESSING,
        amount: 9999,
        destinationType: baseDto.destinationType,
        destination: baseDto.destination,
        destinationAccount: baseDto.destinationAccount,
        provider: PaymentProvider.MOCK,
      });

      await expect(
        service.requestWithdrawal('driver-u-1', baseDto),
      ).rejects.toMatchObject({ code: ErrorCode.IDEMPOTENCY_CONFLICT });
      expect(dataSource.transaction).not.toHaveBeenCalled();
    });

    it('marks withdrawal FAILED and rethrows when debitForWithdrawal fails', async () => {
      withdrawalRepo.findOne.mockResolvedValue(null);
      walletsService.debitForWithdrawal.mockRejectedValue(
        new DomainException(
          'Insufficient wallet balance for withdrawal',
          400,
          ErrorCode.WITHDRAWAL_INSUFFICIENT_BALANCE,
        ),
      );

      await expect(
        service.requestWithdrawal('driver-u-1', baseDto),
      ).rejects.toMatchObject({ code: ErrorCode.WITHDRAWAL_INSUFFICIENT_BALANCE });
    });
  });
});
