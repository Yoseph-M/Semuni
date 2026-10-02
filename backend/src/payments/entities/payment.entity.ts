import { Entity, Column, Index, Check, ManyToOne, JoinColumn } from 'typeorm';
import { User } from '../../users/entities/user.entity';
import { Trip } from '../../trips/entities/trip.entity';
import { Route } from '../../routes/entities/route.entity';
import { BaseEntity } from '../../common/entities/base.entity';
import { PaymentRecordStatus, Currency, PaymentProvider } from '../../common/enums';

@Entity('payments')
@Check('CHK_payment_amount_positive', '"amount" > 0')
// An idempotency key is only meaningful to the user who generated it, so
// uniqueness is scoped to the payer. A key must never be treated as a global
// namespace: two different passengers are allowed to pick the same string.
@Index('UQ_payments_passenger_idempotency', ['passengerId', 'idempotencyKey'], {
  unique: true,
})
// A trip may have several durable *attempts* (PENDING / FAILED) but exactly one
// payment that moved money. A blanket UNIQUE(tripId) would make a failed attempt
// permanently unpayable, so uniqueness is partial: only SUCCESS counts.
@Index('UQ_payments_trip_success', ['tripId'], {
  unique: true,
  where: `"status" = 'SUCCESS'`,
})
@Index('UQ_payments_provider_reference', ['providerReference'], {
  unique: true,
  where: '"providerReference" IS NOT NULL',
})
@Index('UQ_payments_receipt_number', ['receiptNumber'], {
  unique: true,
  where: '"receiptNumber" IS NOT NULL',
})
export class Payment extends BaseEntity {
  @Column({ type: 'uuid' })
  @Index()
  tripId: string;

  @ManyToOne(() => Trip)
  @JoinColumn({ name: 'tripId', foreignKeyConstraintName: 'FK_payments_tripId' })
  trip?: Trip;

  @Column({ type: 'uuid' })
  @Index()
  passengerId: string;

  @ManyToOne(() => User)
  @JoinColumn({ name: 'passengerId', foreignKeyConstraintName: 'FK_payments_passengerId' })
  passenger?: User;

  @Column({ type: 'uuid' })
  @Index()
  driverId: string;

  @ManyToOne(() => User)
  @JoinColumn({ name: 'driverId', foreignKeyConstraintName: 'FK_payments_driverId' })
  driver?: User;

  @Column({ type: 'uuid', nullable: true })
  @Index('IDX_payments_routeId')
  routeId?: string;

  @ManyToOne(() => Route)
  @JoinColumn({ name: 'routeId', foreignKeyConstraintName: 'FK_payments_routeId' })
  route?: Route;

  @Column({ type: 'int' })
  amount: number;

  @Column({ type: 'enum', enum: Currency, default: Currency.ETB })
  currency: Currency;

  @Column({ type: 'enum', enum: PaymentRecordStatus, default: PaymentRecordStatus.PENDING })
  status: PaymentRecordStatus;

  @Column({ type: 'enum', enum: PaymentProvider, default: PaymentProvider.MOCK })
  provider: PaymentProvider;

  @Column({ nullable: true })
  providerReference?: string;

  @Column()
  idempotencyKey: string;

  @Column({ nullable: true })
  receiptNumber?: string;

  /**
   * Why an attempt ended in FAILED. Attempts are durable rows rather than
   * rolled-back writes, so the reason is stored where an operator can read it.
   */
  @Column({ nullable: true })
  failureReason?: string;

  @Column({ type: 'timestamp with time zone', nullable: true })
  completedAt?: Date;
}
