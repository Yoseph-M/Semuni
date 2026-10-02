import { Entity, Column, Index, ManyToOne, JoinColumn } from 'typeorm';
import { User } from '../../users/entities/user.entity';
import { Vehicle } from '../../vehicles/entities/vehicle.entity';
import { Route } from '../../routes/entities/route.entity';
import { RouteStop } from '../../routes/entities/route-stop.entity';
import { Tariff } from '../../tariffs/entities/tariff.entity';
import { TariffRule } from '../../tariffs/entities/tariff-rule.entity';
import { BaseEntity } from '../../common/entities/base.entity';
import { TripStatus, PaymentStatus, Currency } from '../../common/enums';

@Entity('trips')
export class Trip extends BaseEntity {
  @Column({ type: 'uuid' })
  @Index()
  passengerId: string;

  @ManyToOne(() => User)
  @JoinColumn({ name: 'passengerId', foreignKeyConstraintName: 'FK_trips_passengerId' })
  passenger?: User;

  @Column({ type: 'uuid' })
  @Index()
  driverId: string;

  @ManyToOne(() => User)
  @JoinColumn({ name: 'driverId', foreignKeyConstraintName: 'FK_trips_driverId' })
  driver?: User;

  @Column({ type: 'uuid', nullable: true })
  @Index('IDX_trips_vehicleId')
  vehicleId?: string;

  @ManyToOne(() => Vehicle)
  @JoinColumn({ name: 'vehicleId', foreignKeyConstraintName: 'FK_trips_vehicleId' })
  vehicle?: Vehicle;

  @Column({ type: 'uuid', nullable: true })
  @Index('IDX_trips_routeId')
  routeId: string;

  @ManyToOne(() => Route)
  @JoinColumn({ name: 'routeId', foreignKeyConstraintName: 'FK_trips_routeId' })
  route?: Route;

  @Column({ type: 'uuid', nullable: true })
  @Index('IDX_trips_originStopId')
  originStopId?: string;

  @ManyToOne(() => RouteStop)
  @JoinColumn({ name: 'originStopId', foreignKeyConstraintName: 'FK_trips_originStopId' })
  originStop?: RouteStop;

  @Column({ type: 'uuid', nullable: true })
  @Index('IDX_trips_destinationStopId')
  destinationStopId?: string;

  @ManyToOne(() => RouteStop)
  @JoinColumn({ name: 'destinationStopId', foreignKeyConstraintName: 'FK_trips_destinationStopId' })
  destinationStop?: RouteStop;

  @Column()
  origin: string;

  @Column()
  destination: string;

  @Column({ type: 'int' })
  fareAmount: number;

  @Column({ type: 'enum', enum: Currency, default: Currency.ETB })
  currency: Currency;

  @Column({ type: 'uuid', nullable: true })
  @Index('IDX_trips_tariffId')
  tariffId?: string;

  @ManyToOne(() => Tariff)
  @JoinColumn({ name: 'tariffId', foreignKeyConstraintName: 'FK_trips_tariffId' })
  tariff?: Tariff;

  @Column({ type: 'uuid', nullable: true })
  @Index('IDX_trips_tariffRuleId')
  tariffRuleId?: string;

  @ManyToOne(() => TariffRule)
  @JoinColumn({ name: 'tariffRuleId', foreignKeyConstraintName: 'FK_trips_tariffRuleId' })
  tariffRule?: TariffRule;

  @Column({ nullable: true })
  tariffVersion?: string;

  @Column({ type: 'enum', enum: TripStatus, default: TripStatus.PENDING })
  status: TripStatus;

  @Column({ type: 'enum', enum: PaymentStatus, default: PaymentStatus.UNPAID })
  paymentStatus: PaymentStatus;

  /** No FK: `payments.tripId` is the owning edge (avoids a circular pair). */
  @Column({ type: 'uuid', nullable: true })
  @Index()
  paymentId?: string;

  @Column({ type: 'timestamp with time zone', nullable: true })
  startedAt?: Date;

  @Column({ type: 'timestamp with time zone', nullable: true })
  completedAt?: Date;
}
