import { MigrationInterface, QueryRunner } from 'typeorm';

/** Stores the provider checkout URL so an idempotent re-initiation can return it. */
export class AddTopUpCheckoutUrl1790790000000 implements MigrationInterface {
  name = 'AddTopUpCheckoutUrl1790790000000';

  public async up(queryRunner: QueryRunner): Promise<void> {
    await queryRunner.query(`ALTER TABLE "top_up_intents" ADD "checkoutUrl" text`);
  }

  public async down(queryRunner: QueryRunner): Promise<void> {
    await queryRunner.query(`ALTER TABLE "top_up_intents" DROP COLUMN "checkoutUrl"`);
  }
}
