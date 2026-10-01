import { Test, TestingModule } from '@nestjs/testing';
import { FaresService } from './fares.service';
import { TariffsService } from '../tariffs/tariffs.service';
import { RoutesService } from '../routes/routes.service';
import { DomainException } from '../common/domain.exception';
import { ErrorCode } from '../common/error-codes';
import { VehicleType, RouteStatus } from '../common/enums';

describe('FaresService', () => {
  let service: FaresService;
  let tariffsService: { getActiveTariff: jest.Mock };
  let routesService: { findById: jest.Mock };

  const route = {
    id: '11111111-1111-4111-8111-111111111111',
    name: 'Bole – Piazza',
    status: RouteStatus.ACTIVE,
    stops: [
      {
        id: '22222222-2222-4222-8222-222222222222',
        name: 'Bole',
        sequence: 1,
      },
      {
        id: '33333333-3333-4333-8333-333333333333',
        name: 'Meskel Square',
        sequence: 2,
      },
      {
        id: '44444444-4444-4444-8444-444444444444',
        name: 'Piazza',
        sequence: 3,
      },
    ],
  };

  const tariff = {
    id: '55555555-5555-4555-8555-555555555555',
    name: 'Standard Tariff',
    currency: 'ETB',
    rules: [
      {
        id: '66666666-6666-4666-8666-666666666666',
        route: { id: route.id },
        vehicleType: VehicleType.MINIBUS,
        startStopSequence: 1,
        endStopSequence: 3,
        basePrice: 8500,
      },
    ],
  };

  beforeEach(async () => {
    routesService = { findById: jest.fn().mockResolvedValue(route) };
    tariffsService = { getActiveTariff: jest.fn().mockResolvedValue(tariff) };

    const module: TestingModule = await Test.createTestingModule({
      providers: [
        FaresService,
        { provide: TariffsService, useValue: tariffsService },
        { provide: RoutesService, useValue: routesService },
      ],
    }).compile();

    service = module.get<FaresService>(FaresService);
  });

  it('calculates a fare only from route and ordered stop IDs', async () => {
    await expect(
      service.calculateFare({
        routeId: route.id,
        originStopId: route.stops[0].id,
        destinationStopId: route.stops[2].id,
        vehicleType: VehicleType.MINIBUS,
      }),
    ).resolves.toMatchObject({
      fare: 8500,
      routeId: route.id,
      originStopId: route.stops[0].id,
      destinationStopId: route.stops[2].id,
      tariffRuleId: tariff.rules[0].id,
    });
  });

  it('rejects a stop that does not belong to the route', async () => {
    await expect(
      service.calculateFare({
        routeId: route.id,
        originStopId: '77777777-7777-4777-8777-777777777777',
        destinationStopId: route.stops[2].id,
      }),
    ).rejects.toHaveProperty('response.code', ErrorCode.STOP_NOT_FOUND);
  });

  it('rejects reverse-direction travel', async () => {
    await expect(
      service.calculateFare({
        routeId: route.id,
        originStopId: route.stops[2].id,
        destinationStopId: route.stops[0].id,
      }),
    ).rejects.toHaveProperty('response.code', ErrorCode.STOP_ORDER_INVALID);
  });

  it('rejects an inactive route', async () => {
    routesService.findById.mockResolvedValue({
      ...route,
      status: RouteStatus.INACTIVE,
    });

    await expect(
      service.calculateFare({
        routeId: route.id,
        originStopId: route.stops[0].id,
        destinationStopId: route.stops[2].id,
      }),
    ).rejects.toHaveProperty('response.code', ErrorCode.ROUTE_INACTIVE);
  });

  it('rejects a tariff rule for a different route', async () => {
    tariffsService.getActiveTariff.mockResolvedValue({
      ...tariff,
      rules: [{ ...tariff.rules[0], route: { id: '88888888-8888-4888-8888-888888888888' } }],
    });

    await expect(
      service.calculateFare({
        routeId: route.id,
        originStopId: route.stops[0].id,
        destinationStopId: route.stops[2].id,
      }),
    ).rejects.toHaveProperty('response.code', ErrorCode.TARIFF_RULE_NOT_FOUND);
  });
});
