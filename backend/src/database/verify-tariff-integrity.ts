/**
 * Phase 5 database-integrity probe.
 *
 * Verifies the three protections the migration adds to PostgreSQL itself. Every
 * check runs inside a transaction that is rolled back, so no data is changed.
 *
 * Run with:  npx ts-node -r tsconfig-paths/register src/database/verify-tariff-integrity.ts
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
async function probe(label: string, expected: string, sql: string, params: unknown[] = []) {
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

async function main(): Promise<void> {
  await dataSource.initialize();
  try {
    const [tariff] = await dataSource.query(
      `SELECT id, version FROM tariffs ORDER BY "createdAt" LIMIT 1`,
    );
    if (!tariff) {
      console.log('⚠️  no tariffs in the database; nothing to probe');
      return;
    }

    // 1. A tariff that has priced a trip cannot have its rule prices edited in
    //    place. The trip and the attempted update share one transaction so the
    //    trigger sees the tariff as used.
    const runner = dataSource.createQueryRunner();
    await runner.connect();
    await runner.startTransaction();
    try {
      await runner.query(
        `INSERT INTO trips ("passengerId", "driverId", origin, destination, "fareAmount", "tariffId")
         VALUES ('integrity-probe', 'integrity-probe', 'a', 'b', 100, $1)`,
        [tariff.id],
      );
      try {
        await runner.query(
          `UPDATE tariff_rules SET "basePrice" = "basePrice" + 1 WHERE "tariffId" = $1`,
          [tariff.id],
        );
        console.log('❌ used-tariff rule immutability: update succeeded');
      } catch (err) {
        report(
          'used-tariff rule immutability',
          (err as { code?: string }).code,
          '55006',
        );
      }
    } finally {
      await runner.rollbackTransaction();
      await runner.release();
    }

    // 2. At most one tariff may be ACTIVE, regardless of application checks.
    await probe(
      'single ACTIVE tariff',
      '23505',
      `INSERT INTO tariffs (version, name, status, "validFrom")
       VALUES ('TARIFF-PROBE-ACTIVE', 'probe', 'ACTIVE', now())`,
    );

    // 3. Version identifiers are unique.
    await probe(
      'unique tariff version',
      '23505',
      `INSERT INTO tariffs (version, name, status, "validFrom")
       VALUES ($1, 'probe', 'DRAFT', now())`,
      [tariff.version],
    );
  } finally {
    await dataSource.destroy();
  }
}

main().catch((err) => {
  console.error('[verify] FAILED:', err);
  process.exit(1);
});
