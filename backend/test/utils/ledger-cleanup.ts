import { DataSource } from 'typeorm';

/**
 * `ledger_entries` is append-only (a trigger rejects DELETE), so test cleanup
 * runs with triggers disabled for this one session. `session_replication_role`
 * needs a superuser, which the local/CI database user is; the application role
 * in production should not be.
 */
export async function deleteLedgerEntries(
  dataSource: DataSource,
  sql: string,
  params: unknown[] = [],
): Promise<void> {
  const runner = dataSource.createQueryRunner();
  await runner.connect();
  try {
    await runner.query(`SET session_replication_role = replica`);
    await runner.query(sql, params);
  } finally {
    await runner.query(`SET session_replication_role = DEFAULT`);
    await runner.release();
  }
}
