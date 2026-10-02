import { Entity, Column, ManyToOne, JoinColumn, Index, Unique, Check } from 'typeorm';
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
// An external reference identifies one external money movement, so it may back
// at most one top-up intent. This is what makes a replayed provider callback
// unable to settle (and credit) the same payment twice. (Constraint name matches
// the one created with the table, so entity and database stay aligned.)
@Unique('UQ_top_up_intents_providerReference', ['providerReference'])
@Check('CHK_top_up_amount_positive', '"amountMinor" > 0')
export class TopUpIntent extends BaseEntity {
  @ManyToOne(() => User)
  @JoinColumn({ name: 'userId', foreignKeyConstraintName: 'FK_top_up_intents_userId' })
  user: User;

  @Column({ type: 'uuid' })
  @Index('IDX_top_up_intents_userId')
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

  /** Where the user approves the payment (Telebirr web checkout). */
  @Column({ type: 'text', nullable: true })
  checkoutUrl?: string;

  /** Client-supplied key; makes initiating the same top-up twice safe. */
  @Column()
  idempotencyKey: string;

  @Column({ type: 'timestamp with time zone', nullable: true })
  completedAt?: Date;

  @Column({ nullable: true })
  failureReason?: string;
}
