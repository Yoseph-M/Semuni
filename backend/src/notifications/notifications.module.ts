import { Module } from '@nestjs/common';
import { TypeOrmModule } from '@nestjs/typeorm';
import { NotificationsService } from './notifications.service';
import { NotificationOutbox } from './entities/notification-outbox.entity';
import { LogNotificationSender, NOTIFICATION_SENDER } from './notification-sender';
import { NotificationsController } from './notifications.controller';

@Module({
  imports: [TypeOrmModule.forFeature([NotificationOutbox])],
  providers: [
    NotificationsService,
    { provide: NOTIFICATION_SENDER, useClass: LogNotificationSender },
  ],
  controllers: [NotificationsController],
  exports: [NotificationsService],
})
export class NotificationsModule {}
