import { Injectable, HttpStatus } from '@nestjs/common';
import { CalculateFareDto } from './dto/fare.dto';
import { TariffsService } from '../tariffs/tariffs.service';
import { RoutesService } from '../routes/routes.service';
import { TariffRule } from '../tariffs/entities/tariff-rule.entity';
import { DomainException } from '../common/domain.exception';
import { ErrorCode } from '../common/error-codes';
import { Currency, RouteStatus, VehicleType } from '../common/enums';

/** Sentinel bounds for rules with an open-ended stop range. */
const LOWEST_SEQUENCE = Number.MIN_SAFE_INTEGER;
const HIGHEST_SEQUENCE = Number.MAX_SAFE_INTEGER;

interface RankedRule {
  rule: TariffRule;
  /** 2 = matches the requested vehicle type, 1 = generic, 0 = unrelated type. */
  vehicleSpecificity: number;
  /** How many sequence positions the rule's range spans. */
  width: number;
}

@Injectable()
export class FaresService {
  constructor(
    private readonly tariffsService: TariffsService,
    private readonly routesService: RoutesService,
  ) {}

  /**
   * Prices a journey from authoritative identifiers only.
   *
   * The route and both stops come from the database (never from client text),
   * the tariff must be the explicitly ACTIVE one, and rule selection is a total
   * order. If two rules are genuinely equally applicable the request is rejected
   * rather than resolved arbitrarily — a fare must never depend on row order.
   */
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

    const candidates: RankedRule[] = (tariff.rules ?? [])
      .filter((rule) =>
        this.ruleContainsSegment(rule, dto, originStop.sequence, destinationStop.sequence),
      )
      .map((rule) => ({
        rule,
        vehicleSpecificity: this.vehicleSpecificity(rule, dto.vehicleType),
        width:
          (rule.endStopSequence ?? HIGHEST_SEQUENCE) -
          (rule.startStopSequence ?? LOWEST_SEQUENCE),
      }));

    if (candidates.length === 0) {
      throw new DomainException(
        'No tariff rule found for this route and stop pair',
        HttpStatus.NOT_FOUND,
        ErrorCode.TARIFF_RULE_NOT_FOUND,
      );
    }

    // Deterministic precedence (specific beats generic, then narrower beats
    // broader). Any remaining tie means the pricing configuration itself is
    // ambiguous, which is rejected instead of being resolved by chance.
    candidates.sort((a, b) => {
      if (a.vehicleSpecificity !== b.vehicleSpecificity) {
        return b.vehicleSpecificity - a.vehicleSpecificity;
      }
      if (a.width !== b.width) {
        return a.width - b.width;
      }
      return 0;
    });

    const best = candidates[0];
    const tied = candidates.filter(
      (candidate) =>
        candidate !== best &&
        candidate.vehicleSpecificity === best.vehicleSpecificity &&
        candidate.width === best.width,
    );
    if (tied.length > 0) {
      throw new DomainException(
        `Multiple tariff rules match this journey equally well (rule ${best.rule.id} and ${tied
          .map((candidate) => candidate.rule.id)
          .join(', ')}); the pricing configuration is ambiguous`,
        HttpStatus.CONFLICT,
        ErrorCode.TARIFF_RULE_AMBIGUOUS,
      );
    }

    const rule = best.rule;

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
      // The version label — not the descriptive name — identifies the schedule
      // that priced this fare, and is what the trip snapshot preserves.
      tariffVersion: tariff.version,
      tariffRuleId: rule.id,
    };
  }

  /**
   * A rule applies when it is scoped to this route, its stop range contains the
   * requested segment in the travel direction, and its vehicle scope is
   * compatible.
   */
  private ruleContainsSegment(
    rule: TariffRule,
    dto: CalculateFareDto,
    originSequence: number,
    destinationSequence: number,
  ): boolean {
    if (rule.route?.id !== dto.routeId) return false;

    if (
      rule.vehicleType != null &&
      dto.vehicleType != null &&
      rule.vehicleType !== dto.vehicleType
    ) {
      return false;
    }

    const start = rule.startStopSequence ?? LOWEST_SEQUENCE;
    const end = rule.endStopSequence ?? HIGHEST_SEQUENCE;

    return (
      originSequence >= start &&
      destinationSequence <= end &&
      originSequence < destinationSequence
    );
  }

  /**
   * Ranks how well a rule speaks to the requested vehicle type.
   *
   *   2 — the rule names exactly the requested type
   *   1 — the rule is generic and applies to any type
   *   0 — the rule names another type (only reachable when the caller did not
   *       state a vehicle type), so a generic rule is always preferred over a
   *       price intended for a different vehicle.
   */
  private vehicleSpecificity(
    rule: TariffRule,
    requested?: VehicleType,
  ): number {
    if (requested != null && rule.vehicleType === requested) return 2;
    if (rule.vehicleType == null) return 1;
    return 0;
  }
}
