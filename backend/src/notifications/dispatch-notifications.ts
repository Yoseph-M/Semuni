/**
 * Delivers queued notifications. Idempotent; run on a schedule (e.g. every minute).
 *
 *   npm run notifications:dispatch
 *   node dist/notifications/dispatch-notifications.js   # from the built image
 */
import { NestFactory } from '@nestjs/core';
import { AppModule } from '../app.module';
import { NotificationsService } from './notifications.service';

async function main() {
  const app = await NestFactory.createApplicationContext(AppModule, {
    logger: ['error', 'warn', 'log'],
  });
  try {
    const service = app.get(NotificationsService);
    const total = { sent: 0, retrying: 0, failed: 0 };
    for (;;) {
      const batch = await service.dispatchPending(100);
      total.sent += batch.sent;
      total.retrying += batch.retrying;
      total.failed += batch.failed;
      if (batch.sent + batch.retrying + batch.failed < 100) break;
    }
    console.log(JSON.stringify(total));
  } finally {
    await app.close();
  }
}

main().catch((err) => {
  console.error('[notifications] FAILED:', err);
  process.exit(1);
});
