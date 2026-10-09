import { MigrationInterface, QueryRunner } from 'typeorm';

/**
 * Per-account login lockout: consecutive failed password attempts are counted
 * on the user row, and the account is locked for a period once the threshold
 * is reached (see AuthService.login).
 */
export class AddLoginLockout1790770000000 implements MigrationInterface {
  name = 'AddLoginLockout1790770000000';

  public async up(queryRunner: QueryRunner): Promise<void> {
    await queryRunner.query(
      `ALTER TABLE "users" ADD "failedLoginAttempts" integer NOT NULL DEFAULT 0`,
    );
    await queryRunner.query(
      `ALTER TABLE "users" ADD "lockedUntil" TIMESTAMP WITH TIME ZONE`,
    );
    await queryRunner.query(
      `ALTER TABLE "users" ADD CONSTRAINT "CHK_users_failed_login_attempts_nonnegative" CHECK ("failedLoginAttempts" >= 0)`,
    );
  }

  public async down(queryRunner: QueryRunner): Promise<void> {
    await queryRunner.query(
      `ALTER TABLE "users" DROP CONSTRAINT "CHK_users_failed_login_attempts_nonnegative"`,
    );
    await queryRunner.query(`ALTER TABLE "users" DROP COLUMN "lockedUntil"`);
    await queryRunner.query(
      `ALTER TABLE "users" DROP COLUMN "failedLoginAttempts"`,
    );
  }
}
