import { Column, Entity, Index } from 'typeorm';
import { BaseEntity } from '../../common/entities/base.entity';

export enum NotificationStatus {
  PENDING = 'PENDING',
  SENT = 'SENT',
  FAILED = 'FAILED',
}

/**
 * Transactional outbox: rows are written in the same transaction as the event
 * that caused them and delivered later by `NotificationsService.dispatchPending`.
 */
@Entity('notification_outbox')
@Index('IDX_notification_outbox_due', ['status', 'nextAttemptAt'])
export class NotificationOutbox extends BaseEntity {
  @Column({ type: 'uuid' })
  userId: string;

  @Column({ type: 'varchar', length: 16, default: 'PUSH' })
  channel: string;

  @Column({ type: 'varchar', length: 120 })
  title: string;

  @Column({ type: 'text' })
  body: string;

  @Column({ type: 'jsonb', nullable: true })
  data?: Record<string, string>;

  @Column({ type: 'varchar', length: 16, default: NotificationStatus.PENDING })
  status: NotificationStatus;

  @Column({ type: 'int', default: 0 })
  attempts: number;

  @Column({ type: 'timestamp with time zone', default: () => 'now()' })
  nextAttemptAt: Date;

  @Column({ type: 'timestamp with time zone', nullable: true })
  sentAt?: Date;

  @Column({ type: 'varchar', length: 500, nullable: true })
  lastError?: string;
}
