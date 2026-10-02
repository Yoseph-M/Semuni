import { Entity, Column, Index, ManyToOne, JoinColumn } from 'typeorm';
import { User } from '../../users/entities/user.entity';
import { BaseEntity } from '../../common/entities/base.entity';
import { VehicleType, VehicleStatus } from '../../common/enums';

@Entity('vehicles')
export class Vehicle extends BaseEntity {
  @Column({ unique: true })
  plateNumber: string;

  @Column({ type: 'enum', enum: VehicleType, default: VehicleType.MINIBUS })
  vehicleType: VehicleType;

  @Column({ type: 'int', default: 12 })
  capacity: number;

  @Column({ type: 'enum', enum: VehicleStatus, default: VehicleStatus.ACTIVE })
  status: VehicleStatus;

  /** The assigned driver's user id. */
  @Column({ type: 'uuid', nullable: true })
  @Index('IDX_vehicles_driverId')
  driverId?: string;

  @ManyToOne(() => User)
  @JoinColumn({ name: 'driverId', foreignKeyConstraintName: 'FK_vehicles_driverId' })
  driver?: User;
}
