import { Entity, Column, Index, Check, ManyToOne, JoinColumn } from 'typeorm';
import { User } from '../../users/entities/user.entity';
import { BaseEntity } from '../../common/entities/base.entity';
import {
  WithdrawalStatus,
  WithdrawalDestinationType,
  Currency,
  PaymentProvider,
} from '../../common/enums';

@Entity('withdrawals')
@Check('CHK_withdrawal_amount_positive', '"amount" > 0')
// Idempotency keys belong to the driver who sent them, so uniqueness is scoped
// to the owner rather than global.
@Index('UQ_withdrawals_user_idempotency', ['userId', 'idempotencyKey'], {
  unique: true,
})
export class Withdrawal extends BaseEntity {
  @Column({ type: 'uuid' })
  @Index()
  userId: string;

  @ManyToOne(() => User)
  @JoinColumn({ name: 'userId', foreignKeyConstraintName: 'FK_withdrawals_userId' })
  user?: User;

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

  @Column({ nullable: true })
  idempotencyKey?: string;

  @Column({ nullable: true })
  externalReference?: string;

  @Column({ type: 'timestamp with time zone', nullable: true })
  completedAt?: Date;
}
