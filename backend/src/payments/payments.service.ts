import { Injectable, HttpStatus } from '@nestjs/common';
import { InjectRepository } from '@nestjs/typeorm';
import { Repository, DataSource, EntityManager } from 'typeorm';
import { Payment } from './entities/payment.entity';
import { ProcessTripPaymentDto } from './dto/payment.dto';
import { WalletsService } from '../wallets/wallets.service';
import { TripsService } from '../trips/trips.service';
import { NotificationsService } from '../notifications/notifications.service';
import { DomainException } from '../common/domain.exception';
import { ErrorCode } from '../common/error-codes';
import {
  PaymentRecordStatus,
  PaymentStatus,
  PaymentProvider,
} from '../common/enums';
import { CustomLogger } from '../common/logger/custom.logger';

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

    const existingByIdem = await this.paymentRepository.findOne({
      where: { idempotencyKey: dto.idempotencyKey },
    });
    if (existingByIdem) {
      this.logger.warn('Idempotent payment request received', PaymentsService.name, {
        paymentId: existingByIdem.id,
        status: existingByIdem.status,
        idempotencyKey: dto.idempotencyKey,
      });
      if (
        existingByIdem.status === PaymentRecordStatus.SUCCESS ||
        existingByIdem.status === PaymentRecordStatus.PENDING
      ) {
        if (existingByIdem.status === PaymentRecordStatus.SUCCESS) {
          return existingByIdem;
        }
        throw new DomainException(
          'Payment is being processed',
          HttpStatus.CONFLICT,
          ErrorCode.PAYMENT_ALREADY_PROCESSED,
        );
      }
    }

    const trip = await this.tripsService.findById(dto.tripId);

    if (trip.passengerId !== passengerUserId) {
      this.logger.error('Trip does not belong to passenger', undefined, PaymentsService.name, {
        passengerUserId,
        tripId: dto.tripId,
        tripOwnerId: trip.passengerId,
      });
      throw new DomainException(
        'Trip does not belong to this passenger',
        HttpStatus.FORBIDDEN,
        ErrorCode.TRIP_NOT_OWNED,
      );
    }

    if (trip.paymentStatus === PaymentStatus.PAID) {
      this.logger.error('Trip already paid', undefined, PaymentsService.name, {
        tripId: dto.tripId,
      });
      throw new DomainException(
        'Trip has already been paid',
        HttpStatus.BAD_REQUEST,
        ErrorCode.TRIP_ALREADY_PAID,
      );
    }

    const fareAmount = trip.fareAmount;
    const receiptNumber = `SEM-${new Date().getFullYear()}-${this.pad6(
      (await this.countToday()) + 1,
    )}`;

    return this.dataSource.transaction(async (manager: EntityManager) => {
      this.logger.log('Starting payment transaction', PaymentsService.name, {
        tripId: trip.id,
        passengerUserId,
        driverId: trip.driverId,
        fareAmount,
      });

      const payment = manager.create(Payment, {
        tripId: trip.id,
        passengerId: passengerUserId,
        driverId: trip.driverId,
        routeId: trip.routeId,
        amount: fareAmount,
        currency: trip.currency,
        status: PaymentRecordStatus.PENDING,
        provider: PaymentProvider.MOCK,
        idempotencyKey: dto.idempotencyKey,
      });
      const savedPayment = await manager.save(payment);

      this.logger.log('Payment record created as PENDING', PaymentsService.name, {
        paymentId: savedPayment.id,
        tripId: trip.id,
        passengerUserId,
        driverId: trip.driverId,
      });

      try {
        await this.walletsService.atomicTransferFromTrip(
          manager,
          passengerUserId,
          trip.driverId,
          fareAmount,
          savedPayment.id,
          trip.id,
        );

        savedPayment.status = PaymentRecordStatus.SUCCESS;
        savedPayment.providerReference = `MOCK-${savedPayment.id}`;
        savedPayment.receiptNumber = receiptNumber;
        savedPayment.completedAt = new Date();
        await manager.save(savedPayment);

        await this.tripsService.markPaid(manager, trip.id, savedPayment.id);

        this.logger.log('Payment transaction SUCCESS', PaymentsService.name, {
          paymentId: savedPayment.id,
          tripId: trip.id,
          passengerUserId,
          driverId: trip.driverId,
          receiptNumber,
        });

        try {
          this.notificationsService.sendPushNotification(
            passengerUserId,
            'Payment Successful',
            `You paid ${fareAmount / 100} ETB for your trip. Receipt: ${receiptNumber}`,
          );
          this.notificationsService.sendPushNotification(
            trip.driverId,
            'Payment Received',
            `You earned ${fareAmount / 100} ETB for a trip.`,
          );
        } catch (notifyErr) {
          this.logger.warn(`Notification failed: ${notifyErr.message}`, PaymentsService.name, {
            paymentId: savedPayment.id,
            tripId: trip.id,
            error: notifyErr.message,
          });
        }

        return savedPayment;
      } catch (err) {
        this.logger.error('Payment transaction FAILED', undefined, PaymentsService.name, {
          paymentId: savedPayment.id,
          tripId: trip.id,
          passengerUserId,
          driverId: trip.driverId,
          error: err.message,
        });

        try {
          savedPayment.status = PaymentRecordStatus.FAILED;
          await manager.save(savedPayment);
        } catch (_updateErr) {
          this.logger.error('Failed to update payment status to FAILED', undefined, PaymentsService.name, {
            paymentId: savedPayment.id,
            error: _updateErr.message,
          });
        }
        throw err;
      }
    });
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

  private pad6(n: number): string {
    return n.toString().padStart(6, '0');
  }

  private async countToday(): Promise<number> {
    const start = new Date();
    start.setHours(0, 0, 0, 0);
    return this.paymentRepository
      .createQueryBuilder('p')
      .where('p.createdAt >= :start', { start })
      .getCount();
  }
}
