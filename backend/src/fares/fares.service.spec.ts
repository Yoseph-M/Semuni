import { Test, TestingModule } from '@nestjs/testing';
import { FaresService } from './fares.service';
import { TariffsService } from '../tariffs/tariffs.service';
import { RoutesService } from '../routes/routes.service';
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

  const minibusRule = {
    id: '66666666-6666-4666-8666-666666666666',
    route: { id: route.id },
    vehicleType: VehicleType.MINIBUS,
    startStopSequence: 1,
    endStopSequence: 3,
    basePrice: 8500,
  };

  const tariff = {
    id: '55555555-5555-4555-8555-555555555555',
    version: 'TARIFF-2026-001',
    name: 'Standard Tariff',
    currency: 'ETB',
    rules: [minibusRule],
  };

  const fareFor = (originIndex = 0, destinationIndex = 2) =>
    service.calculateFare({
      routeId: route.id,
      originStopId: route.stops[originIndex].id,
      destinationStopId: route.stops[destinationIndex].id,
      vehicleType: VehicleType.MINIBUS,
    });

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
    await expect(fareFor()).resolves.toMatchObject({
      fare: 8500,
      routeId: route.id,
      originStopId: route.stops[0].id,
      destinationStopId: route.stops[2].id,
      tariffRuleId: minibusRule.id,
    });
  });

  it('stamps the tariff version identifier, not its descriptive name', async () => {
    await expect(fareFor()).resolves.toMatchObject({
      tariffId: tariff.id,
      tariffVersion: 'TARIFF-2026-001',
    });
  });

  it('returns server-derived stop names for the trip snapshot', async () => {
    await expect(fareFor()).resolves.toMatchObject({
      routeName: 'Bole – Piazza',
      originStopName: 'Bole',
      destinationStopName: 'Piazza',
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

    await expect(fareFor()).rejects.toHaveProperty(
      'response.code',
      ErrorCode.ROUTE_INACTIVE,
    );
  });

  it('rejects a tariff rule for a different route', async () => {
    tariffsService.getActiveTariff.mockResolvedValue({
      ...tariff,
      rules: [
        { ...minibusRule, route: { id: '88888888-8888-4888-8888-888888888888' } },
      ],
    });

    await expect(fareFor()).rejects.toHaveProperty(
      'response.code',
      ErrorCode.TARIFF_RULE_NOT_FOUND,
    );
  });

  it('propagates the failure when no tariff is active', async () => {
    // DRAFT/EXPIRED tariffs never reach the engine because the active-tariff
    // lookup only ever returns an explicitly ACTIVE schedule.
    tariffsService.getActiveTariff.mockRejectedValue(
      Object.assign(new Error('No active tariff found'), {
        response: { code: ErrorCode.TARIFF_NOT_FOUND },
      }),
    );

    await expect(fareFor()).rejects.toHaveProperty(
      'response.code',
      ErrorCode.TARIFF_NOT_FOUND,
    );
  });

  it('rejects a journey no rule covers', async () => {
    tariffsService.getActiveTariff.mockResolvedValue({
      ...tariff,
      rules: [{ ...minibusRule, startStopSequence: 1, endStopSequence: 1 }],
    });

    await expect(fareFor()).rejects.toHaveProperty(
      'response.code',
      ErrorCode.TARIFF_RULE_NOT_FOUND,
    );
  });

  describe('deterministic precedence', () => {
    const genericRule = {
      id: '99999999-9999-4999-8999-999999999999',
      route: { id: route.id },
      vehicleType: null,
      startStopSequence: 1,
      endStopSequence: 3,
      basePrice: 9000,
    };

    it('prefers a rule naming the requested vehicle type over a generic rule', async () => {
      tariffsService.getActiveTariff.mockResolvedValue({
        ...tariff,
        rules: [genericRule, minibusRule],
      });

      await expect(fareFor()).resolves.toMatchObject({
        fare: 8500,
        tariffRuleId: minibusRule.id,
      });
    });

    it('prefers a generic rule when the caller did not state a vehicle type', async () => {
      tariffsService.getActiveTariff.mockResolvedValue({
        ...tariff,
        rules: [genericRule, minibusRule],
      });

      await expect(
        service.calculateFare({
          routeId: route.id,
          originStopId: route.stops[0].id,
          destinationStopId: route.stops[2].id,
        }),
      ).resolves.toMatchObject({ fare: 9000, tariffRuleId: genericRule.id });
    });

    it('prefers the narrower stop range over a broader one', async () => {
      const shortHopRule = {
        ...genericRule,
        id: 'aaaaaaaa-aaaa-4aaa-8aaa-aaaaaaaaaaaa',
        startStopSequence: 1,
        endStopSequence: 2,
        basePrice: 4000,
      };
      tariffsService.getActiveTariff.mockResolvedValue({
        ...tariff,
        rules: [genericRule, shortHopRule],
      });

      await expect(fareFor(0, 1)).resolves.toMatchObject({
        fare: 4000,
        tariffRuleId: shortHopRule.id,
      });
      // The broad rule still prices the full journey.
      await expect(fareFor(0, 2)).resolves.toMatchObject({ fare: 9000 });
    });

    it('applies an open-ended generic rule to any stop pair on its route', async () => {
      tariffsService.getActiveTariff.mockResolvedValue({
        ...tariff,
        rules: [
          {
            ...genericRule,
            startStopSequence: null,
            endStopSequence: null,
            basePrice: 3000,
          },
        ],
      });

      await expect(fareFor(0, 1)).resolves.toMatchObject({ fare: 3000 });
      await expect(fareFor(1, 2)).resolves.toMatchObject({ fare: 3000 });
    });

    it('rejects equally-applicable rules instead of guessing', async () => {
      tariffsService.getActiveTariff.mockResolvedValue({
        ...tariff,
        rules: [minibusRule, { ...minibusRule, id: 'bbbbbbbb-bbbb-4bbb-8bbb-bbbbbbbbbbbb' }],
      });

      await expect(fareFor()).rejects.toHaveProperty(
        'response.code',
        ErrorCode.TARIFF_RULE_AMBIGUOUS,
      );
    });

    it('does not treat different-width matches as ambiguous', async () => {
      tariffsService.getActiveTariff.mockResolvedValue({
        ...tariff,
        rules: [
          minibusRule,
          { ...minibusRule, id: 'cccccccc-cccc-4ccc-8ccc-cccccccccccc', endStopSequence: 2, basePrice: 4000 },
        ],
      });

      await expect(fareFor(0, 1)).resolves.toMatchObject({ fare: 4000 });
    });
  });
});
