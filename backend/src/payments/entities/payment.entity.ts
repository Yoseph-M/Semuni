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

  @Column({ type: 'timestamp with time zone', nullable: true })
  completedAt?: Date;
}
