import { MigrationInterface, QueryRunner } from 'typeorm';

/**
 * Phase 6 — financial integrity enforced by PostgreSQL itself.
 *
 * The service layer validates first so callers get precise domain errors, but
 * application checks are not the integrity boundary: this migration makes the
 * database reject impossible financial state even if a future code path (or a
 * concurrent request) violates an invariant.
 *
 * Two deliberate design points:
 *
 *  1. Payment uniqueness is scoped to SUCCESS. A trip may have many durable
 *     *attempt* records (PENDING / FAILED — see Phase 7) but only one payment
 *     that actually moved money. A blanket UNIQUE("tripId") would make a failed
 *     attempt permanently unpayable.
 *
 *  2. Ledger uniqueness is expressed per (transaction, wallet, entry type) and
 *     per (wallet, reference, entry type). Together they make replay impossible:
 *     a retried callback cannot append a second movement for the same reference.
 */
export class EnforceFinancialInvariants1790750000000
  implements MigrationInterface
{
  name = 'EnforceFinancialInvariants1790750000000';

  public async up(queryRunner: QueryRunner): Promise<void> {
    // ── One successful payment per trip ──────────────────────────────────────
    // The database backstop for concurrent payment requests: even if two
    // transactions both passed the application check, only one row can reach
    // SUCCESS for a given trip.
    await queryRunner.query(
      `CREATE UNIQUE INDEX "UQ_payments_trip_success" ON "payments" ("tripId") WHERE "status" = 'SUCCESS'`,
    );

    // ── External references are consumed at most once ────────────────────────
    // A provider reference identifies one external money movement, so it must
    // never be attached to two payment records.
    await queryRunner.query(
      `CREATE UNIQUE INDEX "UQ_payments_provider_reference" ON "payments" ("providerReference") WHERE "providerReference" IS NOT NULL`,
    );

    // Receipt numbers are handed to users and quoted in disputes; two payments
    // sharing one would make a receipt unverifiable.
    //
    // Existing rows are repaired explicitly first (see below): the old
    // `countToday() + 1` scheme restarted its counter every day, so the first
    // payment of two different days was minted the same number. Those receipts
    // were already unverifiable — both payments claim one number — so keeping
    // them as found is not an option, and neither is silently discarding a
    // payment. The repair renumbers only the *later* duplicates.
    await this.repairDuplicateReceiptNumbers(queryRunner);
    await queryRunner.query(
      `CREATE UNIQUE INDEX "UQ_payments_receipt_number" ON "payments" ("receiptNumber") WHERE "receiptNumber" IS NOT NULL`,
    );

    // ── Ledger replay protection ─────────────────────────────────────────────
    // A single financial transaction writes at most one entry of a given type
    // per wallet: trip settlement is exactly one passenger debit plus one
    // driver credit, and a retry cannot append a second copy.
    await queryRunner.query(
      `CREATE UNIQUE INDEX "UQ_ledger_transaction_wallet_entry_type" ON "ledger_entries" ("transactionId", "walletId", "entryType") WHERE "transactionId" IS NOT NULL`,
    );

    // Independently of any transaction id: one movement per (wallet, external
    // reference, entry type). This is what makes a replayed top-up confirmation
    // or withdrawal callback incapable of crediting/debiting twice.
    await queryRunner.query(
      `CREATE UNIQUE INDEX "UQ_ledger_wallet_reference_entry_type" ON "ledger_entries" ("walletId", "referenceType", "referenceId", "entryType") WHERE "referenceId" IS NOT NULL`,
    );

    // ── Amounts are positive, integral minor units ───────────────────────────
    await queryRunner.query(
      `ALTER TABLE "ledger_entries" ADD CONSTRAINT "CHK_ledger_amount_positive" CHECK ("amount" > 0)`,
    );
    await queryRunner.query(
      `ALTER TABLE "payments" ADD CONSTRAINT "CHK_payment_amount_positive" CHECK ("amount" > 0)`,
    );
    await queryRunner.query(
      `ALTER TABLE "top_up_intents" ADD CONSTRAINT "CHK_top_up_amount_positive" CHECK ("amountMinor" > 0)`,
    );
    await queryRunner.query(
      `ALTER TABLE "withdrawals" ADD CONSTRAINT "CHK_withdrawal_amount_positive" CHECK ("amount" > 0)`,
    );

    // ── A wallet balance can never go negative ───────────────────────────────
    await queryRunner.query(
      `ALTER TABLE "wallets" ADD CONSTRAINT "CHK_wallet_balance_nonnegative" CHECK ("balance" >= 0)`,
    );

    // ── Ledger rows must describe a reachable balance ────────────────────────
    // Every entry states where the balance came from and where it went, so the
    // ledger is auditable from the rows alone:
    //   CREDIT: balanceAfter = balanceBefore + amount
    //   DEBIT:  balanceAfter = balanceBefore - amount
    await queryRunner.query(
      `ALTER TABLE "ledger_entries" ADD CONSTRAINT "CHK_ledger_balance_arithmetic" CHECK (("direction" = 'CREDIT' AND "balanceAfter" = "balanceBefore" + "amount") OR ("direction" = 'DEBIT' AND "balanceAfter" = "balanceBefore" - "amount"))`,
    );
    await queryRunner.query(
      `ALTER TABLE "ledger_entries" ADD CONSTRAINT "CHK_ledger_balance_nonnegative" CHECK ("balanceBefore" >= 0 AND "balanceAfter" >= 0)`,
    );
  }

  /**
   * Gives every payment a unique receipt number, touching as little as possible.
   *
   * The first payment to claim a number keeps it (it is the one a user is most
   * likely to have been shown); later duplicates are re-numbered from a range
   * above the highest existing number, so the new values cannot collide with any
   * legacy receipt either. Every change is printed, because a renumbered receipt
   * is something an operator needs to be able to see afterwards.
   *
   * A no-op once the data is already clean, so re-running is safe.
   */
  private async repairDuplicateReceiptNumbers(
    queryRunner: QueryRunner,
  ): Promise<void> {
    const duplicates: Array<{
      id: string;
      receiptNumber: string;
      createdAt: Date;
    }> = await queryRunner.query(
      `WITH ranked AS (
         SELECT id, "receiptNumber", "createdAt",
                row_number() OVER (PARTITION BY "receiptNumber" ORDER BY "createdAt", id) AS rn
         FROM payments
         WHERE "receiptNumber" IS NOT NULL
       )
       SELECT id, "receiptNumber", "createdAt" FROM ranked WHERE rn > 1
       ORDER BY "createdAt", id`,
    );

    if (duplicates.length === 0) return;

    console.log(
      `[${this.name}] re-numbering ${duplicates.length} duplicate receipt(s) - the first holder of each number keeps it`,
    );
    for (const duplicate of duplicates) {
      console.log(
        `  payment ${duplicate.id}: ${duplicate.receiptNumber} (${duplicate.createdAt?.toISOString?.() ?? duplicate.createdAt})`,
      );
    }

    await queryRunner.query(
      `WITH ranked AS (
         SELECT id, "receiptNumber", "createdAt",
                row_number() OVER (PARTITION BY "receiptNumber" ORDER BY "createdAt", id) AS rn
         FROM payments
         WHERE "receiptNumber" IS NOT NULL
       ),
       dup AS (
         SELECT id, "createdAt",
                row_number() OVER (ORDER BY "createdAt", id) AS offset_seq
         FROM ranked WHERE rn > 1
       ),
       base AS (
         SELECT COALESCE(
                  MAX((regexp_replace("receiptNumber", '^SEM-[0-9]{4}-', ''))::int), 0
                ) AS max_seq
         FROM payments
         WHERE "receiptNumber" ~ '^SEM-[0-9]{4}-[0-9]+$'
       )
       UPDATE payments p
       SET "receiptNumber" = 'SEM-' || to_char(p."createdAt", 'YYYY') || '-' ||
             lpad(((SELECT max_seq FROM base) + dup.offset_seq)::text, 6, '0')
       FROM dup
       WHERE p.id = dup.id`,
    );
  }

  public async down(queryRunner: QueryRunner): Promise<void> {
    await queryRunner.query(
      `ALTER TABLE "ledger_entries" DROP CONSTRAINT "CHK_ledger_balance_nonnegative"`,
    );
    await queryRunner.query(
      `ALTER TABLE "ledger_entries" DROP CONSTRAINT "CHK_ledger_balance_arithmetic"`,
    );
    await queryRunner.query(
      `ALTER TABLE "wallets" DROP CONSTRAINT "CHK_wallet_balance_nonnegative"`,
    );
    await queryRunner.query(
      `ALTER TABLE "withdrawals" DROP CONSTRAINT "CHK_withdrawal_amount_positive"`,
    );
    await queryRunner.query(
      `ALTER TABLE "top_up_intents" DROP CONSTRAINT "CHK_top_up_amount_positive"`,
    );
    await queryRunner.query(
      `ALTER TABLE "payments" DROP CONSTRAINT "CHK_payment_amount_positive"`,
    );
    await queryRunner.query(
      `ALTER TABLE "ledger_entries" DROP CONSTRAINT "CHK_ledger_amount_positive"`,
    );

    await queryRunner.query(
      `DROP INDEX "public"."UQ_ledger_wallet_reference_entry_type"`,
    );
    await queryRunner.query(
      `DROP INDEX "public"."UQ_ledger_transaction_wallet_entry_type"`,
    );
    await queryRunner.query(
      `DROP INDEX "public"."UQ_payments_receipt_number"`,
    );
    await queryRunner.query(
      `DROP INDEX "public"."UQ_payments_provider_reference"`,
    );
    await queryRunner.query(`DROP INDEX "public"."UQ_payments_trip_success"`);
  }
}
