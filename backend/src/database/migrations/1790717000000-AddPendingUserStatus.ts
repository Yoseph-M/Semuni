import { MigrationInterface, QueryRunner } from 'typeorm';

/**
 * Adds `PENDING` to `users_status_enum`.
 *
 * The Phase 2 identity model defines four account statuses
 * (PENDING, ACTIVE, SUSPENDED, INACTIVE) but the original schema only created
 * the last three, so a user could not be persisted in a "created, not yet
 * activated" state. `PENDING` is an additive enum value.
 */
export class AddPendingUserStatus1790717000000 implements MigrationInterface {
  name = 'AddPendingUserStatus1790717000000';

  public async up(queryRunner: QueryRunner): Promise<void> {
    await queryRunner.query(
      `ALTER TYPE "public"."users_status_enum" ADD VALUE IF NOT EXISTS 'PENDING'`,
    );
  }

  public async down(): Promise<void> {
    // PostgreSQL cannot drop a single value from an enum type without
    // recreating the type and rewriting every dependent column. `PENDING` is
    // additive and harmless to leave in place, so this is intentionally a no-op.
  }
}
