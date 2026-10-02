import { Injectable, Logger } from '@nestjs/common';
import { NotificationOutbox } from './entities/notification-outbox.entity';

export const NOTIFICATION_SENDER = Symbol('NOTIFICATION_SENDER');

/** Delivery channel (FCM, SMS gateway, ...). Throwing schedules a retry. */
export interface NotificationSender {
  send(notification: NotificationOutbox): Promise<void>;
}

/** Default sender until a push/SMS provider is chosen: logs ids only, never the body. */
@Injectable()
export class LogNotificationSender implements NotificationSender {
  private readonly logger = new Logger('Notifications');

  send(notification: NotificationOutbox): Promise<void> {
    this.logger.log(
      `Delivered ${notification.channel} ${notification.id} to user ${notification.userId}`,
    );
    return Promise.resolve();
  }
}
