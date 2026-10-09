import { Entity, Column, Index, ManyToOne, JoinColumn } from 'typeorm';
import { User } from '../../users/entities/user.entity';
import { Withdrawal } from '../../withdrawals/entities/withdrawal.entity';
import { BaseEntity } from '../../common/entities/base.entity';
import {
  WithdrawalStatus,
  Currency,
} from '../../common/enums';

@Entity('settlements')
export class Settlement extends BaseEntity {
  @Column({ type: 'uuid' })
  @Index()
  driverId: string;

  @ManyToOne(() => User)
  @JoinColumn({ name: 'driverId', foreignKeyConstraintName: 'FK_settlements_driverId' })
  driver?: User;

  @Column({ type: 'uuid', nullable: true })
  @Index()
  withdrawalId?: string;

  @ManyToOne(() => Withdrawal)
  @JoinColumn({ name: 'withdrawalId', foreignKeyConstraintName: 'FK_settlements_withdrawalId' })
  withdrawal?: Withdrawal;

  @Column({ type: 'int' })
  amount: number;

  @Column({ type: 'enum', enum: Currency, default: Currency.ETB })
  currency: Currency;

  @Column({ type: 'enum', enum: WithdrawalStatus, default: WithdrawalStatus.PENDING })
  status: WithdrawalStatus;

  @Column({ nullable: true })
  externalReference?: string;

  @Column({ type: 'timestamp with time zone', nullable: true })
  completedAt?: Date;
}
