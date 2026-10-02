import { Inject, Injectable, Logger } from '@nestjs/common';
import { DataSource, EntityManager } from 'typeorm';
import {
  NotificationOutbox,
  NotificationStatus,
} from './entities/notification-outbox.entity';
import { NOTIFICATION_SENDER, NotificationSender } from './notification-sender';

export interface OutboxMessage {
  userId: string;
  title: string;
  body: string;
  channel?: 'PUSH' | 'SMS';
  data?: Record<string, string>;
}

export interface DispatchSummary {
  sent: number;
  retrying: number;
  failed: number;
}

export const MAX_NOTIFICATION_ATTEMPTS = 5;

@Injectable()
export class NotificationsService {
  private readonly logger = new Logger(NotificationsService.name);

  constructor(
    private readonly dataSource: DataSource,
    @Inject(NOTIFICATION_SENDER) private readonly sender: NotificationSender,
  ) {}

  /** Queue messages inside the caller's transaction. */
  async enqueue(manager: EntityManager, messages: OutboxMessage[]): Promise<void> {
    if (messages.length === 0) return;
    await manager.insert(
      NotificationOutbox,
      messages.map((m) => ({
        userId: m.userId,
        title: m.title,
        body: m.body,
        channel: m.channel ?? 'PUSH',
        data: m.data,
      })),
    );
  }

  /**
   * Delivers due messages at least once. Rows are locked with SKIP LOCKED, so
   * several dispatchers can run side by side without double-sending a batch.
   * Failures back off exponentially and give up after MAX_NOTIFICATION_ATTEMPTS.
   */
  async dispatchPending(limit = 50): Promise<DispatchSummary> {
    return this.dataSource.transaction(async (manager) => {
      const due = await manager
        .getRepository(NotificationOutbox)
        .createQueryBuilder('n')
        .setLock('pessimistic_write')
        .setOnLocked('skip_locked')
        .where('n.status = :status', { status: NotificationStatus.PENDING })
        .andWhere('n.nextAttemptAt <= now()')
        .orderBy('n.createdAt', 'ASC')
        .limit(limit)
        .getMany();

      const summary: DispatchSummary = { sent: 0, retrying: 0, failed: 0 };
      for (const notification of due) {
        try {
          await this.sender.send(notification);
          notification.status = NotificationStatus.SENT;
          notification.sentAt = new Date();
          summary.sent += 1;
        } catch (err) {
          notification.attempts += 1;
          notification.lastError = (err as Error).message?.slice(0, 500);
          if (notification.attempts >= MAX_NOTIFICATION_ATTEMPTS) {
            notification.status = NotificationStatus.FAILED;
            summary.failed += 1;
          } else {
            notification.nextAttemptAt = new Date(
              Date.now() + 2 ** notification.attempts * 60_000,
            );
            summary.retrying += 1;
          }
        }
        await manager.save(notification);
      }
      if (due.length) this.logger.log(`Notification dispatch: ${JSON.stringify(summary)}`);
      return summary;
    });
  }
}
