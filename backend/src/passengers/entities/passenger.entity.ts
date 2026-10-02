import { Entity, Column, OneToOne, JoinColumn, Index, ManyToOne } from 'typeorm';
import { Wallet } from '../../wallets/entities/wallet.entity';
import { BaseEntity } from '../../common/entities/base.entity';
import { User } from '../../users/entities/user.entity';

@Entity('passengers')
export class Passenger extends BaseEntity {
  @OneToOne(() => User)
  @JoinColumn()
  user: User;

  @Column()
  userId: string;

  @Column()
  fullName: string;

  @Column({ nullable: true })
  phone?: string; // duplicated from user for easy access

  /** Convenience pointer; the owning edge is `wallets.userId`. */
  @Column({ type: 'uuid', nullable: true })
  @Index('IDX_passengers_walletId')
  walletId?: string;

  @ManyToOne(() => Wallet, { onDelete: 'SET NULL' })
  @JoinColumn({ name: 'walletId', foreignKeyConstraintName: 'FK_passengers_walletId' })
  wallet?: Wallet;
}
