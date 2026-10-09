import { Entity, Column, OneToOne, JoinColumn, Check } from 'typeorm';
import { BaseEntity } from '../../common/entities/base.entity';
import { User } from '../../users/entities/user.entity';
import { WalletStatus, Currency } from '../../common/enums';

@Entity('wallets')
@Check('CHK_wallet_balance_nonnegative', '"balance" >= 0')
export class Wallet extends BaseEntity {
  @OneToOne(() => User)
  @JoinColumn()
  user: User;

  // Current balance in minor units (e.g., santim)
  @Column({ type: 'int', default: 0 })
  balance: number;

  @Column({ type: 'enum', enum: Currency, default: Currency.ETB })
  currency: Currency;

  @Column({ type: 'enum', enum: WalletStatus, default: WalletStatus.ACTIVE })
  status: WalletStatus;
}
