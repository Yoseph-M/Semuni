import { Entity, Column, ManyToOne, Index } from 'typeorm';
import { BaseEntity } from '../../common/entities/base.entity';
import { Route } from './route.entity';

@Entity('route_stops')
@Index('UQ_route_stop_sequence', ['route', 'sequence'], { unique: true })
export class RouteStop extends BaseEntity {
  @ManyToOne(() => Route, (route) => route.stops, { onDelete: 'CASCADE' })
  route: Route;

  @Column()
  name: string;

  @Column({ type: 'int' })
  sequence: number;

  @Column({ type: 'decimal', precision: 10, scale: 6, nullable: true })
  latitude?: number;

  @Column({ type: 'decimal', precision: 10, scale: 6, nullable: true })
  longitude?: number;
}
