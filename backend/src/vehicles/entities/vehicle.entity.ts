import { Entity, Column } from 'typeorm';
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

  @Column({ nullable: true })
  driverId?: string; // Links back to a driver for simple assignment
}
