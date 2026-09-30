import { Entity, Column, Index } from 'typeorm';
import { BaseEntity } from '../../common/entities/base.entity';
import {
  WithdrawalStatus,
  WithdrawalDestinationType,
  Currency,
  PaymentProvider,
} from '../../common/enums';

@Entity('withdrawals')
export class Withdrawal extends BaseEntity {
  @Column()
  @Index()
  userId: string;

  @Column({ type: 'int' })
  amount: number;

  @Column({ type: 'enum', enum: Currency, default: Currency.ETB })
  currency: Currency;

  @Column({ type: 'enum', enum: WithdrawalStatus, default: WithdrawalStatus.PENDING })
  status: WithdrawalStatus;

  @Column({
    type: 'enum',
    enum: WithdrawalDestinationType,
    default: WithdrawalDestinationType.BANK,
  })
  destinationType: WithdrawalDestinationType;

  @Column({ nullable: true })
  destination?: string;

  @Column({ nullable: true })
  destinationAccount?: string;

  @Column({ type: 'enum', enum: PaymentProvider, default: PaymentProvider.MOCK })
  provider: PaymentProvider;

  @Column({ nullable: true, unique: true })
  idempotencyKey?: string;

  @Column({ nullable: true })
  externalReference?: string;

  @Column({ type: 'timestamp with time zone', nullable: true })
  completedAt?: Date;
}
