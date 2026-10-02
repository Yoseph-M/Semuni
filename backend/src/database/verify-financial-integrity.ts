/**
 * Phase 6/7 financial-integrity probe.
 *
 * Two jobs:
 *
 *   1. `--report` (default) — read-only. Lists rows that would violate the
 *      Phase 6 invariants, so a repair is a decision rather than a surprise.
 *      Nothing is modified.
 *
 *   2. `--probe` — asserts PostgreSQL itself rejects impossible financial rows.
 *      Every probe runs inside a transaction that is rolled back.
 *
 * Run with:
 *   npx ts-node -r tsconfig-paths/register src/database/verify-financial-integrity.ts
 *   npx ts-node -r tsconfig-paths/register src/database/verify-financial-integrity.ts --probe
 */
import 'reflect-metadata';
import dataSource from './data-source';

function report(label: string, code: string | undefined, expected: string): void {
  const ok = code === expected;
  console.log(
    `${ok ? '✅' : '❌'} ${label}: rejected with code ${code}${
      ok ? '' : ` (expected ${expected})`
    }`,
  );
}

/** Runs `sql` in a rolled-back transaction and reports the raised SQLSTATE. */
async function probe(
  label: string,
  expected: string,
  sql: string,
  params: unknown[] = [],
) {
  const runner = dataSource.createQueryRunner();
  await runner.connect();
  await runner.startTransaction();
  try {
    await runner.query(sql, params);
    console.log(`❌ ${label}: statement succeeded but should have failed`);
  } catch (err) {
    report(label, (err as { code?: string }).code, expected);
  } finally {
    await runner.rollbackTransaction();
    await runner.release();
  }
}

interface Finding {
  label: string;
  sql: string;
  hint: string;
}

const FINDINGS: Finding[] = [
  {
    label: 'payments sharing a receipt number',
    hint: 'the old countToday()+1 scheme; each receipt must be unique',
    sql: `SELECT "receiptNumber", count(*) AS n, array_agg("id") AS ids
          FROM payments WHERE "receiptNumber" IS NOT NULL
          GROUP BY "receiptNumber" HAVING count(*) > 1`,
  },
  {
    label: 'trips with more than one SUCCESS payment',
    hint: 'a trip may settle once',
    sql: `SELECT "tripId", count(*) AS n, array_agg("id") AS ids
          FROM payments WHERE status = 'SUCCESS'
          GROUP BY "tripId" HAVING count(*) > 1`,
  },
  {
    label: 'payments sharing a provider reference',
    hint: 'an external reference is consumed once',
    sql: `SELECT "providerReference", count(*) AS n, array_agg("id") AS ids
          FROM payments WHERE "providerReference" IS NOT NULL
          GROUP BY "providerReference" HAVING count(*) > 1`,
  },
  {
    label: 'wallets with a negative balance',
    hint: 'a balance is never allowed below zero',
    sql: `SELECT id, "userId", balance FROM wallets WHERE balance < 0`,
  },
  {
    label: 'ledger rows with a non-positive amount',
    hint: 'every movement is positive; direction carries the sign',
    sql: `SELECT id, "walletId", amount, "entryType" FROM ledger_entries WHERE amount <= 0`,
  },
  {
    label: 'ledger rows whose balance arithmetic does not hold',
    hint: 'balanceAfter must equal balanceBefore ± amount',
    sql: `SELECT id, "walletId", direction, amount, "balanceBefore", "balanceAfter"
          FROM ledger_entries
          WHERE ("direction" = 'CREDIT' AND "balanceAfter" <> "balanceBefore" + amount)
             OR ("direction" = 'DEBIT'  AND "balanceAfter" <> "balanceBefore" - amount)`,
  },
  {
    label: 'ledger rows with a negative balance snapshot',
    hint: 'a reachable balance is never negative',
    sql: `SELECT id, "walletId", "balanceBefore", "balanceAfter"
          FROM ledger_entries WHERE "balanceBefore" < 0 OR "balanceAfter" < 0`,
  },
  {
    label: 'duplicate ledger rows for one (transaction, wallet, entry type)',
    hint: 'one transaction writes at most one entry per wallet and type',
    sql: `SELECT "transactionId", "walletId", "entryType", count(*) AS n
          FROM ledger_entries WHERE "transactionId" IS NOT NULL
          GROUP BY "transactionId", "walletId", "entryType" HAVING count(*) > 1`,
  },
  {
    label: 'duplicate ledger rows for one (wallet, reference, entry type)',
    hint: 'a replayed reference must not move money twice',
    sql: `SELECT "walletId", "referenceType", "referenceId", "entryType", count(*) AS n
          FROM ledger_entries WHERE "referenceId" IS NOT NULL
          GROUP BY "walletId", "referenceType", "referenceId", "entryType" HAVING count(*) > 1`,
  },
  {
    label: 'top-up intents sharing a provider reference',
    hint: 'provider references are replay-safe',
    sql: `WITH tops AS (
            SELECT * FROM top_up_intents WHERE "providerReference" IS NOT NULL
          )
          SELECT "providerReference", count(*) AS n FROM tops
          GROUP BY "providerReference" HAVING count(*) > 1`,
  },
  {
    label: 'withdrawals with a non-positive amount',
    hint: 'withdrawal amounts are positive integer minor units',
    sql: `SELECT id, "userId", amount FROM withdrawals WHERE amount <= 0`,
  },
  {
    label: 'top-up intents with a non-positive amount',
    hint: 'top-up amounts are positive integer minor units',
    sql: `SELECT id, "userId", "amountMinor" FROM top_up_intents WHERE "amountMinor" <= 0`,
  },
];

async function runReport(): Promise<void> {
  let total = 0;
  for (const finding of FINDINGS) {
    const rows = await dataSource.query(finding.sql);
    if (!rows.length) {
      console.log(`✅ clean — ${finding.label}`);
      continue;
    }
    total += rows.length;
    console.log(
      `⚠️  ${rows.length} finding(s) — ${finding.label} (${finding.hint})`,
    );
    for (const row of rows.slice(0, 10)) {
      console.log(`     ${JSON.stringify(row)}`);
    }
    if (rows.length > 10) console.log(`     … and ${rows.length - 10} more`);
  }
  console.log(
    total === 0
      ? '\nNo invariant violations found.'
      : `\n${total} violation group(s) require a decision — no data was changed.`,
  );
}

async function main(): Promise<void> {
  await dataSource.initialize();
  try {
    if (process.argv.includes('--probe')) {
      const [wallet] = await dataSource.query(
        `SELECT id, balance FROM wallets ORDER BY "createdAt" LIMIT 1`,
      );
      const [tripPayment] = await dataSource.query(
        `SELECT id, "tripId" FROM payments WHERE "tripId" IS NOT NULL LIMIT 1`,
      );

      // 1. One successful payment per trip, enforced by the partial index.
      if (tripPayment) {
        await probe(
          'one SUCCESS payment per trip',
          '23505',
          `INSERT INTO payments ("tripId", "passengerId", "driverId", amount, status, "idempotencyKey")
           VALUES ($1, 'probe', 'probe', 1, 'SUCCESS', 'probe-' || gen_random_uuid())`,
          [tripPayment.tripId],
        );
      }

      // 2. Duplicate ledger entry for the same transaction/wallet/type.
      await probe(
        'duplicate ledger movement',
        '23505',
        `INSERT INTO ledger_entries ("walletId", "transactionId", "entryType", direction, amount, "balanceBefore", "balanceAfter")
         SELECT "walletId", "transactionId", "entryType", 'CREDIT', 1, 0, 1
         FROM ledger_entries WHERE "transactionId" IS NOT NULL LIMIT 1`,
      );

      // 3. Ledger arithmetic that does not hold.
      if (wallet) {
        await probe(
          'ledger arithmetic',
          '23514',
          `INSERT INTO ledger_entries ("walletId", "entryType", direction, amount, "balanceBefore", "balanceAfter")
           VALUES ($1, 'ADJUSTMENT', 'DEBIT', 100, 0, 0)`,
          [wallet.id],
        );

        // 4. A negative wallet balance.
        await probe(
          'non-negative wallet balance',
          '23514',
          `UPDATE wallets SET balance = -1 WHERE id = $1`,
          [wallet.id],
        );

        // 5. A zero/negative ledger amount.
        await probe(
          'positive ledger amount',
          '23514',
          `INSERT INTO ledger_entries ("walletId", "entryType", direction, amount, "balanceBefore", "balanceAfter")
           VALUES ($1, 'ADJUSTMENT', 'CREDIT', 0, 0, 0)`,
          [wallet.id],
        );
      }

      // 6. A non-positive payment amount.
      await probe(
        'positive payment amount',
        '23514',
        `INSERT INTO payments ("tripId", "passengerId", "driverId", amount, "idempotencyKey")
         VALUES ('probe', 'probe', 'probe', 0, 'probe-' || gen_random_uuid())`,
      );
    } else {
      await runReport();
    }
  } finally {
    await dataSource.destroy();
  }
}

main().catch((err) => {
  console.error('[verify] FAILED:', err);
  process.exit(1);
});
