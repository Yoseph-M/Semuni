import { Test, TestingModule } from '@nestjs/testing';
import { FaresService } from './fares.service';
import { TariffsService } from '../tariffs/tariffs.service';
import { RoutesService } from '../routes/routes.service';
import { getRepositoryToken } from '@nestjs/typeorm';
import { Route } from '../routes/entities/route.entity';
import { Tariff } from '../tariffs/entities/tariff.entity';
import { TariffRule } from '../tariffs/entities/tariff-rule.entity';
import { DomainException } from '../common/domain.exception';
import { ErrorCode } from '../common/error-codes';
import { VehicleType } from '../common/enums';

describe('FaresService', () => {
  let service: FaresService;
  let tariffsService: TariffsService;

  const mockTariffRepository = {};
  const mockTariffRuleRepository = {};
  const mockRouteRepository = {};

  beforeEach(async () => {
    const module: TestingModule = await Test.createTestingModule({
      providers: [
        FaresService,
        TariffsService,
        RoutesService,
        {
          provide: getRepositoryToken(Route),
          useValue: mockRouteRepository,
        },
        {
          provide: getRepositoryToken(Tariff),
          useValue: mockTariffRepository,
        },
        {
          provide: getRepositoryToken(TariffRule),
          useValue: mockTariffRuleRepository,
        },
      ],
    }).compile();

    service = module.get<FaresService>(FaresService);
    tariffsService = module.get<TariffsService>(TariffsService);
  });

  it('should be defined', () => {
    expect(service).toBeDefined();
  });

  describe('calculateFare', () => {
    const mockRoute = {
      id: 'route-1',
      name: 'Bole to Piazza',
      origin: 'Bole',
      destination: 'Piazza',
      code: 'BP001',
      status: 'ACTIVE',
      createdAt: new Date(),
      updatedAt: new Date(),
      stops: [],
    };

    const mockTariffRule = {
      id: 'rule-1',
      tariffId: 'tariff-1',
      routeId: 'route-1',
      // TariffsService loads `rules.route`; FaresService matches on it.
      route: mockRoute,
      basePrice: 8500,
      vehicleType: VehicleType.MINIBUS,
      createdAt: new Date(),
      updatedAt: new Date(),
    };

    const mockTariff = {
      id: 'tariff-1',
      name: 'Standard Tariff',
      validFrom: new Date('2023-01-01'),
      validTo: null,
      currency: 'ETB',
      rules: [mockTariffRule],
      createdAt: new Date(),
      updatedAt: new Date(),
    };

    beforeEach(() => {
      jest.spyOn(service as any, 'findRouteByOriginDestination').mockResolvedValue(mockRoute);
      jest.spyOn(tariffsService, 'getActiveTariff').mockResolvedValue(mockTariff as any);
    });

    it('should calculate fare for a given origin, destination and vehicle type', async () => {
      const dto = {
        origin: 'Bole',
        destination: 'Piazza',
        vehicleType: VehicleType.MINIBUS,
      };

      const result = await service.calculateFare(dto);
      expect(result).toEqual({
        fare: 8500,
        currency: 'ETB',
        routeId: 'route-1',
        routeName: 'Bole to Piazza',
        tariffId: 'tariff-1',
        tariffRuleId: 'rule-1',
        tariffVersion: 'Standard Tariff',
      });
    });

    it('should throw error if route not found', async () => {
      jest.spyOn(service as any, 'findRouteByOriginDestination').mockResolvedValue(null);
      const dto = {
        origin: 'Unknown',
        destination: 'Place',
        vehicleType: VehicleType.MINIBUS,
      };
      await expect(service.calculateFare(dto)).rejects.toThrow(DomainException);
      await expect(service.calculateFare(dto)).rejects.toHaveProperty(
        'response.code', ErrorCode.ROUTE_NOT_FOUND,
      );
    });

    it('should throw error if active tariff not found', async () => {
      jest
        .spyOn(tariffsService, 'getActiveTariff')
        .mockResolvedValue(null as unknown as Tariff);
      const dto = {
        origin: 'Bole',
        destination: 'Piazza',
        vehicleType: VehicleType.MINIBUS,
      };
      await expect(service.calculateFare(dto)).rejects.toThrow(DomainException);
      await expect(service.calculateFare(dto)).rejects.toHaveProperty(
        'response.code', ErrorCode.TARIFF_NOT_FOUND,
      );
    });

    it('should throw error if tariff rule not found for route and vehicle type', async () => {
      const tariffWithNoMatchingRule = { ...mockTariff, rules: [] };
      jest.spyOn(tariffsService, 'getActiveTariff').mockResolvedValue(tariffWithNoMatchingRule as any);
      const dto = {
        origin: 'Bole',
        destination: 'Piazza',
        vehicleType: VehicleType.MINIBUS,
      };
      await expect(service.calculateFare(dto)).rejects.toThrow(DomainException);
      await expect(service.calculateFare(dto)).rejects.toHaveProperty(
        'response.code', ErrorCode.TARIFF_RULE_NOT_FOUND,
      );
    });
  });
});
