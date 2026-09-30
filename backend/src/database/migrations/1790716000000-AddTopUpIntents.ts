import { MigrationInterface, QueryRunner } from 'typeorm';

/**
 * Adds `top_up_intents`.
 *
 * Wallet top-ups previously credited the balance the moment the client called
 * the endpoint. Money entering the system must instead be recorded as an intent
 * that only becomes SUCCESS once the payment provider confirms it, so the
 * confirmation step needs its own durable row.
 */
export class AddTopUpIntents1790716000000 implements MigrationInterface {
  name = 'AddTopUpIntents1790716000000';

  public async up(queryRunner: QueryRunner): Promise<void> {
    await queryRunner.query(
      `DO $$ BEGIN CREATE TYPE "public"."top_up_intents_currency_enum" AS ENUM('ETB'); EXCEPTION WHEN duplicate_object THEN null; END $$`,
    );
    await queryRunner.query(
      `DO $$ BEGIN CREATE TYPE "public"."top_up_intents_provider_enum" AS ENUM('MOCK', 'TELEBIRR', 'CHAPA', 'BANK'); EXCEPTION WHEN duplicate_object THEN null; END $$`,
    );
    await queryRunner.query(
      `DO $$ BEGIN CREATE TYPE "public"."top_up_intents_status_enum" AS ENUM('PENDING', 'SUCCESS', 'FAILED', 'EXPIRED'); EXCEPTION WHEN duplicate_object THEN null; END $$`,
    );

    await queryRunner.query(
      `CREATE TABLE "top_up_intents" (
        "id" uuid NOT NULL DEFAULT uuid_generate_v4(),
        "createdAt" TIMESTAMP WITH TIME ZONE NOT NULL DEFAULT now(),
        "updatedAt" TIMESTAMP WITH TIME ZONE NOT NULL DEFAULT now(),
        "userId" uuid NOT NULL,
        "amountMinor" integer NOT NULL,
        "currency" "public"."top_up_intents_currency_enum" NOT NULL DEFAULT 'ETB',
        "provider" "public"."top_up_intents_provider_enum" NOT NULL DEFAULT 'MOCK',
        "status" "public"."top_up_intents_status_enum" NOT NULL DEFAULT 'PENDING',
        "providerReference" character varying,
        "idempotencyKey" character varying NOT NULL,
        "completedAt" TIMESTAMP WITH TIME ZONE,
        "failureReason" character varying,
        CONSTRAINT "UQ_top_up_intents_idempotencyKey" UNIQUE ("idempotencyKey"),
        CONSTRAINT "UQ_top_up_intents_providerReference" UNIQUE ("providerReference"),
        CONSTRAINT "PK_top_up_intents" PRIMARY KEY ("id")
      )`,
    );

    await queryRunner.query(
      `CREATE INDEX "IDX_top_up_intents_userId" ON "top_up_intents" ("userId")`,
    );
    await queryRunner.query(
      `ALTER TABLE "top_up_intents" ADD CONSTRAINT "FK_top_up_intents_userId"
         FOREIGN KEY ("userId") REFERENCES "users"("id") ON DELETE NO ACTION ON UPDATE NO ACTION`,
    );
  }

  public async down(queryRunner: QueryRunner): Promise<void> {
    await queryRunner.query(
      `ALTER TABLE "top_up_intents" DROP CONSTRAINT "FK_top_up_intents_userId"`,
    );
    await queryRunner.query(`DROP TABLE "top_up_intents"`);
    await queryRunner.query(
      `DROP TYPE "public"."top_up_intents_status_enum"`,
    );
    await queryRunner.query(
      `DROP TYPE "public"."top_up_intents_provider_enum"`,
    );
    await queryRunner.query(
      `DROP TYPE "public"."top_up_intents_currency_enum"`,
    );
  }
}
