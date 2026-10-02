import { MigrationInterface, QueryRunner } from 'typeorm';

/**
 * Phase 5 — tariff versioning and lifecycle.
 *
 * Adds an explicit, unique, never-reused `version` identifier and a
 * DRAFT/ACTIVE/EXPIRED lifecycle to `tariffs`, then protects the invariants in
 * PostgreSQL itself:
 *
 *   - `UQ_tariffs_version`          every version label is unique
 *   - `UQ_tariffs_single_active`    at most one ACTIVE tariff may exist
 *   - `TRG_tariff_rules_immutable`  a tariff that has priced a trip can no
 *                                   longer have its rule prices edited
 *
 * The application validates the same rules first so that callers receive a
 * structured ErrorCode; the database constraints are the integrity boundary.
 */
export class TariffVersioningAndLifecycle1790740000000
  implements MigrationInterface
{
  name = 'TariffVersioningAndLifecycle1790740000000';

  public async up(queryRunner: QueryRunner): Promise<void> {
    await queryRunner.query(
      `DO $$ BEGIN CREATE TYPE "public"."tariffs_status_enum" AS ENUM('DRAFT', 'ACTIVE', 'EXPIRED'); EXCEPTION WHEN duplicate_object THEN null; END $$`,
    );

    await queryRunner.query(
      `ALTER TABLE "tariffs" ADD COLUMN "version" character varying`,
    );
    await queryRunner.query(
      `ALTER TABLE "tariffs" ADD COLUMN "status" "public"."tariffs_status_enum" NOT NULL DEFAULT 'DRAFT'`,
    );

    // Rows created before versioning still need a unique label. Deriving it from
    // the primary key keeps the backfill deterministic and collision-free.
    await queryRunner.query(`
      UPDATE "tariffs"
      SET "version" = 'TARIFF-LEGACY-' || UPPER(SUBSTRING(REPLACE("id"::text, '-', '') FROM 1 FOR 12))
      WHERE "version" IS NULL
    `);
    await queryRunner.query(
      `ALTER TABLE "tariffs" ALTER COLUMN "version" SET NOT NULL`,
    );
    await queryRunner.query(
      `CREATE UNIQUE INDEX "UQ_tariffs_version" ON "tariffs" ("version")`,
    );

    // Before this migration every tariff was implicitly usable. Preserve that
    // for the single most recent in-window tariff and retire the rest, so the
    // single-ACTIVE constraint below can be created on existing data.
    await queryRunner.query(`UPDATE "tariffs" SET "status" = 'EXPIRED'`);
    await queryRunner.query(`
      UPDATE "tariffs" SET "status" = 'ACTIVE'
      WHERE "id" = (
        SELECT "id" FROM "tariffs"
        WHERE "validFrom" <= now() AND ("validTo" IS NULL OR "validTo" >= now())
        ORDER BY "validFrom" DESC
        LIMIT 1
      )
    `);

    await queryRunner.query(
      `CREATE UNIQUE INDEX "UQ_tariffs_single_active" ON "tariffs" ("status") WHERE "status" = 'ACTIVE'`,
    );

    // Immutability of a tariff that has already priced trips. Only pricing
    // columns are guarded: lifecycle status changes and cascade deletes remain
    // legal, because the trip fare snapshot — not the tariff row — is what
    // makes history reconstructable.
    await queryRunner.query(`
      CREATE OR REPLACE FUNCTION "semuni_protect_used_tariff_rules"()
      RETURNS trigger
      LANGUAGE plpgsql
      AS $$
      DECLARE
        already_used boolean;
      BEGIN
        IF OLD."basePrice" IS NOT DISTINCT FROM NEW."basePrice"
           AND OLD."startStopSequence" IS NOT DISTINCT FROM NEW."startStopSequence"
           AND OLD."endStopSequence" IS NOT DISTINCT FROM NEW."endStopSequence"
           AND OLD."vehicleType" IS NOT DISTINCT FROM NEW."vehicleType"
           AND OLD."routeId" IS NOT DISTINCT FROM NEW."routeId" THEN
          RETURN NEW;
        END IF;

        SELECT EXISTS (
          SELECT 1 FROM "trips" WHERE "tariffId" = OLD."tariffId"::text
        ) INTO already_used;

        IF already_used THEN
          RAISE EXCEPTION 'Tariff % has already priced trips and is immutable; publish a new version instead', OLD."tariffId"
            USING ERRCODE = '55006';
        END IF;

        RETURN NEW;
      END;
      $$
    `);
    await queryRunner.query(
      `CREATE TRIGGER "TRG_tariff_rules_immutable" BEFORE UPDATE ON "tariff_rules" FOR EACH ROW EXECUTE FUNCTION "semuni_protect_used_tariff_rules"()`,
    );
  }

  public async down(queryRunner: QueryRunner): Promise<void> {
    await queryRunner.query(
      `DROP TRIGGER IF EXISTS "TRG_tariff_rules_immutable" ON "tariff_rules"`,
    );
    await queryRunner.query(
      `DROP FUNCTION IF EXISTS "semuni_protect_used_tariff_rules"()`,
    );
    await queryRunner.query(`DROP INDEX "public"."UQ_tariffs_single_active"`);
    await queryRunner.query(`DROP INDEX "public"."UQ_tariffs_version"`);
    await queryRunner.query(`ALTER TABLE "tariffs" DROP COLUMN "status"`);
    await queryRunner.query(`ALTER TABLE "tariffs" DROP COLUMN "version"`);
    await queryRunner.query(`DROP TYPE "public"."tariffs_status_enum"`);
  }
}
