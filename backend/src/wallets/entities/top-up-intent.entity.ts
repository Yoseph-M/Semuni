import { Entity, Column, ManyToOne, JoinColumn, Index } from 'typeorm';
import { BaseEntity } from '../../common/entities/base.entity';
import { User } from '../../users/entities/user.entity';
import {
  Currency,
  PaymentProvider,
  TopUpIntentStatus,
} from '../../common/enums';

@Entity('top_up_intents')
@Index('UQ_top_up_intents_user_idempotency', ['userId', 'idempotencyKey'], {
  unique: true,
})
@Index('UQ_top_up_intents_provider_reference', ['providerReference'], {
  unique: true,
  where: '"providerReference" IS NOT NULL',
})
export class TopUpIntent extends BaseEntity {
  @ManyToOne(() => User)
  @JoinColumn({ name: 'userId' })
  user: User;

  @Column({ type: 'uuid' })
  userId: string;

  /** Amount in minor units (santim). */
  @Column({ type: 'int' })
  amountMinor: number;

  @Column({ type: 'enum', enum: Currency, default: Currency.ETB })
  currency: Currency;

  @Column({ type: 'enum', enum: PaymentProvider, default: PaymentProvider.MOCK })
  provider: PaymentProvider;

  @Column({
    type: 'enum',
    enum: TopUpIntentStatus,
    default: TopUpIntentStatus.PENDING,
  })
  status: TopUpIntentStatus;

  /** Provider-side handle used to verify or reconcile the top-up. */
  @Column({ nullable: true })
  providerReference?: string;

  @Column()
  idempotencyKey: string;

  @Column({ type: 'timestamp with time zone', nullable: true })
  completedAt?: Date;

  @Column({ nullable: true })
  failureReason?: string;
}
