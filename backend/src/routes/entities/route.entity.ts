import { Entity, Column, OneToMany } from 'typeorm';
import { BaseEntity } from '../../common/entities/base.entity';
import { RouteStatus } from '../../common/enums';
import { RouteStop } from './route-stop.entity';

@Entity('routes')
export class Route extends BaseEntity {
  @Column()
  name: string;

  @Column()
  origin: string;

  @Column()
  destination: string;

  @Column({ unique: true })
  code: string;

  @Column({ type: 'enum', enum: RouteStatus, default: RouteStatus.ACTIVE })
  status: RouteStatus;

  @OneToMany(() => RouteStop, (stop) => stop.route, { cascade: true })
  stops: RouteStop[];
}
