import { Injectable, HttpStatus } from '@nestjs/common';
import { InjectRepository } from '@nestjs/typeorm';
import {
  Repository,
  DataSource,
  EntityManager,
  LessThanOrEqual,
  IsNull,
  MoreThanOrEqual,
} from 'typeorm';
import { Tariff } from './entities/tariff.entity';
import { CreateTariffDto } from './dto/tariff.dto';
import { RoutesService } from '../routes/routes.service';
import { DomainException } from '../common/domain.exception';
import { ErrorCode } from '../common/error-codes';
import { RouteStatus, TariffStatus } from '../common/enums';

/**
 * Advisory-lock key that serialises tariff activation. Two admins publishing a
 * schedule at once must not both observe "no ACTIVE tariff" and both commit.
 */
const TARIFF_ACTIVATION_LOCK_KEY = 2026005001;

@Injectable()
export class TariffsService {
  constructor(
    @InjectRepository(Tariff)
    private readonly tariffRepository: Repository<Tariff>,
    private readonly routesService: RoutesService,
    private readonly dataSource: DataSource,
  ) {}

  /**
   * Creates a tariff in DRAFT. Creation never makes a schedule live: only an
   * explicit `activate` does, so inserting a row is not enough to change the
   * authoritative fare.
   */
  async create(dto: CreateTariffDto): Promise<Tariff> {
    if (!dto.rules || dto.rules.length === 0) {
      throw new DomainException(
        'A tariff must contain at least one rule',
        HttpStatus.BAD_REQUEST,
        ErrorCode.TARIFF_RULE_NOT_FOUND,
      );
    }

    const validFrom = new Date(dto.validFrom);
    if (Number.isNaN(validFrom.getTime())) {
      throw new DomainException(
        'Tariff validFrom must be a valid date',
        HttpStatus.BAD_REQUEST,
        ErrorCode.TARIFF_WINDOW_INVALID,
      );
    }
    const validTo = dto.validTo ? new Date(dto.validTo) : undefined;
    if (validTo && Number.isNaN(validTo.getTime())) {
      throw new DomainException(
        'Tariff validTo must be a valid date',
        HttpStatus.BAD_REQUEST,
        ErrorCode.TARIFF_WINDOW_INVALID,
      );
    }
    if (validTo && validTo <= validFrom) {
      throw new DomainException(
        'Tariff validTo must be after validFrom',
        HttpStatus.BAD_REQUEST,
        ErrorCode.TARIFF_WINDOW_INVALID,
      );
    }

    const duplicate = await this.tariffRepository.findOne({
      where: { version: dto.version },
    });
    if (duplicate) {
      throw new DomainException(
        `Tariff version ${dto.version} already exists; versions are never reused`,
        HttpStatus.CONFLICT,
        ErrorCode.TARIFF_VERSION_EXISTS,
      );
    }

    // Validate every rule against the route's real stop sequence. Tariffs are
    // authoritative financial data, so a dangling route or impossible segment
    // must be rejected at creation time.
    for (const rule of dto.rules) {
      const route = await this.routesService.findById(rule.routeId);
      if (route.status !== RouteStatus.ACTIVE) {
        throw new DomainException(
          `Route ${route.code} is not active`,
          HttpStatus.BAD_REQUEST,
          ErrorCode.ROUTE_INACTIVE,
        );
      }

      if (!Number.isInteger(rule.basePrice) || rule.basePrice <= 0) {
        throw new DomainException(
          'Tariff basePrice must be a positive integer in minor currency units',
          HttpStatus.BAD_REQUEST,
          ErrorCode.VALIDATION_ERROR,
        );
      }

      if (rule.startStopSequence != null || rule.endStopSequence != null) {
        if (rule.startStopSequence == null || rule.endStopSequence == null) {
          throw new DomainException(
            'Tariff stop ranges require both startStopSequence and endStopSequence',
            HttpStatus.BAD_REQUEST,
            ErrorCode.VALIDATION_ERROR,
          );
        }
        if (
          !Number.isInteger(rule.startStopSequence) ||
          !Number.isInteger(rule.endStopSequence) ||
          rule.startStopSequence >= rule.endStopSequence
        ) {
          throw new DomainException(
            'Tariff stop range must have startStopSequence < endStopSequence',
            HttpStatus.BAD_REQUEST,
            ErrorCode.STOP_ORDER_INVALID,
          );
        }

        const sequences = new Set(route.stops.map((stop) => stop.sequence));
        if (
          !sequences.has(rule.startStopSequence) ||
          !sequences.has(rule.endStopSequence)
        ) {
          throw new DomainException(
            'Tariff stop range must reference stops that exist on the route',
            HttpStatus.BAD_REQUEST,
            ErrorCode.STOP_NOT_FOUND,
          );
        }
      }
    }

    const tariff = this.tariffRepository.create({
      version: dto.version,
      name: dto.name,
      status: TariffStatus.DRAFT,
      validFrom,
      validTo,
      currency: dto.currency,
      rules: dto.rules.map((rule) => ({
        route: { id: rule.routeId },
        vehicleType: rule.vehicleType,
        startStopSequence: rule.startStopSequence,
        endStopSequence: rule.endStopSequence,
        basePrice: rule.basePrice,
      })),
    });

    try {
      return await this.tariffRepository.save(tariff);
    } catch (err) {
      // Two concurrent creates of the same version race past the pre-check;
      // the unique index is the integrity boundary and the loser reports the
      // same structured error as the sequential case.
      if (this.isUniqueViolation(err)) {
        throw new DomainException(
          `Tariff version ${dto.version} already exists; versions are never reused`,
          HttpStatus.CONFLICT,
          ErrorCode.TARIFF_VERSION_EXISTS,
        );
      }
      throw err;
    }
  }

  async findAll(): Promise<Tariff[]> {
    return this.tariffRepository.find({
      relations: ['rules', 'rules.route'],
      order: { createdAt: 'DESC' },
    });
  }

  async findById(tariffId: string): Promise<Tariff> {
    const tariff = await this.tariffRepository.findOne({
      where: { id: tariffId },
      relations: ['rules', 'rules.route'],
    });
    if (!tariff) {
      throw new DomainException(
        'Tariff not found',
        HttpStatus.NOT_FOUND,
        ErrorCode.TARIFF_NOT_FOUND,
      );
    }
    return tariff;
  }

  /**
   * The tariff that may price a new fare right now.
   *
   * A tariff is usable only when it is explicitly ACTIVE *and* its validity
   * window currently covers "now". Being inside the window is deliberately not
   * sufficient: publishing a schedule is a regulator decision.
   */
  async getActiveTariff(): Promise<Tariff> {
    const now = new Date();
    const tariff = await this.tariffRepository.findOne({
      where: [
        {
          status: TariffStatus.ACTIVE,
          validFrom: LessThanOrEqual(now),
          validTo: IsNull(),
        },
        {
          status: TariffStatus.ACTIVE,
          validFrom: LessThanOrEqual(now),
          validTo: MoreThanOrEqual(now),
        },
      ],
      order: {
        validFrom: 'DESC',
      },
      relations: ['rules', 'rules.route'],
    });

    if (!tariff) {
      throw new DomainException(
        'No active tariff found',
        HttpStatus.NOT_FOUND,
        ErrorCode.TARIFF_NOT_FOUND,
      );
    }
    return tariff;
  }

  /**
   * DRAFT → ACTIVE. Serialised by an advisory lock and backed by the
   * `UQ_tariffs_single_active` partial unique index, so at most one schedule can
   * ever be live even under concurrent admin requests.
   */
  async activate(tariffId: string): Promise<Tariff> {
    return this.dataSource.transaction(async (manager: EntityManager) => {
      await manager.query('SELECT pg_advisory_xact_lock($1)', [
        TARIFF_ACTIVATION_LOCK_KEY,
      ]);

      const tariff = await manager.findOne(Tariff, { where: { id: tariffId } });
      if (!tariff) {
        throw new DomainException(
          'Tariff not found',
          HttpStatus.NOT_FOUND,
          ErrorCode.TARIFF_NOT_FOUND,
        );
      }

      if (tariff.status !== TariffStatus.DRAFT) {
        throw new DomainException(
          `Only a DRAFT tariff can be activated (current status: ${tariff.status})`,
          HttpStatus.CONFLICT,
          ErrorCode.TARIFF_STATUS_INVALID,
        );
      }

      const now = new Date();
      if (tariff.validFrom > now || (tariff.validTo && tariff.validTo <= now)) {
        throw new DomainException(
          'Tariff can only be activated while its validity window covers the current time',
          HttpStatus.BAD_REQUEST,
          ErrorCode.TARIFF_WINDOW_INVALID,
        );
      }

      // Retire schedules whose window has already closed before checking for
      // conflicts — otherwise a long-ended ACTIVE row would block every future
      // activation forever.
      const actives = await manager.find(Tariff, {
        where: { status: TariffStatus.ACTIVE },
      });
      for (const active of actives) {
        if (active.validTo && active.validTo <= now) {
          active.status = TariffStatus.EXPIRED;
          await manager.save(active);
          continue;
        }

        // An incumbent that is still ACTIVE either genuinely overlaps this
        // window or is open-ended (which overlaps everything). Either way a
        // second live schedule is a conflict: the regulator must expire the
        // incumbent explicitly rather than have one silently replace it.
        const overlapping = this.windowsOverlap(active, tariff);
        throw new DomainException(
          overlapping
            ? `Tariff ${active.version} is already active over an overlapping window`
            : `Tariff ${active.version} is already active`,
          HttpStatus.CONFLICT,
          ErrorCode.TARIFF_WINDOW_OVERLAP,
        );
      }

      tariff.status = TariffStatus.ACTIVE;
      try {
        return await manager.save(tariff);
      } catch (err) {
        if (this.isUniqueViolation(err)) {
          throw new DomainException(
            'Another tariff is already active',
            HttpStatus.CONFLICT,
            ErrorCode.TARIFF_WINDOW_OVERLAP,
          );
        }
        throw err;
      }
    });
  }

  /**
   * DRAFT|ACTIVE → EXPIRED. Expiring is the explicit step that frees the single
   * ACTIVE slot for the next published version.
   */
  async expire(tariffId: string): Promise<Tariff> {
    const tariff = await this.findById(tariffId);

    if (
      tariff.status !== TariffStatus.ACTIVE &&
      tariff.status !== TariffStatus.DRAFT
    ) {
      throw new DomainException(
        `Only a DRAFT or ACTIVE tariff can be expired (current status: ${tariff.status})`,
        HttpStatus.CONFLICT,
        ErrorCode.TARIFF_STATUS_INVALID,
      );
    }

    tariff.status = TariffStatus.EXPIRED;
    return this.tariffRepository.save(tariff);
  }

  /** Two validity windows conflict when each starts before the other ends. */
  private windowsOverlap(a: Tariff, b: Tariff): boolean {
    const aEnd = a.validTo ?? new Date(8640000000000000);
    const bEnd = b.validTo ?? new Date(8640000000000000);
    return a.validFrom < bEnd && b.validFrom < aEnd;
  }

  private isUniqueViolation(err: unknown): boolean {
    return (
      typeof err === 'object' &&
      err !== null &&
      (err as { code?: string }).code === '23505'
    );
  }
}
