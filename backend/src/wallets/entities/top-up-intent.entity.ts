import { Entity, Column, ManyToOne, JoinColumn, Index } from 'typeorm';
import { BaseEntity } from '../../common/entities/base.entity';
import { User } from '../../users/entities/user.entity';
import {
  Currency,
  PaymentProvider,
  TopUpIntentStatus,
} from '../../common/enums';

/**
 * A request to move external money into a Semuni wallet.
 *
 * Kept separate from `payments`, which records fare settlement *between two
 * users*. Merging them would make it impossible to answer "did money enter the
 * system or merely move within it?" — the distinction that audit depends on.
 *
 * Lifecycle: PENDING (handed to the provider) -> SUCCESS (provider confirmed and
 * the wallet was credited) | FAILED | EXPIRED. The wallet is only credited on
 * the SUCCESS transition, which happens in TopUpService.
 */
@Entity('top_up_intents')
// Top-up keys are scoped to their owner; one user's key is invisible to others.
@Index('UQ_top_up_intents_user_idempotency', ['userId', 'idempotencyKey'], {
  unique: true,
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

  /** Client-supplied key; makes initiating the same top-up twice safe. */
  @Column()
  idempotencyKey: string;

  @Column({ type: 'timestamp with time zone', nullable: true })
  completedAt?: Date;

  @Column({ nullable: true })
  failureReason?: string;
}
