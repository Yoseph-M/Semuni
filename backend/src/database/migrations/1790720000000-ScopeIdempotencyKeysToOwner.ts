import { MigrationInterface, QueryRunner } from 'typeorm';

/**
 * Scopes idempotency keys to their owner.
 *
 * `idempotencyKey` used to be globally unique on payments, withdrawals and
 * top-up intents. That made one user's key collide with another user's and
 * allowed a lookup by key alone to return (or block) a foreign operation, so an
 * attacker-chosen string could reach someone else's money movement.
 *
 * Uniqueness now includes the owning user:
 *   payments        (passengerId, idempotencyKey)
 *   withdrawals     (userId, idempotencyKey)
 *   top_up_intents  (userId, idempotencyKey)
 *
 * Note on `down()`: restoring the global constraints can fail if two different
 * users have since used the same key. That is intentional — failing loudly is
 * better than silently discarding a key that now identifies more than one
 * operation.
 */
export class ScopeIdempotencyKeysToOwner1790720000000
  implements MigrationInterface
{
  name = 'ScopeIdempotencyKeysToOwner1790720000000';

  public async up(queryRunner: QueryRunner): Promise<void> {
    await queryRunner.query(
      `ALTER TABLE "payments" DROP CONSTRAINT "UQ_743b9fb1d2a059f2f7860418e4e"`,
    );
    await queryRunner.query(
      `CREATE UNIQUE INDEX "UQ_payments_passenger_idempotency" ON "payments" ("passengerId", "idempotencyKey")`,
    );

    await queryRunner.query(
      `ALTER TABLE "withdrawals" DROP CONSTRAINT "UQ_448416a5a1d5de32c06e3bbbdd6"`,
    );
    await queryRunner.query(
      `CREATE UNIQUE INDEX "UQ_withdrawals_user_idempotency" ON "withdrawals" ("userId", "idempotencyKey")`,
    );

    await queryRunner.query(
      `ALTER TABLE "top_up_intents" DROP CONSTRAINT "UQ_top_up_intents_idempotencyKey"`,
    );
    await queryRunner.query(
      `CREATE UNIQUE INDEX "UQ_top_up_intents_user_idempotency" ON "top_up_intents" ("userId", "idempotencyKey")`,
    );
  }

  public async down(queryRunner: QueryRunner): Promise<void> {
    await queryRunner.query(
      `DROP INDEX "public"."UQ_top_up_intents_user_idempotency"`,
    );
    await queryRunner.query(
      `ALTER TABLE "top_up_intents" ADD CONSTRAINT "UQ_top_up_intents_idempotencyKey" UNIQUE ("idempotencyKey")`,
    );

    await queryRunner.query(
      `DROP INDEX "public"."UQ_withdrawals_user_idempotency"`,
    );
    await queryRunner.query(
      `ALTER TABLE "withdrawals" ADD CONSTRAINT "UQ_448416a5a1d5de32c06e3bbbdd6" UNIQUE ("idempotencyKey")`,
    );

    await queryRunner.query(
      `DROP INDEX "public"."UQ_payments_passenger_idempotency"`,
    );
    await queryRunner.query(
      `ALTER TABLE "payments" ADD CONSTRAINT "UQ_743b9fb1d2a059f2f7860418e4e" UNIQUE ("idempotencyKey")`,
    );
  }
}
