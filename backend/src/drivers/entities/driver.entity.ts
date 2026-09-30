import { Entity, Column, OneToOne, JoinColumn } from 'typeorm';
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

  @Column({ nullable: true })
  walletId?: string;
}
