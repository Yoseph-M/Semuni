import { Entity, Column, Index } from 'typeorm';
import { BaseEntity } from '../../common/entities/base.entity';
import { TripStatus, PaymentStatus, Currency } from '../../common/enums';

@Entity('trips')
export class Trip extends BaseEntity {
  @Column()
  @Index()
  passengerId: string;

  @Column()
  @Index()
  driverId: string;

  @Column({ nullable: true })
  vehicleId?: string;

  @Column()
  routeId: string;

  @Column({ nullable: true })
  originStopId?: string;

  @Column({ nullable: true })
  destinationStopId?: string;

  @Column()
  origin: string;

  @Column()
  destination: string;

  @Column({ type: 'int' })
  fareAmount: number;

  @Column({ type: 'enum', enum: Currency, default: Currency.ETB })
  currency: Currency;

  @Column({ nullable: true })
  tariffId?: string;

  @Column({ nullable: true })
  tariffRuleId?: string;

  @Column({ nullable: true })
  tariffVersion?: string;

  @Column({ type: 'enum', enum: TripStatus, default: TripStatus.PENDING })
  status: TripStatus;

  @Column({ type: 'enum', enum: PaymentStatus, default: PaymentStatus.UNPAID })
  paymentStatus: PaymentStatus;

  @Column({ nullable: true })
  @Index()
  paymentId?: string;

  @Column({ type: 'timestamp with time zone', nullable: true })
  startedAt?: Date;

  @Column({ type: 'timestamp with time zone', nullable: true })
  completedAt?: Date;
}
