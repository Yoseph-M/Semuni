import { MigrationInterface, QueryRunner } from 'typeorm';

/**
 * Referential integrity for the financial tables, and an append-only ledger.
 *
 * 1. Identifier columns that referenced uuid primary keys as varchar become
 *    uuid (a foreign key needs matching types). The migration stops with a
 *    clear message if a value is not a uuid or points at a missing row, rather
 *    than silently rewriting data.
 * 2. Foreign keys (NO ACTION, so financial history cannot be deleted from
 *    under a payment or ledger row) plus indexes on every FK column.
 *    `trips.paymentId` stays without FK: payments already reference their trip
 *    (`payments.tripId`), and a second edge would make the pair circular.
 *    `ledger_entries.transactionId/referenceId` are polymorphic and stay text.
 * 3. Triggers reject UPDATE, DELETE and TRUNCATE on `ledger_entries`;
 *    corrections are new compensating entries.
 */

const UUID_COLUMNS: Array<[table: string, column: string]> = [
  ['ledger_entries', 'walletId'],
  ['payments', 'tripId'],
  ['payments', 'passengerId'],
  ['payments', 'driverId'],
  ['payments', 'routeId'],
  ['trips', 'passengerId'],
  ['trips', 'driverId'],
  ['trips', 'vehicleId'],
  ['trips', 'routeId'],
  ['trips', 'tariffId'],
  ['trips', 'tariffRuleId'],
  ['trips', 'paymentId'],
  ['settlements', 'driverId'],
  ['settlements', 'withdrawalId'],
  ['withdrawals', 'userId'],
  ['vehicles', 'driverId'],
  ['passengers', 'walletId'],
  ['drivers', 'walletId'],
];

interface ForeignKey {
  table: string;
  column: string;
  references: string;
  onDelete?: 'SET NULL';
}

const FOREIGN_KEYS: ForeignKey[] = [
  { table: 'ledger_entries', column: 'walletId', references: 'wallets' },
  { table: 'payments', column: 'tripId', references: 'trips' },
  { table: 'payments', column: 'passengerId', references: 'users' },
  { table: 'payments', column: 'driverId', references: 'users' },
  { table: 'payments', column: 'routeId', references: 'routes' },
  { table: 'trips', column: 'passengerId', references: 'users' },
  { table: 'trips', column: 'driverId', references: 'users' },
  { table: 'trips', column: 'vehicleId', references: 'vehicles' },
  { table: 'trips', column: 'routeId', references: 'routes' },
  { table: 'trips', column: 'tariffId', references: 'tariffs' },
  { table: 'trips', column: 'tariffRuleId', references: 'tariff_rules' },
  { table: 'trips', column: 'originStopId', references: 'route_stops' },
  { table: 'trips', column: 'destinationStopId', references: 'route_stops' },
  { table: 'settlements', column: 'driverId', references: 'users' },
  { table: 'settlements', column: 'withdrawalId', references: 'withdrawals' },
  { table: 'withdrawals', column: 'userId', references: 'users' },
  { table: 'vehicles', column: 'driverId', references: 'users' },
  // Denormalised convenience pointers; the owning edge is wallets.userId.
  { table: 'passengers', column: 'walletId', references: 'wallets', onDelete: 'SET NULL' },
  { table: 'drivers', column: 'walletId', references: 'wallets', onDelete: 'SET NULL' },
];

/** FK columns that had no index yet. */
const NEW_INDEXES: Array<[table: string, column: string]> = [
  ['payments', 'routeId'],
  ['trips', 'vehicleId'],
  ['trips', 'routeId'],
  ['trips', 'tariffId'],
  ['trips', 'tariffRuleId'],
  ['vehicles', 'driverId'],
  ['passengers', 'walletId'],
  ['drivers', 'walletId'],
];

const UUID_PATTERN =
  '^[0-9a-fA-F]{8}-[0-9a-fA-F]{4}-[0-9a-fA-F]{4}-[0-9a-fA-F]{4}-[0-9a-fA-F]{12}$';

export class ForeignKeysAndAppendOnlyLedger1790780000000
  implements MigrationInterface
{
  name = 'ForeignKeysAndAppendOnlyLedger1790780000000';

  public async up(queryRunner: QueryRunner): Promise<void> {
    for (const [table, column] of UUID_COLUMNS) {
      const [{ n }] = await queryRunner.query(
        `SELECT count(*)::int AS n FROM "${table}" WHERE "${column}" IS NOT NULL AND "${column}" !~ $1`,
        [UUID_PATTERN],
      );
      if (n > 0) {
        throw new Error(
          `${table}.${column} has ${n} non-uuid value(s); fix them before migrating`,
        );
      }
      await queryRunner.query(
        `ALTER TABLE "${table}" ALTER COLUMN "${column}" TYPE uuid USING "${column}"::uuid`,
      );
    }

    for (const fk of FOREIGN_KEYS) {
      const [{ n }] = await queryRunner.query(
        `SELECT count(*)::int AS n FROM "${fk.table}" t
          WHERE t."${fk.column}" IS NOT NULL
            AND NOT EXISTS (SELECT 1 FROM "${fk.references}" r WHERE r.id = t."${fk.column}")`,
      );
      if (n > 0) {
        throw new Error(
          `${fk.table}.${fk.column} has ${n} orphan row(s) with no matching ${fk.references}.id; resolve them before migrating`,
        );
      }
      await queryRunner.query(
        `ALTER TABLE "${fk.table}" ADD CONSTRAINT "FK_${fk.table}_${fk.column}"
           FOREIGN KEY ("${fk.column}") REFERENCES "${fk.references}"("id")
           ON DELETE ${fk.onDelete ?? 'NO ACTION'} ON UPDATE NO ACTION`,
      );
    }

    for (const [table, column] of NEW_INDEXES) {
      await queryRunner.query(
        `CREATE INDEX "IDX_${table}_${column}" ON "${table}" ("${column}")`,
      );
    }

    await queryRunner.query(`
      CREATE FUNCTION ledger_entries_append_only() RETURNS trigger
      LANGUAGE plpgsql AS $$
      BEGIN
        RAISE EXCEPTION 'ledger_entries is append-only: % is not allowed', TG_OP
          USING ERRCODE = 'restrict_violation',
                HINT = 'Record a compensating ledger entry instead.';
      END
      $$`);
    await queryRunner.query(
      `CREATE TRIGGER "TRG_ledger_entries_append_only"
         BEFORE UPDATE OR DELETE ON "ledger_entries"
         FOR EACH ROW EXECUTE FUNCTION ledger_entries_append_only()`,
    );
    await queryRunner.query(
      `CREATE TRIGGER "TRG_ledger_entries_no_truncate"
         BEFORE TRUNCATE ON "ledger_entries"
         FOR EACH STATEMENT EXECUTE FUNCTION ledger_entries_append_only()`,
    );
  }

  public async down(queryRunner: QueryRunner): Promise<void> {
    await queryRunner.query(
      `DROP TRIGGER "TRG_ledger_entries_no_truncate" ON "ledger_entries"`,
    );
    await queryRunner.query(
      `DROP TRIGGER "TRG_ledger_entries_append_only" ON "ledger_entries"`,
    );
    await queryRunner.query(`DROP FUNCTION ledger_entries_append_only()`);

    for (const [table, column] of NEW_INDEXES) {
      await queryRunner.query(`DROP INDEX "public"."IDX_${table}_${column}"`);
    }
    for (const fk of [...FOREIGN_KEYS].reverse()) {
      await queryRunner.query(
        `ALTER TABLE "${fk.table}" DROP CONSTRAINT "FK_${fk.table}_${fk.column}"`,
      );
    }
    for (const [table, column] of [...UUID_COLUMNS].reverse()) {
      await queryRunner.query(
        `ALTER TABLE "${table}" ALTER COLUMN "${column}" TYPE character varying USING "${column}"::text`,
      );
    }
  }
}
