import { Injectable, HttpStatus } from '@nestjs/common';
import { InjectRepository } from '@nestjs/typeorm';
import { Repository, LessThanOrEqual, IsNull, MoreThanOrEqual } from 'typeorm';
import { Tariff } from './entities/tariff.entity';
import { CreateTariffDto } from './dto/tariff.dto';
import { RoutesService } from '../routes/routes.service';
import { DomainException } from '../common/domain.exception';
import { ErrorCode } from '../common/error-codes';
import { RouteStatus } from '../common/enums';

@Injectable()
export class TariffsService {
  constructor(
    @InjectRepository(Tariff)
    private readonly tariffRepository: Repository<Tariff>,
    private readonly routesService: RoutesService,
  ) {}

  async create(dto: CreateTariffDto): Promise<Tariff> {
    if (dto.rules.length === 0) {
      throw new DomainException(
        'A tariff must contain at least one rule',
        HttpStatus.BAD_REQUEST,
        ErrorCode.TARIFF_RULE_NOT_FOUND,
      );
    }

    const validFrom = new Date(dto.validFrom);
    const validTo = dto.validTo ? new Date(dto.validTo) : undefined;
    if (validTo && validTo <= validFrom) {
      throw new DomainException(
        'Tariff validTo must be after validFrom',
        HttpStatus.BAD_REQUEST,
        ErrorCode.VALIDATION_ERROR,
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

      if (rule.basePrice <= 0 || !Number.isInteger(rule.basePrice)) {
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
      name: dto.name,
      validFrom,
      validTo,
      currency: dto.currency,
      rules: dto.rules.map(rule => ({
        route: { id: rule.routeId },
        vehicleType: rule.vehicleType,
        startStopSequence: rule.startStopSequence,
        endStopSequence: rule.endStopSequence,
        basePrice: rule.basePrice,
      })),
    });

    return this.tariffRepository.save(tariff);
  }

  async findAll(): Promise<Tariff[]> {
    return this.tariffRepository.find({ relations: ['rules', 'rules.route'] });
  }

  async getActiveTariff(): Promise<Tariff> {
    const now = new Date();
    const tariff = await this.tariffRepository.findOne({
      where: [
        {
          validFrom: LessThanOrEqual(now),
          validTo: IsNull(),
        },
        {
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
}
