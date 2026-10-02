import { Entity, Column, Index } from 'typeorm';
import { BaseEntity } from '../../common/entities/base.entity';
import { LedgerDirection, LedgerEntryType, Currency } from '../../common/enums';

@Entity('ledger_entries')
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
  @Column()
  @Index()
  walletId: string;

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
