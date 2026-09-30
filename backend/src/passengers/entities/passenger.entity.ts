import { Entity, Column, OneToOne, JoinColumn } from 'typeorm';
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

  @Column({ nullable: true })
  walletId?: string; // loosely coupled to Wallet aggregate
}
