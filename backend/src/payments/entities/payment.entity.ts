import { Entity, Column, Index } from 'typeorm';
import { BaseEntity } from '../../common/entities/base.entity';
import { PaymentRecordStatus, Currency, PaymentProvider } from '../../common/enums';

@Entity('payments')
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

  @Column({ unique: true })
  idempotencyKey: string;

  @Column({ nullable: true })
  receiptNumber?: string;

  @Column({ type: 'timestamp with time zone', nullable: true })
  completedAt?: Date;
}
