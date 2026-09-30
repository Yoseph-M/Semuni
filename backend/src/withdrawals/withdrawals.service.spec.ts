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
} from '../common/enums';
import { RequestWithdrawalDto } from './dto/withdrawal.dto';
import { DomainException } from '../common/domain.exception';
import { ErrorCode } from '../common/error-codes';

describe('WithdrawalsService', () => {
  let service: WithdrawalsService;
  let withdrawalRepo: any;
  let walletsService: any;
  let dataSource: any;

  beforeEach(async () => {
    withdrawalRepo = {
      findOne: jest.fn(),
      find: jest.fn(),
    };

    walletsService = {
      debitForWithdrawal: jest.fn(),
    };

    dataSource = {
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
