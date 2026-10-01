import { Injectable, HttpStatus } from '@nestjs/common';
import { CalculateFareDto } from './dto/fare.dto';
import { TariffsService } from '../tariffs/tariffs.service';
import { RoutesService } from '../routes/routes.service';
import { DomainException } from '../common/domain.exception';
import { ErrorCode } from '../common/error-codes';
import { Currency, RouteStatus } from '../common/enums';

@Injectable()
export class FaresService {
  constructor(
    private readonly tariffsService: TariffsService,
    private readonly routesService: RoutesService,
  ) {}

  async calculateFare(dto: CalculateFareDto) {
    const route = await this.routesService.findById(dto.routeId, {
      requireActive: true,
    });

    const originStop = route.stops.find((stop) => stop.id === dto.originStopId);
    const destinationStop = route.stops.find(
      (stop) => stop.id === dto.destinationStopId,
    );

    if (!originStop || !destinationStop) {
      throw new DomainException(
        'Origin and destination stops must belong to the selected route',
        HttpStatus.BAD_REQUEST,
        ErrorCode.STOP_NOT_FOUND,
      );
    }

    if (route.status !== RouteStatus.ACTIVE) {
      throw new DomainException(
        'Route is not active',
        HttpStatus.BAD_REQUEST,
        ErrorCode.ROUTE_INACTIVE,
      );
    }

    if (originStop.sequence >= destinationStop.sequence) {
      throw new DomainException(
        'Destination stop must occur after origin stop on the route',
        HttpStatus.BAD_REQUEST,
        ErrorCode.STOP_ORDER_INVALID,
      );
    }

    const tariff = await this.tariffsService.getActiveTariff();

    const candidates = (tariff.rules ?? []).filter((rule) => {
      if (rule.route?.id !== route.id) return false;

      const vehicleTypeMatches =
        rule.vehicleType == null ||
        dto.vehicleType == null ||
        rule.vehicleType === dto.vehicleType;
      if (!vehicleTypeMatches) return false;

      const start = rule.startStopSequence ?? Number.MIN_SAFE_INTEGER;
      const end = rule.endStopSequence ?? Number.MAX_SAFE_INTEGER;

      return (
        originStop.sequence >= start &&
        destinationStop.sequence <= end &&
        originStop.sequence < destinationStop.sequence
      );
    });

    if (candidates.length === 0) {
      throw new DomainException(
        'No tariff rule found for this route and stop pair',
        HttpStatus.NOT_FOUND,
        ErrorCode.TARIFF_RULE_NOT_FOUND,
      );
    }

    // Prefer the narrowest matching stop range, then a vehicle-specific rule
    // over a generic rule. This makes overlapping tariff rules deterministic.
    candidates.sort((a, b) => {
      const aWidth =
        (a.endStopSequence ?? Number.MAX_SAFE_INTEGER) -
        (a.startStopSequence ?? Number.MIN_SAFE_INTEGER);
      const bWidth =
        (b.endStopSequence ?? Number.MAX_SAFE_INTEGER) -
        (b.startStopSequence ?? Number.MIN_SAFE_INTEGER);
      if (aWidth !== bWidth) return aWidth - bWidth;

      const aSpecific = a.vehicleType != null ? 1 : 0;
      const bSpecific = b.vehicleType != null ? 1 : 0;
      return bSpecific - aSpecific;
    });

    const rule = candidates[0];

    return {
      fare: rule.basePrice,
      currency: tariff.currency as Currency,
      routeId: route.id,
      routeName: route.name,
      originStopId: originStop.id,
      originStopName: originStop.name,
      destinationStopId: destinationStop.id,
      destinationStopName: destinationStop.name,
      tariffId: tariff.id,
      tariffRuleId: rule.id,
      tariffVersion: tariff.name,
    };
  }
}
