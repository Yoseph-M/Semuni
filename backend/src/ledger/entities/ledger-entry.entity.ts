import { Entity, Column, Index } from 'typeorm';
import { BaseEntity } from '../../common/entities/base.entity';
import { LedgerDirection, LedgerEntryType, Currency } from '../../common/enums';

@Entity('ledger_entries')
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
