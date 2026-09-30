import { Entity, Column, OneToMany } from 'typeorm';
import { BaseEntity } from '../../common/entities/base.entity';
import { Currency } from '../../common/enums';
import { TariffRule } from './tariff-rule.entity';

@Entity('tariffs')
export class Tariff extends BaseEntity {
  @Column()
  name: string;

  @Column({ type: 'timestamp with time zone' })
  validFrom: Date;

  @Column({ type: 'timestamp with time zone', nullable: true })
  validTo?: Date;

  @Column({ type: 'enum', enum: Currency, default: Currency.ETB })
  currency: Currency;

  @OneToMany(() => TariffRule, (rule) => rule.tariff, { cascade: true })
  rules: TariffRule[];
}
