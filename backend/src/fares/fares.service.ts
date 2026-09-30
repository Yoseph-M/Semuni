import { Injectable, HttpStatus } from '@nestjs/common';
import { InjectRepository } from '@nestjs/typeorm';
import { Repository, ILike } from 'typeorm';
import { CalculateFareDto } from './dto/fare.dto';
import { TariffsService } from '../tariffs/tariffs.service';
import { RoutesService } from '../routes/routes.service';
import { Route } from '../routes/entities/route.entity';
import { DomainException } from '../common/domain.exception';
import { ErrorCode } from '../common/error-codes';
import { Currency } from '../common/enums';

@Injectable()
export class FaresService {
  constructor(
    private readonly tariffsService: TariffsService,
    private readonly routesService: RoutesService,
    @InjectRepository(Route)
    private readonly routeRepository: Repository<Route>,
  ) {}

  async calculateFare(dto: CalculateFareDto) {
    const route = await this.findRouteByOriginDestination(
      dto.origin,
      dto.destination,
    );

    if (!route) {
      throw new DomainException(
        `No route found from ${dto.origin} to ${dto.destination}`,
        HttpStatus.NOT_FOUND,
        ErrorCode.ROUTE_NOT_FOUND,
      );
    }

    // TariffsService throws when no tariff is active, but guard anyway so a
    // misconfiguration surfaces as a domain error rather than a 500.
    const tariff = await this.tariffsService.getActiveTariff();
    if (!tariff) {
      throw new DomainException(
        'No active tariff found',
        HttpStatus.NOT_FOUND,
        ErrorCode.TARIFF_NOT_FOUND,
      );
    }

    // A tariff with no matching rule is TARIFF_RULE_NOT_FOUND, not a missing tariff.
    const rule = (tariff.rules ?? []).find((r) => {
      // Match by route ID. A rule whose route relation was not loaded can never
      // be verified, so it is skipped rather than trusted.
      if (r.route?.id !== route.id) return false;

      // Match by vehicle type: if DTO specifies vehicleType, find rule that matches it or is general.
      // If DTO does not specify vehicleType, find rule that is general (has no specific vehicleType).
      const vehicleTypeMatches = !dto.vehicleType || !r.vehicleType || r.vehicleType === dto.vehicleType;

      return vehicleTypeMatches;
    });

    if (!rule) {
      throw new DomainException(
        'No tariff rule found for this route',
        HttpStatus.NOT_FOUND,
        ErrorCode.TARIFF_RULE_NOT_FOUND,
      );
    }

    return {
      fare: rule.basePrice,
      currency: tariff.currency as Currency,
      routeId: route.id,
      routeName: route.name,
      tariffId: tariff.id,
      tariffRuleId: rule.id,
      tariffVersion: tariff.name,
    };
  }

  private async findRouteByOriginDestination(
    origin: string,
    destination: string,
  ): Promise<Route> {
    const route = await this.routeRepository.findOne({
      where: {
        origin: ILike(origin.trim()),
        destination: ILike(destination.trim()),
      },
      relations: ['stops'],
    });

    if (route) return route;

    const stopsOrigin = await this.routeRepository
      .createQueryBuilder('route')
      .innerJoinAndSelect('route.stops', 'originStop', 'originStop.name ILIKE :origin', { origin: origin.trim() })
      .innerJoinAndSelect('route.stops', 'destStop', 'destStop.name ILIKE :dest AND destStop.sequence > originStop.sequence', { dest: destination.trim() })
      .getOne();

    if (stopsOrigin) return stopsOrigin;

    const anyMatch = await this.routeRepository
      .createQueryBuilder('route')
      .leftJoinAndSelect('route.stops', 'stop')
      .where('route.origin ILIKE :origin OR route.destination ILIKE :dest', {
        origin: `%${origin.trim()}%`,
        dest: `%${destination.trim()}%`,
      })
      .getOne();

    if (anyMatch) return anyMatch;

    throw new DomainException(
      `No route found from ${origin} to ${destination}`,
      HttpStatus.NOT_FOUND,
      ErrorCode.ROUTE_NOT_FOUND,
    );
  }
}
