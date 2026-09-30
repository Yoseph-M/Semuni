import { Entity, Column, Index } from 'typeorm';
import { BaseEntity } from '../../common/entities/base.entity';
import {
  WithdrawalStatus,
  Currency,
} from '../../common/enums';

@Entity('settlements')
export class Settlement extends BaseEntity {
  @Column()
  @Index()
  driverId: string;

  @Column({ nullable: true })
  @Index()
  withdrawalId?: string;

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
