import { Test, TestingModule } from '@nestjs/testing';
import { SettlementsService } from './settlements.service';
import { getRepositoryToken } from '@nestjs/typeorm';
import { Settlement } from './entities/settlement.entity';
import { DataSource } from 'typeorm';
import { Withdrawal } from '../withdrawals/entities/withdrawal.entity';
import {
  WithdrawalStatus,
  Currency,
} from '../common/enums';

describe('SettlementsService', () => {
  let service: SettlementsService;
  let settlementRepo: any;
  let dataSource: any;

  beforeEach(async () => {
    settlementRepo = {
      find: jest.fn(),
    };

    dataSource = {
      transaction: jest.fn().mockImplementation(async (cb) => {
        const manager: any = {
          find: jest.fn(),
          findOne: jest.fn().mockResolvedValue(null),
          save: jest.fn().mockImplementation((e: any) => e),
          create: jest.fn().mockImplementation((_, data) => data),
        };
        return cb(manager);
      }),
    };

    const module: TestingModule = await Test.createTestingModule({
      providers: [
        SettlementsService,
        { provide: getRepositoryToken(Settlement), useValue: settlementRepo },
        { provide: DataSource, useValue: dataSource },
      ],
    }).compile();

    service = module.get<SettlementsService>(SettlementsService);
  });

  it('should be defined', () => {
    expect(service).toBeDefined();
  });

  describe('processPendingWithdrawals', () => {
    it('returns { processedCount: 0 } if there are no pending/processing withdrawals', async () => {
      const managerRef: any = { find: jest.fn().mockResolvedValue([]) };
      dataSource.transaction = jest.fn().mockImplementation((cb) => cb(managerRef));

      const result = await service.processPendingWithdrawals();
      expect(result.processedCount).toBe(0);
    });

    it('marks withdrawals SUCCESS and creates a Settlement per withdrawal', async () => {
      const mockWithdrawals: any[] = [
        {
          id: 'w1',
          userId: 'driver1',
          amount: 5000,
          currency: Currency.ETB,
          status: WithdrawalStatus.PENDING,
        },
        {
          id: 'w2',
          userId: 'driver2',
          amount: 2000,
          currency: Currency.ETB,
          status: WithdrawalStatus.PROCESSING,
        },
      ];

      let captured: any;
      dataSource.transaction = jest.fn().mockImplementation(async (cb) => {
        const manager: any = {
          find: jest.fn().mockImplementation((entity: any) => {
            if (entity === Withdrawal || entity?.name === 'Withdrawal') return mockWithdrawals;
            return [];
          }),
          findOne: jest.fn().mockResolvedValue(null),
          save: jest.fn().mockImplementation((e: any) => {
            if (Array.isArray(mockWithdrawals)) {
              const match = mockWithdrawals.find((mw) => mw.id === e.id);
              if (match) Object.assign(match, e);
            }
            return e;
          }),
          create: jest.fn().mockImplementation((_, data) => data),
        };
        captured = manager;
        return cb(manager);
      });

      const result = await service.processPendingWithdrawals();
      expect(result.processedCount).toBe(2);
      expect(mockWithdrawals[0].status).toBe(WithdrawalStatus.SUCCESS);
      expect(mockWithdrawals[1].status).toBe(WithdrawalStatus.SUCCESS);
      expect(captured.create).toHaveBeenCalledTimes(2);
    });
  });
});
