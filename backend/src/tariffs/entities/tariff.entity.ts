import { Entity, Column, OneToMany, Index } from 'typeorm';
import { BaseEntity } from '../../common/entities/base.entity';
import { Currency, TariffStatus } from '../../common/enums';
import { TariffRule } from './tariff-rule.entity';

/**
 * A regulator-controlled pricing schedule.
 *
 * A tariff is identified by an immutable, never-reused `version` label
 * (e.g. `TARIFF-2026-001`); `name` is descriptive only and must not be used as
 * an identifier. Only a tariff whose `status` is ACTIVE and whose validity
 * window currently contains "now" may price a new fare.
 *
 * Lifecycle: DRAFT → ACTIVE → EXPIRED. Creation starts as DRAFT so that a new
 * price schedule can never take effect merely by being inserted; an explicit
 * admin activation is required.
 */
@Entity('tariffs')
export class Tariff extends BaseEntity {
  /** Immutable, unique, never-reused version identifier (e.g. TARIFF-2026-001). */
  @Column({ unique: true })
  version: string;

  @Column()
  name: string;

  // At most one tariff may be ACTIVE at a time. Enforced in PostgreSQL as well
  // as in the service, because two concurrently-published schedules would make
  // the authoritative fare ambiguous.
  @Index('UQ_tariffs_single_active', {
    unique: true,
    where: `"status" = 'ACTIVE'`,
  })
  @Column({ type: 'enum', enum: TariffStatus, default: TariffStatus.DRAFT })
  status: TariffStatus;

  @Column({ type: 'timestamp with time zone' })
  validFrom: Date;

  @Column({ type: 'timestamp with time zone', nullable: true })
  validTo?: Date;

  @Column({ type: 'enum', enum: Currency, default: Currency.ETB })
  currency: Currency;

  @OneToMany(() => TariffRule, (rule) => rule.tariff, { cascade: true })
  rules: TariffRule[];
}
