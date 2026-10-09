import { Entity, Column, Index, Check, ManyToOne, JoinColumn } from 'typeorm';
import { Wallet } from '../../wallets/entities/wallet.entity';
import { BaseEntity } from '../../common/entities/base.entity';
import { LedgerDirection, LedgerEntryType, Currency } from '../../common/enums';

@Entity('ledger_entries')
// Append-only: UPDATE/DELETE/TRUNCATE are rejected by database triggers
// (migration ForeignKeysAndAppendOnlyLedger1790780000000).
@Check('CHK_ledger_amount_positive', '"amount" > 0')
@Check('CHK_ledger_balance_nonnegative', '"balanceBefore" >= 0 AND "balanceAfter" >= 0')
@Check(
  'CHK_ledger_balance_arithmetic',
  `("direction" = 'CREDIT' AND "balanceAfter" = "balanceBefore" + "amount") OR ("direction" = 'DEBIT' AND "balanceAfter" = "balanceBefore" - "amount")`,
)
// One financial transaction writes at most one entry of a given type per wallet:
// trip settlement is exactly one passenger debit plus one driver credit.
@Index(
  'UQ_ledger_transaction_wallet_entry_type',
  ['transactionId', 'walletId', 'entryType'],
  { unique: true, where: '"transactionId" IS NOT NULL' },
)
// Independent replay protection: one movement per (wallet, reference, type), so
// a replayed top-up confirmation or withdrawal callback cannot move money twice.
@Index(
  'UQ_ledger_wallet_reference_entry_type',
  ['walletId', 'referenceType', 'referenceId', 'entryType'],
  { unique: true, where: '"referenceId" IS NOT NULL' },
)
export class LedgerEntry extends BaseEntity {
  @Column({ type: 'uuid' })
  @Index()
  walletId: string;

  @ManyToOne(() => Wallet)
  @JoinColumn({ name: 'walletId', foreignKeyConstraintName: 'FK_ledger_entries_walletId' })
  wallet?: Wallet;

  @Column({ nullable: true })
  @Index()
  transactionId?: string;

  @Column({ type: 'enum', enum: LedgerEntryType })
  entryType: LedgerEntryType;

  @Column({ type: 'enum', enum: LedgerDirection })
  direction: LedgerDirection;

  @Column({ type: 'int' })
  amount: number;

  @Column({ type: 'enum', enum: Currency, default: Currency.ETB })
  currency: Currency;

  @Column({ type: 'int' })
  balanceBefore: number;

  @Column({ type: 'int' })
  balanceAfter: number;

  @Column({ nullable: true })
  referenceType?: string;

  @Column({ nullable: true })
  @Index()
  referenceId?: string;

  @Column({ nullable: true })
  description?: string;
}
