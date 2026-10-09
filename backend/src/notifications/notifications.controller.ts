import { Controller, Get, Param, Patch, Post, UseGuards } from '@nestjs/common';
import { InjectRepository } from '@nestjs/typeorm';
import { Repository } from 'typeorm';
import { CurrentUser } from '../auth/decorators/current-user.decorator';
import { JwtAuthGuard } from '../auth/guards/jwt-auth.guard';
import { User } from '../users/entities/user.entity';
import { NotificationOutbox } from './entities/notification-outbox.entity';

/** Authenticated notification inbox backed by the transactional outbox table. */
@Controller('notifications')
@UseGuards(JwtAuthGuard)
export class NotificationsController {
  constructor(
    @InjectRepository(NotificationOutbox)
    private readonly notifications: Repository<NotificationOutbox>,
  ) {}

  @Get()
  async list(@CurrentUser() user: User) {
    const rows = await this.notifications.find({
      where: { userId: user.id },
      order: { createdAt: 'DESC' },
      take: 100,
    });
    return { data: rows, meta: {} };
  }

  @Patch(':id/read')
  async markRead(@CurrentUser() user: User, @Param('id') id: string) {
    const row = await this.notifications.findOne({ where: { id, userId: user.id } });
    if (row) {
      row.data = { ...(row.data ?? {}), read: 'true' };
      await this.notifications.save(row);
    }
    return { data: row, meta: {} };
  }

  @Post('read-all')
  async markAllRead(@CurrentUser() user: User) {
    const rows = await this.notifications.find({ where: { userId: user.id } });
    for (const row of rows) row.data = { ...(row.data ?? {}), read: 'true' };
    if (rows.length) await this.notifications.save(rows);
    return { data: null, meta: {} };
  }
}
