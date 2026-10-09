import { MigrationInterface, QueryRunner } from 'typeorm';

/**
 * Adds `top_up_intents.receiptReference`.
 *
 * The `TopUpIntent` entity has always declared this column (and a unique
 * constraint on it) as the external-verification identifier written when a
 * links.et receipt is settled. No migration ever created it, so every read of
 * a top-up intent — including initiating one — failed on a database built from
 * migrations alone (`column TopUpIntent.receiptReference does not exist`).
 *
 * The unique constraint is what makes a replayed receipt unable to settle the
 * same top-up twice: one external receipt may back at most one intent. It is
 * created conditionally so this migration is safe on a database where an
 * equivalent constraint already exists under another name.
 */
export class AddTopUpReceiptReference1790810000000
  implements MigrationInterface
{
  name = 'AddTopUpReceiptReference1790810000000';

  public async up(queryRunner: QueryRunner): Promise<void> {
    await queryRunner.query(
      `ALTER TABLE "top_up_intents" ADD COLUMN IF NOT EXISTS "receiptReference" character varying`,
    );

    await queryRunner.query(`
      DO $$
      BEGIN
        IF NOT EXISTS (
          SELECT 1
          FROM pg_constraint c
          JOIN pg_class t ON t.oid = c.conrelid
          JOIN pg_attribute a ON a.attrelid = t.oid AND a.attnum = ANY (c.conkey)
          WHERE t.relname = 'top_up_intents'
            AND c.contype = 'u'
            AND a.attname = 'receiptReference'
            AND array_length(c.conkey, 1) = 1
        ) THEN
          ALTER TABLE "top_up_intents"
            ADD CONSTRAINT "UQ_top_up_intents_receiptReference"
            UNIQUE ("receiptReference");
        END IF;
      END
      $$;
    `);
  }

  public async down(queryRunner: QueryRunner): Promise<void> {
    await queryRunner.query(
      `ALTER TABLE "top_up_intents" DROP CONSTRAINT IF EXISTS "UQ_top_up_intents_receiptReference"`,
    );
    await queryRunner.query(
      `ALTER TABLE "top_up_intents" DROP COLUMN IF EXISTS "receiptReference"`,
    );
  }
}
