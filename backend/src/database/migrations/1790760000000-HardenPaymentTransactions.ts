import { MigrationInterface, QueryRunner } from 'typeorm';

/**
 * Phase 7 — payment-transaction hardening support.
 *
 *  1. Receipt numbers come from a PostgreSQL sequence. The previous
 *     `countToday() + 1` scheme was read-then-write: two concurrent payments
 *     could read the same count and mint the same receipt number. A sequence is
 *     allocated inside the database, so uniqueness no longer depends on timing,
 *     and `UQ_payments_receipt_number` (Phase 6) enforces it even if that
 *     changes.
 *
 *  2. `failureReason` makes a failed attempt self-describing. Failed payments
 *     are durable records, not rolled-back rows, so an operator can answer
 *     "why did this attempt fail?" from the row itself.
 */
export class HardenPaymentTransactions1790760000000
  implements MigrationInterface
{
  name = 'HardenPaymentTransactions1790760000000';

  public async up(queryRunner: QueryRunner): Promise<void> {
    // Sequences are non-transactional: a rolled-back payment may leave a gap in
    // the numbering. Gaps are acceptable for a receipt number (uniqueness and
    // monotonicity are what matter); reusing one is not.
    await queryRunner.query(
      `CREATE SEQUENCE IF NOT EXISTS "receipt_number_seq" START WITH 1 INCREMENT BY 1 MINVALUE 1`,
    );

    // Continue above the highest receipt already issued, so the sequence can
    // never mint a number that a historical payment is already using. If no
    // receipt exists yet the sequence starts at 1 untouched.
    await queryRunner.query(`
      DO $$
      DECLARE max_seq integer;
      BEGIN
        SELECT COALESCE(
                 MAX((regexp_replace("receiptNumber", '^SEM-[0-9]{4}-', ''))::int), 0
               )
          INTO max_seq
          FROM payments
         WHERE "receiptNumber" ~ '^SEM-[0-9]{4}-[0-9]+$';
        IF max_seq > 0 THEN
          PERFORM setval('receipt_number_seq', max_seq);
        END IF;
      END $$;
    `);

    await queryRunner.query(
      `ALTER TABLE "payments" ADD COLUMN "failureReason" character varying`,
    );
  }

  public async down(queryRunner: QueryRunner): Promise<void> {
    await queryRunner.query(
      `ALTER TABLE "payments" DROP COLUMN "failureReason"`,
    );
    await queryRunner.query(`DROP SEQUENCE IF EXISTS "receipt_number_seq"`);
  }
}
