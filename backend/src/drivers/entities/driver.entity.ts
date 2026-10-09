import { Entity, Column, OneToOne, JoinColumn, Index, ManyToOne } from 'typeorm';
import { Wallet } from '../../wallets/entities/wallet.entity';
import { BaseEntity } from '../../common/entities/base.entity';
import { User } from '../../users/entities/user.entity';
import { DriverStatus } from '../../common/enums';

@Entity('drivers')
export class Driver extends BaseEntity {
  @OneToOne(() => User)
  @JoinColumn()
  user: User;

  @Column()
  userId: string;

  @Column()
  fullName: string;

  @Column({ nullable: true })
  phone?: string;

  @Column()
  licenseNumber: string;

  @Column({ type: 'enum', enum: DriverStatus, default: DriverStatus.PENDING })
  status: DriverStatus;

  /** Convenience pointer; the owning edge is `wallets.userId`. */
  @Column({ type: 'uuid', nullable: true })
  @Index('IDX_drivers_walletId')
  walletId?: string;

  @ManyToOne(() => Wallet, { onDelete: 'SET NULL' })
  @JoinColumn({ name: 'walletId', foreignKeyConstraintName: 'FK_drivers_walletId' })
  wallet?: Wallet;
}
