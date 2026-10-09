/**
 * Settles or expires PENDING top-ups by asking the provider directly.
 * Idempotent; run on a schedule (e.g. every 5 minutes via cron/k8s CronJob).
 *
 *   npm run reconcile:top-ups
 *   node dist/wallets/reconcile-top-ups.js   # from the built image
 */
import { NestFactory } from '@nestjs/core';
import { AppModule } from '../app.module';
import { TopUpService } from './top-up.service';

async function main() {
  const app = await NestFactory.createApplicationContext(AppModule, {
    logger: ['error', 'warn', 'log'],
  });
  try {
    const summary = await app.get(TopUpService).reconcilePending({
      olderThanMinutes: Number(process.env.RECONCILE_OLDER_THAN_MINUTES ?? 10),
      expireAfterMinutes: Number(process.env.RECONCILE_EXPIRE_AFTER_MINUTES ?? 1440),
    });
    console.log(JSON.stringify(summary));
    if (summary.errors > 0) process.exitCode = 1;
  } finally {
    await app.close();
  }
}

main().catch((err) => {
  console.error('[reconcile] FAILED:', err);
  process.exit(1);
});
