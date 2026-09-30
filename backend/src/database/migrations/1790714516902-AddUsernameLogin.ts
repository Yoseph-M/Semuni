import { MigrationInterface, QueryRunner } from 'typeorm';

/**
 * Moves the login identifier from `phone` to `username`.
 *
 * - `users.username` becomes the unique credential used by /auth/login.
 * - `phone` is demoted from "the login handle" to an optional contact detail,
 *   so it is relaxed to NULL on users, passengers and drivers.
 *
 * Existing rows are backfilled from `phone` (already unique), falling back to
 * the primary key so the NOT NULL + UNIQUE constraints can be applied safely.
 */
export class AddUsernameLogin1790714516902 implements MigrationInterface {
  name = 'AddUsernameLogin1790714516902';

  public async up(queryRunner: QueryRunner): Promise<void> {
    // 1. Add the new credential column as nullable so existing rows survive.
    await queryRunner.query(
      `ALTER TABLE "users" ADD "username" character varying`,
    );

    // 2. Backfill: phone was unique, so it is a safe seed for username.
    await queryRunner.query(
      `UPDATE "users" SET "username" = "phone" WHERE "username" IS NULL AND "phone" IS NOT NULL`,
    );
    // Any row without a phone falls back to its id, which is also unique.
    await queryRunner.query(
      `UPDATE "users" SET "username" = "id"::text WHERE "username" IS NULL`,
    );

    // 3. Promote to the real credential: NOT NULL + UNIQUE.
    await queryRunner.query(
      `ALTER TABLE "users" ALTER COLUMN "username" SET NOT NULL`,
    );
    await queryRunner.query(
      `ALTER TABLE "users" ADD CONSTRAINT "UQ_users_username" UNIQUE ("username")`,
    );

    // 4. Phone becomes an optional contact field.
    await queryRunner.query(
      `ALTER TABLE "users" ALTER COLUMN "phone" DROP NOT NULL`,
    );
    await queryRunner.query(
      `ALTER TABLE "passengers" ALTER COLUMN "phone" DROP NOT NULL`,
    );
    await queryRunner.query(
      `ALTER TABLE "drivers" ALTER COLUMN "phone" DROP NOT NULL`,
    );
  }

  public async down(queryRunner: QueryRunner): Promise<void> {
    await queryRunner.query(
      `ALTER TABLE "drivers" ALTER COLUMN "phone" SET NOT NULL`,
    );
    await queryRunner.query(
      `ALTER TABLE "passengers" ALTER COLUMN "phone" SET NOT NULL`,
    );
    await queryRunner.query(
      `ALTER TABLE "users" ALTER COLUMN "phone" SET NOT NULL`,
    );

    await queryRunner.query(
      `ALTER TABLE "users" DROP CONSTRAINT "UQ_users_username"`,
    );
    await queryRunner.query(`ALTER TABLE "users" DROP COLUMN "username"`);
  }
}
