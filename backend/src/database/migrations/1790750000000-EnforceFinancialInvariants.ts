import { MigrationInterface, QueryRunner } from 'typeorm';

export class EnforceFinancialInvariants1790750000000 implements MigrationInterface {
  name = 'EnforceFinancialInvariants1790750000000';

  public async up(queryRunner: QueryRunner): Promise<void> {
    // A trip can settle at most once. This is the database backstop against
    // concurrent payment requests; the service must still lock/recheck state.
    await queryRunner.query(
      'CREATE UNIQUE INDEX "UQ_payments_trip" ON "payments" ("tripId")',
    );

    // One financial transaction may emit one ledger entry per wallet and entry
    // type. Trip settlement therefore has exactly one passenger debit and one
    // driver credit, while retries cannot append a second copy.
    await queryRunner.query(
      'CREATE UNIQUE INDEX "UQ_ledger_transaction_wallet_entry_type" ON "ledger_entries" ("transactionId", "walletId", "entryType")',
    );

    // Ledger rows must describe a positive movement and their balance snapshot
    // must agree with the direction. These checks make the ledger auditable even
    // if an application bug attempts to write an impossible row.
    await queryRunner.query(
      'ALTER TABLE "ledger_entries" ADD CONSTRAINT "CHK_ledger_amount_positive" CHECK ("amount" > 0)',
    );
    await queryRunner.query(
      'ALTER TABLE "ledger_entries" ADD CONSTRAINT "CHK_ledger_balance_direction" CHECK (("direction" = \'CREDIT\' AND "balanceAfter" = "balanceBefore" + "amount") OR ("direction" = \'DEBIT\' AND "balanceAfter" = "balanceBefore" - "amount"))',
    );

    await queryRunner.query(
      'ALTER TABLE "wallets" ADD CONSTRAINT "CHK_wallet_balance_nonnegative" CHECK ("balance" >= 0)',
    );
    await queryRunner.query(
      'ALTER TABLE "payments" ADD CONSTRAINT "CHK_payment_amount_positive" CHECK ("amount" > 0)',
    );
    await queryRunner.query(
      'ALTER TABLE "top_up_intents" ADD CONSTRAINT "CHK_top_up_amount_positive" CHECK ("amountMinor" > 0)',
    );
    await queryRunner.query(
      'ALTER TABLE "withdrawals" ADD CONSTRAINT "CHK_withdrawal_amount_positive" CHECK ("amount" > 0)',
    );
  }

  public async down(queryRunner: QueryRunner): Promise<void> {
    await queryRunner.query(
      'ALTER TABLE "withdrawals" DROP CONSTRAINT "CHK_withdrawal_amount_positive"',
    );
    await queryRunner.query(
      'ALTER TABLE "top_up_intents" DROP CONSTRAINT "CHK_top_up_amount_positive"',
    );
    await queryRunner.query(
      'ALTER TABLE "payments" DROP CONSTRAINT "CHK_payment_amount_positive"',
    );
    await queryRunner.query(
      'ALTER TABLE "wallets" DROP CONSTRAINT "CHK_wallet_balance_nonnegative"',
    );
    await queryRunner.query(
      'ALTER TABLE "ledger_entries" DROP CONSTRAINT "CHK_ledger_balance_direction"',
    );
    await queryRunner.query(
      'ALTER TABLE "ledger_entries" DROP CONSTRAINT "CHK_ledger_amount_positive"',
    );
    await queryRunner.query(
      'DROP INDEX "public"."UQ_ledger_transaction_wallet_entry_type"',
    );
    await queryRunner.query(
      'DROP INDEX "public"."UQ_payments_trip"',
    );
  }
}
