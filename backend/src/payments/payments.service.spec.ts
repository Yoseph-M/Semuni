import { Test, TestingModule } from '@nestjs/testing';
import { PaymentsService } from './payments.service';
import { getRepositoryToken } from '@nestjs/typeorm';
import { Payment } from './entities/payment.entity';
import { Trip } from '../trips/entities/trip.entity';
import { WalletsService } from '../wallets/wallets.service';
import { TripsService } from '../trips/trips.service';
import { NotificationsService } from '../notifications/notifications.service';
import { DataSource } from 'typeorm';
import { CustomLogger } from '../common/logger/custom.logger';
import {
  PaymentRecordStatus,
  PaymentStatus,
  Currency,
  LedgerEntryType,
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
    status: 'PENDING',
    createdAt: new Date(),
    ...overrides,
  });

  /** Transaction manager whose locked reads answer from the given rows. */
  const makeManager = (trip: any, payment: any) => {
    const manager: any = {
      findOne: jest.fn().mockImplementation((entity: any) => {
        if (entity === Trip) return Promise.resolve(trip);
        if (entity === Payment) return Promise.resolve(payment);
        return Promise.resolve(null);
      }),
      save: jest.fn().mockImplementation((e: any) => Promise.resolve(e)),
      query: jest.fn().mockResolvedValue([{ nextval: '42' }]),
    };
    return manager;
  };

  beforeEach(async () => {
    paymentRepo = {
      findOne: jest.fn(),
      create: jest.fn().mockImplementation((data) => ({ id: 'attempt-1', ...data })),
      save: jest.fn().mockImplementation((e) => Promise.resolve(e)),
      update: jest.fn().mockResolvedValue({ affected: 1 }),
    };

    walletsService = {
      transferWallet: jest.fn().mockResolvedValue({}),
    };

    tripsService = {
      findById: jest.fn(),
      markPaid: jest.fn().mockResolvedValue(undefined),
    };

    notificationsService = {
      sendPushNotification: jest.fn().mockResolvedValue(true),
    };

    dataSource = {
      transaction: jest.fn(),
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

  describe('processTripPayment — idempotency', () => {
    const dto: ProcessTripPaymentDto = {
      tripId: 'trip-1',
      idempotencyKey: 'idem-abc-123',
    };

    it('returns the existing SUCCESS payment for the same key and trip, moving no money', async () => {
      const existingPayment = {
        id: 'pay-1',
        status: PaymentRecordStatus.SUCCESS,
        tripId: 'trip-1',
      };
      paymentRepo.findOne.mockResolvedValue(existingPayment);

      const result = await service.processTripPayment('pass-user-1', dto);

      expect(result).toEqual(existingPayment);
      expect(dataSource.transaction).not.toHaveBeenCalled();
      expect(walletsService.transferWallet).not.toHaveBeenCalled();
    });

    it('rejects the same key with a different trip payload', async () => {
      paymentRepo.findOne.mockResolvedValue({
        id: 'pay-1',
        status: PaymentRecordStatus.SUCCESS,
        tripId: 'trip-OTHER',
      });

      await expect(
        service.processTripPayment('pass-user-1', dto),
      ).rejects.toMatchObject({ code: ErrorCode.IDEMPOTENCY_CONFLICT });
      expect(walletsService.transferWallet).not.toHaveBeenCalled();
    });

    it('rejects a replayed key whose attempt is still in flight', async () => {
      paymentRepo.findOne.mockResolvedValue({
        id: 'pay-1',
        status: PaymentRecordStatus.PENDING,
        tripId: 'trip-1',
      });

      await expect(
        service.processTripPayment('pass-user-1', dto),
      ).rejects.toMatchObject({ code: ErrorCode.PAYMENT_ALREADY_PROCESSED });
    });

    it('rejects a replayed key whose attempt already failed', async () => {
      paymentRepo.findOne.mockResolvedValue({
        id: 'pay-1',
        status: PaymentRecordStatus.FAILED,
        tripId: 'trip-1',
      });

      await expect(
        service.processTripPayment('pass-user-1', dto),
      ).rejects.toMatchObject({ code: ErrorCode.PAYMENT_FAILED });
    });
  });

  describe('processTripPayment — settlement', () => {
    const dto: ProcessTripPaymentDto = {
      tripId: 'trip-1',
      idempotencyKey: 'idem-settle-1',
    };

    it('settles from the locked trip: transfer, receipt from the sequence, trip marked paid', async () => {
      paymentRepo.findOne.mockResolvedValue(null);
      tripsService.findById.mockResolvedValue(makeTrip());

      const payment = {
        id: 'attempt-1',
        tripId: 'trip-1',
        passengerId: 'pass-user-1',
        driverId: 'driver-user-1',
        amount: 8500,
        currency: Currency.ETB,
        status: PaymentRecordStatus.PENDING,
      };
      const manager = makeManager(makeTrip(), payment);
      dataSource.transaction.mockImplementation(async (cb: any) => cb(manager));

      const result = await service.processTripPayment('pass-user-1', dto);

      expect(walletsService.transferWallet).toHaveBeenCalledWith(
        manager,
        'pass-user-1',
        'driver-user-1',
        8500,
        expect.objectContaining({
          currency: Currency.ETB,
          debit: expect.objectContaining({
            entryType: LedgerEntryType.TRIP_PAYMENT,
            transactionId: 'attempt-1',
            referenceType: 'TRIP',
            referenceId: 'trip-1',
          }),
          credit: expect.objectContaining({
            entryType: LedgerEntryType.DRIVER_EARNING,
            transactionId: 'attempt-1',
          }),
        }),
      );
      expect(result.status).toBe(PaymentRecordStatus.SUCCESS);
      expect(result.receiptNumber).toBe('SEM-' + new Date().getFullYear() + '-000042');
      expect(result.completedAt).toBeInstanceOf(Date);
      expect(tripsService.markPaid).toHaveBeenCalledWith(manager, 'trip-1', 'attempt-1');
      expect(notificationsService.sendPushNotification).toHaveBeenCalledTimes(2);
    });

    it('CRITICAL: the locked trip — not the pre-flight read — decides the amount charged', async () => {
      paymentRepo.findOne.mockResolvedValue(null);
      // The pre-flight read sees one fare…
      tripsService.findById.mockResolvedValue(makeTrip({ fareAmount: 8500 }));
      // …but the authoritative, locked row is what the transaction settles.
      const lockedTrip = makeTrip({ fareAmount: 9200 });
      const payment = { id: 'attempt-1', tripId: 'trip-1', status: PaymentRecordStatus.PENDING };
      const manager = makeManager(lockedTrip, payment);
      dataSource.transaction.mockImplementation(async (cb: any) => cb(manager));

      const result = await service.processTripPayment('pass-user-1', dto);

      expect(walletsService.transferWallet).toHaveBeenCalledWith(
        manager,
        'pass-user-1',
        'driver-user-1',
        9200,
        expect.anything(),
      );
      expect(result.amount).toBe(9200);
    });

    it('CRITICAL: a concurrent payer who won the trip lock is detected inside the transaction', async () => {
      paymentRepo.findOne.mockResolvedValue(null);
      tripsService.findById.mockResolvedValue(makeTrip());
      // By the time we hold the lock the trip is already PAID.
      const manager = makeManager(
        makeTrip({ paymentStatus: PaymentStatus.PAID }),
        { id: 'attempt-1', tripId: 'trip-1', status: PaymentRecordStatus.PENDING },
      );
      dataSource.transaction.mockImplementation(async (cb: any) => cb(manager));

      await expect(
        service.processTripPayment('pass-user-1', dto),
      ).rejects.toMatchObject({ code: ErrorCode.TRIP_ALREADY_PAID });

      expect(walletsService.transferWallet).not.toHaveBeenCalled();
      expect(tripsService.markPaid).not.toHaveBeenCalled();
      // The losing attempt is still recorded, in its own durable write.
      expect(paymentRepo.update).toHaveBeenCalledWith(
        { id: 'attempt-1', status: PaymentRecordStatus.PENDING },
        expect.objectContaining({
          status: PaymentRecordStatus.FAILED,
          failureReason: ErrorCode.TRIP_ALREADY_PAID,
        }),
      );
    });

    it('CRITICAL: a rolled-back payment leaves a durable FAILED attempt', async () => {
      paymentRepo.findOne.mockResolvedValue(null);
      tripsService.findById.mockResolvedValue(makeTrip());
      walletsService.transferWallet.mockRejectedValue(
        new DomainException(
          'Insufficient wallet balance',
          400,
          ErrorCode.WALLET_INSUFFICIENT_BALANCE,
        ),
      );
      const manager = makeManager(makeTrip(), {
        id: 'attempt-1',
        tripId: 'trip-1',
        status: PaymentRecordStatus.PENDING,
      });
      dataSource.transaction.mockImplementation(async (cb: any) => cb(manager));

      await expect(
        service.processTripPayment('pass-user-1', dto),
      ).rejects.toMatchObject({ code: ErrorCode.WALLET_INSUFFICIENT_BALANCE });

      expect(tripsService.markPaid).not.toHaveBeenCalled();
      expect(paymentRepo.update).toHaveBeenCalledWith(
        { id: 'attempt-1', status: PaymentRecordStatus.PENDING },
        expect.objectContaining({
          status: PaymentRecordStatus.FAILED,
          failureReason: ErrorCode.WALLET_INSUFFICIENT_BALANCE,
        }),
      );
      expect(notificationsService.sendPushNotification).not.toHaveBeenCalled();
    });

    it('maps a database unique violation on the trip index to TRIP_ALREADY_PAID', async () => {
      paymentRepo.findOne.mockResolvedValue(null);
      tripsService.findById.mockResolvedValue(makeTrip());
      const manager = makeManager(makeTrip(), {
        id: 'attempt-1',
        tripId: 'trip-1',
        status: PaymentRecordStatus.PENDING,
      });
      manager.save = jest.fn().mockRejectedValue({
        code: '23505',
        constraint: 'UQ_payments_trip_success',
      });
      dataSource.transaction.mockImplementation(async (cb: any) => cb(manager));

      await expect(
        service.processTripPayment('pass-user-1', dto),
      ).rejects.toMatchObject({ code: ErrorCode.TRIP_ALREADY_PAID });
    });

    it('refuses to pay a trip owned by another passenger', async () => {
      paymentRepo.findOne.mockResolvedValue(null);
      tripsService.findById.mockResolvedValue(
        makeTrip({ passengerId: 'someone-else' }),
      );

      await expect(
        service.processTripPayment('pass-user-1', dto),
      ).rejects.toMatchObject({ code: ErrorCode.TRIP_NOT_OWNED });

      expect(paymentRepo.save).not.toHaveBeenCalled();
      expect(dataSource.transaction).not.toHaveBeenCalled();
    });

    it('refuses to pay a trip with no valid fare instead of writing a zero-amount payment', async () => {
      paymentRepo.findOne.mockResolvedValue(null);
      tripsService.findById.mockResolvedValue(makeTrip({ fareAmount: 0 }));

      await expect(
        service.processTripPayment('pass-user-1', dto),
      ).rejects.toMatchObject({ code: ErrorCode.FARE_CALCULATION_FAILED });

      expect(paymentRepo.save).not.toHaveBeenCalled();
    });

    it('does not let a notification failure affect a settled payment', async () => {
      paymentRepo.findOne.mockResolvedValue(null);
      tripsService.findById.mockResolvedValue(makeTrip());
      notificationsService.sendPushNotification.mockRejectedValue(
        new Error('push provider down'),
      );
      const manager = makeManager(makeTrip(), {
        id: 'attempt-1',
        tripId: 'trip-1',
        status: PaymentRecordStatus.PENDING,
      });
      dataSource.transaction.mockImplementation(async (cb: any) => cb(manager));

      const result = await service.processTripPayment('pass-user-1', dto);

      expect(result.status).toBe(PaymentRecordStatus.SUCCESS);
      // Let the fire-and-forget notification rejections settle; they must not
      // surface as unhandled errors or affect the result.
      await new Promise((resolve) => setImmediate(resolve));
    });
  });
});
