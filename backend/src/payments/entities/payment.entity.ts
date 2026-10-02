import { Entity, Column, Index } from 'typeorm';
import { BaseEntity } from '../../common/entities/base.entity';
import { PaymentRecordStatus, Currency, PaymentProvider } from '../../common/enums';

@Entity('payments')
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
  @Column()
  @Index()
  tripId: string;

  @Column()
  @Index()
  passengerId: string;

  @Column()
  @Index()
  driverId: string;

  @Column({ nullable: true })
  routeId?: string;

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
