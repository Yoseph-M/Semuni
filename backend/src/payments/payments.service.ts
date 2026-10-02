import { Injectable, HttpStatus } from '@nestjs/common';
import { InjectRepository } from '@nestjs/typeorm';
import { Repository, DataSource, EntityManager } from 'typeorm';
import { Payment } from './entities/payment.entity';
import { Trip } from '../trips/entities/trip.entity';
import { ProcessTripPaymentDto } from './dto/payment.dto';
import { WalletsService } from '../wallets/wallets.service';
import { TripsService } from '../trips/trips.service';
import { NotificationsService } from '../notifications/notifications.service';
import { DomainException } from '../common/domain.exception';
import { ErrorCode } from '../common/error-codes';
import {
  LedgerEntryType,
  PaymentRecordStatus,
  PaymentStatus,
  PaymentProvider,
  TripStatus,
  UserRole,
} from '../common/enums';
import { CustomLogger } from '../common/logger/custom.logger';

/** PostgreSQL SQLSTATE for a unique-constraint violation. */
const PG_UNIQUE_VIOLATION = '23505';

/**
 * Trip fare settlement.
 *
 * The shape of a payment is deliberately:
 *
 *   1. resolve idempotency (owner + key + payload)
 *   2. record a durable PENDING attempt — it survives a financial rollback, so a
 *      failure is auditable instead of vanishing with the transaction
 *   3. run one transaction that locks the trip, re-checks it, moves the money,
 *      settles the attempt, marks the trip PAID/COMPLETED
 *   4. only after the commit, notify the two participants
 *
 * Nothing inside step 3 trusts the pre-transaction read: a payment request that
 * arrives while another one is settling must observe the locked, current trip.
 */
@Injectable()
export class PaymentsService {
  constructor(
    @InjectRepository(Payment)
    private readonly paymentRepository: Repository<Payment>,
    private readonly walletsService: WalletsService,
    private readonly tripsService: TripsService,
    private readonly notificationsService: NotificationsService,
    private readonly dataSource: DataSource,
    private readonly logger: CustomLogger,
  ) {}

  async processTripPayment(
    passengerUserId: string,
    dto: ProcessTripPaymentDto,
  ): Promise<Payment> {
    this.logger.log('Processing trip payment', PaymentsService.name, {
      passengerUserId,
      tripId: dto.tripId,
      idempotencyKey: dto.idempotencyKey,
    });

    // ── 1. Idempotency ───────────────────────────────────────────────────────
    // Keys are scoped to the authenticated passenger. A global lookup would let
    // one user's key collide with — or return — another user's payment.
    const replay = await this.findByIdempotencyKey(
      passengerUserId,
      dto.idempotencyKey,
    );
    if (replay) return this.resolveIdempotentReplay(replay, dto);

    // ── 2. Pre-flight, advisory only ─────────────────────────────────────────
    // These checks produce fast, precise errors; the authoritative ones run
    // again under the trip lock below.
    const preflightTrip = await this.tripsService.findById(dto.tripId);
    this.assertPayableBy(preflightTrip, passengerUserId);

    // ── 3. Durable attempt record ────────────────────────────────────────────
    // Committed before any money moves, so a later rollback cannot erase the
    // fact that an attempt happened.
    let attempt: Payment;
    try {
      attempt = await this.paymentRepository.save(
        this.paymentRepository.create({
          tripId: preflightTrip.id,
          passengerId: passengerUserId,
          driverId: preflightTrip.driverId,
          routeId: preflightTrip.routeId,
          amount: preflightTrip.fareAmount,
          currency: preflightTrip.currency,
          status: PaymentRecordStatus.PENDING,
          provider: PaymentProvider.MOCK,
          idempotencyKey: dto.idempotencyKey,
        }),
      );
    } catch (err) {
      // A concurrent request using the same key won the insert. Its outcome is
      // the answer to this request too — that is what idempotency means.
      if (this.isUniqueViolation(err)) {
        const concurrent = await this.findByIdempotencyKey(
          passengerUserId,
          dto.idempotencyKey,
        );
        if (concurrent) return this.resolveIdempotentReplay(concurrent, dto);
      }
      throw err;
    }

    // ── 4. One transaction: money, ledger, attempt and trip move together ────
    let settled: Payment;
    try {
      settled = await this.dataSource.transaction((manager: EntityManager) =>
        this.settle(manager, attempt, passengerUserId),
      );
    } catch (rawErr) {
      // The financial transaction rolled back, taking its wallet, ledger and
      // attempt updates with it. The FAILED state is written separately, so the
      // attempt survives as a durable record rather than disappearing.
      const err = this.translateConstraintViolation(rawErr);
      await this.recordAttemptFailure(attempt.id, err);
      throw err;
    }

    this.logger.log('Payment transaction SUCCESS', PaymentsService.name, {
      paymentId: settled.id,
      tripId: settled.tripId,
      passengerUserId,
      driverId: settled.driverId,
      receiptNumber: settled.receiptNumber,
    });

    // ── 5. Side effects after the commit ─────────────────────────────────────
    // A notification failure must never roll back money that already moved.
    this.notifySettled(settled);

    return settled;
  }

  /**
   * The financial transaction.
   *
   * Runs entirely from state read *inside* the transaction, under locks:
   * a concurrent payment for the same trip blocks on the trip row, then sees
   * `paymentStatus = PAID` and is rejected before it can move any money.
   */
  private async settle(
    manager: EntityManager,
    attempt: Payment,
    passengerUserId: string,
  ): Promise<Payment> {
    const trip = await manager.findOne(Trip, {
      where: { id: attempt.tripId },
      lock: { mode: 'pessimistic_write' },
    });
    if (!trip) {
      throw new DomainException(
        'Trip not found',
        HttpStatus.NOT_FOUND,
        ErrorCode.TRIP_NOT_FOUND,
      );
    }

    // Re-checked under the lock: ownership, payability and the fare to charge.
    this.assertPayableBy(trip, passengerUserId);

    const payment = await manager.findOne(Payment, {
      where: { id: attempt.id },
      lock: { mode: 'pessimistic_write' },
    });
    if (!payment) {
      throw new DomainException(
        'Payment not found',
        HttpStatus.NOT_FOUND,
        ErrorCode.PAYMENT_NOT_FOUND,
      );
    }
    if (payment.status === PaymentRecordStatus.SUCCESS) {
      // Already settled under this attempt (retry of a committed transaction).
      return payment;
    }

    // The locked trip — never the client and never the pre-transaction read —
    // decides what is charged and to whom.
    payment.amount = trip.fareAmount;
    payment.currency = trip.currency;
    payment.driverId = trip.driverId;
    payment.routeId = trip.routeId;

    await this.walletsService.transferWallet(
      manager,
      passengerUserId,
      trip.driverId,
      trip.fareAmount,
      {
        currency: trip.currency,
        debit: {
          entryType: LedgerEntryType.TRIP_PAYMENT,
          transactionId: payment.id,
          referenceType: 'TRIP',
          referenceId: trip.id,
          description: `Trip payment - ${trip.fareAmount / 100} ETB`,
        },
        credit: {
          entryType: LedgerEntryType.DRIVER_EARNING,
          transactionId: payment.id,
          referenceType: 'TRIP',
          referenceId: trip.id,
          description: `Trip earnings - ${trip.fareAmount / 100} ETB`,
        },
      },
    );

    payment.status = PaymentRecordStatus.SUCCESS;
    payment.providerReference = payment.providerReference ?? `MOCK-${payment.id}`;
    payment.receiptNumber = await this.nextReceiptNumber(manager);
    payment.completedAt = new Date();
    await manager.save(payment);

    await this.tripsService.markPaid(manager, trip.id, payment.id);

    return payment;
  }

  async getMyPayments(userId: string): Promise<Payment[]> {
    return this.paymentRepository.find({
      where: [{ passengerId: userId }, { driverId: userId }],
      order: { createdAt: 'DESC' },
      take: 50,
    });
  }

  async findById(paymentId: string): Promise<Payment> {
    const payment = await this.paymentRepository.findOne({
      where: { id: paymentId },
    });
    if (!payment) {
      throw new DomainException(
        'Payment not found',
        HttpStatus.NOT_FOUND,
        ErrorCode.PAYMENT_NOT_FOUND,
      );
    }
    return payment;
  }

  /**
   * Loads a payment only for a caller entitled to see it: the paying passenger,
   * the driver who was paid, or an ADMIN (explicit privileged branch). Anyone
   * else gets 403 PAYMENT_NOT_OWNED — knowing a UUID is not authorization.
   */
  async findByIdForUser(
    paymentId: string,
    user: { id: string; role: UserRole },
  ): Promise<Payment> {
    const payment = await this.findById(paymentId);

    const isParticipant =
      payment.passengerId === user.id || payment.driverId === user.id;
    if (!isParticipant && user.role !== UserRole.ADMIN) {
      throw new DomainException(
        'Payment does not belong to this user',
        HttpStatus.FORBIDDEN,
        ErrorCode.PAYMENT_NOT_OWNED,
      );
    }

    return payment;
  }

  // ─── Internals ─────────────────────────────────────────────────────────────

  private findByIdempotencyKey(
    passengerId: string,
    idempotencyKey: string,
  ): Promise<Payment | null> {
    return this.paymentRepository.findOne({
      where: { passengerId, idempotencyKey },
    });
  }

  /**
   * Same owner + same key + same payload means the same request: the original
   * result is returned. A different payload under a used key is a conflict —
   * treating it as a retry would silently answer a question nobody asked.
   */
  private resolveIdempotentReplay(
    existing: Payment,
    dto: ProcessTripPaymentDto,
  ): Payment {
    if (existing.tripId !== dto.tripId) {
      this.logger.warn(
        'Idempotency key reused for a different trip',
        PaymentsService.name,
        {
          paymentId: existing.id,
          existingTripId: existing.tripId,
          requestedTripId: dto.tripId,
          idempotencyKey: dto.idempotencyKey,
        },
      );
      throw new DomainException(
        'This idempotency key was already used for a different trip',
        HttpStatus.CONFLICT,
        ErrorCode.IDEMPOTENCY_CONFLICT,
      );
    }

    switch (existing.status) {
      case PaymentRecordStatus.SUCCESS:
        // Same request ⇒ same result. No second charge.
        return existing;
      case PaymentRecordStatus.PENDING:
        throw new DomainException(
          'Payment is being processed',
          HttpStatus.CONFLICT,
          ErrorCode.PAYMENT_ALREADY_PROCESSED,
        );
      case PaymentRecordStatus.FAILED:
        // Terminal for this key: a genuinely new attempt must use a new key.
        throw new DomainException(
          'Payment was already attempted and failed',
          HttpStatus.CONFLICT,
          ErrorCode.PAYMENT_FAILED,
        );
      default:
        throw new DomainException(
          `Payment was already ${existing.status.toLowerCase()}`,
          HttpStatus.CONFLICT,
          ErrorCode.PAYMENT_ALREADY_PROCESSED,
        );
    }
  }

  /**
   * Everything that must hold for a trip to be payable. Applied once before the
   * transaction (fast errors) and again inside it under the trip lock (truth).
   */
  private assertPayableBy(trip: Trip, passengerUserId: string): void {
    if (trip.passengerId !== passengerUserId) {
      this.logger.error(
        'Trip does not belong to passenger',
        undefined,
        PaymentsService.name,
        {
          passengerUserId,
          tripId: trip.id,
          tripOwnerId: trip.passengerId,
        },
      );
      throw new DomainException(
        'Trip does not belong to this passenger',
        HttpStatus.FORBIDDEN,
        ErrorCode.TRIP_NOT_OWNED,
      );
    }

    if (trip.paymentStatus === PaymentStatus.PAID) {
      this.logger.error('Trip already paid', undefined, PaymentsService.name, {
        tripId: trip.id,
      });
      throw new DomainException(
        'Trip has already been paid',
        HttpStatus.CONFLICT,
        ErrorCode.TRIP_ALREADY_PAID,
      );
    }

    if (
      trip.paymentStatus === PaymentStatus.COMPLETED ||
      trip.paymentStatus === PaymentStatus.REFUNDED ||
      trip.status === TripStatus.CANCELLED
    ) {
      throw new DomainException(
        `Trip is ${trip.status.toLowerCase()} and cannot be paid`,
        HttpStatus.BAD_REQUEST,
        ErrorCode.TRIP_NOT_PAYABLE,
      );
    }

    // A fare is only ever written by the fare engine from an active tariff.
    // Zero, negative or fractional values mean the trip row itself is corrupt.
    if (!Number.isInteger(trip.fareAmount) || trip.fareAmount <= 0) {
      throw new DomainException(
        'Trip has no valid fare to settle',
        HttpStatus.INTERNAL_SERVER_ERROR,
        ErrorCode.FARE_CALCULATION_FAILED,
      );
    }

    if (!trip.driverId || trip.driverId === trip.passengerId) {
      throw new DomainException(
        'Trip has no payable driver',
        HttpStatus.BAD_REQUEST,
        ErrorCode.TRIP_NOT_PAYABLE,
      );
    }
  }

  /**
   * Receipt numbers are allocated by a PostgreSQL sequence, so two concurrent
   * payments can never mint the same one. `UQ_payments_receipt_number` makes
   * that a database guarantee rather than a property of this method.
   */
  private async nextReceiptNumber(manager: EntityManager): Promise<string> {
    const rows: Array<{ nextval: string }> = await manager.query(
      `SELECT nextval('receipt_number_seq') AS nextval`,
    );
    const sequence = rows[0]?.nextval;
    return `SEM-${new Date().getFullYear()}-${String(sequence).padStart(6, '0')}`;
  }

  /** Writes the durable FAILED state, in its own transaction. */
  private async recordAttemptFailure(
    paymentId: string,
    err: unknown,
  ): Promise<void> {
    const reason =
      err instanceof DomainException
        ? err.code
        : err instanceof Error
          ? err.message
          : String(err);

    try {
      await this.paymentRepository.update(
        { id: paymentId, status: PaymentRecordStatus.PENDING },
        {
          status: PaymentRecordStatus.FAILED,
          failureReason: reason.slice(0, 500),
        },
      );
    } catch (updateErr) {
      this.logger.error(
        'Failed to persist payment failure state',
        (updateErr as Error).message,
        PaymentsService.name,
        { paymentId, reason },
      );
    }
  }

  /**
   * PostgreSQL is the last line of defence: even if two requests somehow both
   * passed the application checks, a unique violation must surface as a domain
   * error rather than a 500.
   */
  private translateConstraintViolation(err: unknown): unknown {
    const driverError = err as {
      code?: string;
      constraint?: string;
    };
    if (driverError?.code !== PG_UNIQUE_VIOLATION) return err;

    const constraint = driverError.constraint ?? '';
    if (constraint.includes('UQ_payments_trip_success')) {
      return new DomainException(
        'Trip has already been paid',
        HttpStatus.CONFLICT,
        ErrorCode.TRIP_ALREADY_PAID,
      );
    }
    if (constraint.includes('UQ_payments_passenger_idempotency')) {
      return new DomainException(
        'This idempotency key was already used for a payment',
        HttpStatus.CONFLICT,
        ErrorCode.IDEMPOTENCY_CONFLICT,
      );
    }
    if (constraint.startsWith('UQ_ledger')) {
      return new DomainException(
        'This payment was already recorded',
        HttpStatus.CONFLICT,
        ErrorCode.PAYMENT_ALREADY_PROCESSED,
      );
    }
    return err;
  }

  private isUniqueViolation(err: unknown): boolean {
    return (err as { code?: string })?.code === PG_UNIQUE_VIOLATION;
  }

  /** Best-effort, post-commit, and never able to affect the payment. */
  private notifySettled(payment: Payment): void {
    const deliver = (work: unknown): void => {
      void (async () => {
        try {
          await work;
        } catch (err) {
          this.logger.warn(
            `Notification failed: ${(err as Error).message}`,
            PaymentsService.name,
            { paymentId: payment.id, tripId: payment.tripId },
          );
        }
      })();
    };

    deliver(
      this.notificationsService.sendPushNotification(
        payment.passengerId,
        'Payment Successful',
        `You paid ${payment.amount / 100} ETB for your trip. Receipt: ${payment.receiptNumber}`,
      ),
    );
    deliver(
      this.notificationsService.sendPushNotification(
        payment.driverId,
        'Payment Received',
        `You earned ${payment.amount / 100} ETB for a trip.`,
      ),
    );
  }
}
