import { Test, TestingModule } from '@nestjs/testing';
import { PaymentsService } from './payments.service';
import { getRepositoryToken } from '@nestjs/typeorm';
import { Payment } from './entities/payment.entity';
import { WalletsService } from '../wallets/wallets.service';
import { TripsService } from '../trips/trips.service';
import { NotificationsService } from '../notifications/notifications.service';
import { DataSource } from 'typeorm';
import { CustomLogger } from '../common/logger/custom.logger';
import {
  PaymentRecordStatus,
  PaymentStatus,
  PaymentProvider,
  Currency,
} from '../common/enums';
import { ProcessTripPaymentDto } from './dto/payment.dto';
import { DomainException } from '../common/domain.exception';
import { ErrorCode } from '../common/error-codes';

describe('PaymentsService', () => {
  let service: PaymentsService;
  let paymentRepo: any;
  let walletsService: any;
  let tripsService: any;
  let notificationsService: any;
  let dataSource: any;

  const makeTrip = (overrides: any = {}) => ({
    id: 'trip-1',
    passengerId: 'pass-user-1',
    driverId: 'driver-user-1',
    fareAmount: 8500,
    currency: Currency.ETB,
    routeId: 'route-1',
    paymentStatus: PaymentStatus.UNPAID,
    status: 'COMPLETED',
    createdAt: new Date(),
    ...overrides,
  });

  beforeEach(async () => {
    paymentRepo = {
      findOne: jest.fn(),
      createQueryBuilder: jest.fn().mockReturnValue({
        where: jest.fn().mockReturnThis(),
        getCount: jest.fn().mockResolvedValue(0),
      }),
    };

    walletsService = {
      atomicTransferFromTrip: jest.fn(),
    };

    tripsService = {
      findById: jest.fn(),
      markPaid: jest.fn(),
    };

    notificationsService = {
      sendPushNotification: jest.fn(),
    };

    dataSource = {
      transaction: jest.fn().mockImplementation(async (cb) => {
        const manager: any = {
          create: jest
            .fn()
            .mockImplementation((_, data) => ({ id: 'test-payment-id', ...data })),
          save: jest.fn().mockImplementation((entity) => entity),
        };
        return cb(manager);
      }),
    };

    const module: TestingModule = await Test.createTestingModule({
      providers: [
        PaymentsService,
        { provide: getRepositoryToken(Payment), useValue: paymentRepo },
        { provide: WalletsService, useValue: walletsService },
        { provide: TripsService, useValue: tripsService },
        { provide: NotificationsService, useValue: notificationsService },
        { provide: DataSource, useValue: dataSource },
        {
          // PaymentsService logs every financial step; a silent double keeps the
          // test output readable while still satisfying the DI graph.
          provide: CustomLogger,
          useValue: {
            log: jest.fn(),
            warn: jest.fn(),
            error: jest.fn(),
            debug: jest.fn(),
            verbose: jest.fn(),
            setContext: jest.fn(),
          },
        },
      ],
    }).compile();

    service = module.get<PaymentsService>(PaymentsService);
  });

  it('should be defined', () => {
    expect(service).toBeDefined();
  });

  describe('processTripPayment', () => {
    const dto: ProcessTripPaymentDto = {
      tripId: 'trip-1',
      idempotencyKey: 'idem-abc-123',
    };

    it('should return existing SUCCESS payment if idempotency key matches (no double-charge)', async () => {
      const existingPayment = {
        id: 'pay-1',
        status: PaymentRecordStatus.SUCCESS,
        tripId: 'trip-1',
      };
      paymentRepo.findOne.mockResolvedValue(existingPayment);

      const result = await service.processTripPayment('pass-user-1', dto);

      expect(result).toEqual(existingPayment);
      expect(dataSource.transaction).not.toHaveBeenCalled();
      expect(walletsService.atomicTransferFromTrip).not.toHaveBeenCalled();
    });

    it('should throw PAYMENT_ALREADY_PROCESSED when idempotency key matches PENDING payment', async () => {
      const existingPayment = {
        id: 'pay-1',
        status: PaymentRecordStatus.PENDING,
        tripId: 'trip-1',
      };
      paymentRepo.findOne.mockResolvedValue(existingPayment);

      await expect(service.processTripPayment('pass-user-1', dto)).rejects.toThrow(
        DomainException,
      );
      await expect(service.processTripPayment('pass-user-1', dto)).rejects.toMatchObject(
        { code: ErrorCode.PAYMENT_ALREADY_PROCESSED },
      );
    });

    it('rejects a key reused for a different trip with IDEMPOTENCY_CONFLICT', async () => {
      paymentRepo.findOne.mockResolvedValue({
        id: 'pay-1',
        status: PaymentRecordStatus.SUCCESS,
        tripId: 'some-other-trip',
      });

      await expect(
        service.processTripPayment('pass-user-1', dto),
      ).rejects.toMatchObject({ code: ErrorCode.IDEMPOTENCY_CONFLICT });
      expect(dataSource.transaction).not.toHaveBeenCalled();
    });

    it('scopes the idempotency lookup to the authenticated passenger', async () => {
      paymentRepo.findOne.mockResolvedValue(null);
      tripsService.findById.mockResolvedValue(makeTrip());

      await service.processTripPayment('pass-user-1', dto);

      // A global key lookup would let one user's request collide with another's.
      expect(paymentRepo.findOne).toHaveBeenCalledWith({
        where: {
          passengerId: 'pass-user-1',
          idempotencyKey: dto.idempotencyKey,
        },
      });
    });

    it('should throw TRIP_NOT_OWNED when passenger does not own the trip', async () => {
      paymentRepo.findOne.mockResolvedValue(null);
      tripsService.findById.mockResolvedValue(makeTrip({ passengerId: 'different-user' }));

      await expect(service.processTripPayment('pass-user-1', dto)).rejects.toThrow(
        DomainException,
      );
      await expect(service.processTripPayment('pass-user-1', dto)).rejects.toMatchObject(
        { code: ErrorCode.TRIP_NOT_OWNED },
      );
    });

    it('should throw TRIP_ALREADY_PAID when trip.paymentStatus === PAID', async () => {
      paymentRepo.findOne.mockResolvedValue(null);
      tripsService.findById.mockResolvedValue(
        makeTrip({ paymentStatus: PaymentStatus.PAID }),
      );

      await expect(service.processTripPayment('pass-user-1', dto)).rejects.toThrow(
        DomainException,
      );
      await expect(service.processTripPayment('pass-user-1', dto)).rejects.toMatchObject(
        { code: ErrorCode.TRIP_ALREADY_PAID },
      );
    });

    it('should process payment atomically: debit passenger, credit driver, mark paid, notify', async () => {
      paymentRepo.findOne.mockResolvedValue(null);
      tripsService.findById.mockResolvedValue(makeTrip());

      const result = await service.processTripPayment('pass-user-1', dto);

      expect(dataSource.transaction).toHaveBeenCalled();
      expect(walletsService.atomicTransferFromTrip).toHaveBeenCalledWith(
        expect.anything(),
        'pass-user-1',
        'driver-user-1',
        8500,
        'test-payment-id',
        'trip-1',
      );
      expect(tripsService.markPaid).toHaveBeenCalledWith(
        expect.anything(),
        'trip-1',
        'test-payment-id',
      );
      expect(result.status).toEqual(PaymentRecordStatus.SUCCESS);
      expect(result.receiptNumber).toMatch(/^SEM-\d{4}-\d{6}$/);
      expect(result.provider).toEqual(PaymentProvider.MOCK);
      expect(result.amount).toEqual(8500);
      expect(notificationsService.sendPushNotification).toHaveBeenCalledTimes(2);
    });

    it('should mark payment FAILED and rethrow on atomicTransferFromTrip failure (rollback invariant)', async () => {
      paymentRepo.findOne.mockResolvedValue(null);
      tripsService.findById.mockResolvedValue(makeTrip());

      walletsService.atomicTransferFromTrip.mockRejectedValue(
        new DomainException(
          'Insufficient wallet balance',
          400,
          ErrorCode.WALLET_INSUFFICIENT_BALANCE,
        ),
      );

      await expect(service.processTripPayment('pass-user-1', dto)).rejects.toThrow(
        DomainException,
      );
      await expect(service.processTripPayment('pass-user-1', dto)).rejects.toMatchObject(
        { code: ErrorCode.WALLET_INSUFFICIENT_BALANCE },
      );
      expect(tripsService.markPaid).not.toHaveBeenCalled();
    });
  });
});
