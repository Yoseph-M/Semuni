import { Entity, Column, ManyToOne } from 'typeorm';
import { BaseEntity } from '../../common/entities/base.entity';
import { Tariff } from './tariff.entity';
import { Route } from '../../routes/entities/route.entity';
import { VehicleType } from '../../common/enums';

@Entity('tariff_rules')
export class TariffRule extends BaseEntity {
  @ManyToOne(() => Tariff, (tariff) => tariff.rules, { onDelete: 'CASCADE' })
  tariff: Tariff;

  @ManyToOne(() => Route)
  route: Route;

  @Column({ type: 'enum', enum: VehicleType, nullable: true })
  vehicleType?: VehicleType;

  @Column({ type: 'int', nullable: true })
  startStopSequence?: number;

  @Column({ type: 'int', nullable: true })
  endStopSequence?: number;

  // The base price for this rule in minor units (e.g., santim)
  @Column({ type: 'int' })
  basePrice: number;
}
