import { Test, TestingModule } from '@nestjs/testing';
import { getRepositoryToken } from '@nestjs/typeorm';
import { DataSource } from 'typeorm';
import { TariffsService } from './tariffs.service';
import { Tariff } from './entities/tariff.entity';
import { RoutesService } from '../routes/routes.service';
import { ErrorCode } from '../common/error-codes';
import {
  CreateTariffDto,
  CreateTariffRuleDto,
} from './dto/tariff.dto';
import {
  Currency,
  RouteStatus,
  TariffStatus,
  VehicleType,
} from '../common/enums';

describe('TariffsService', () => {
  let service: TariffsService;
  let tariffRepository: {
    findOne: jest.Mock;
    find: jest.Mock;
    create: jest.Mock;
    save: jest.Mock;
  };
  let routesService: { findById: jest.Mock };
  let manager: {
    query: jest.Mock;
    findOne: jest.Mock;
    find: jest.Mock;
    save: jest.Mock;
  };
  let dataSource: { transaction: jest.Mock };

  const ROUTE_ID = '11111111-1111-4111-8111-111111111111';

  const route = {
    id: ROUTE_ID,
    code: 'RT-1',
    name: 'Bole – Piazza',
    status: RouteStatus.ACTIVE,
    stops: [
      { id: '22222222-2222-4222-8222-222222222222', name: 'Bole', sequence: 1 },
      { id: '33333333-3333-4333-8333-333333333333', name: 'Meskel', sequence: 2 },
      { id: '44444444-4444-4444-8444-444444444444', name: 'Piazza', sequence: 3 },
    ],
  };

  const rule: CreateTariffRuleDto = {
    routeId: ROUTE_ID,
    vehicleType: VehicleType.MINIBUS,
    startStopSequence: 1,
    endStopSequence: 3,
    basePrice: 8500,
  };

  const validDto = (overrides: Partial<CreateTariffDto> = {}): CreateTariffDto => ({
    version: 'TARIFF-2026-001',
    name: 'Regulator Schedule 2026-001',
    validFrom: new Date(Date.now() - 60_000).toISOString(),
    currency: Currency.ETB,
    rules: [{ ...rule }],
    ...overrides,
  });

  beforeEach(async () => {
    tariffRepository = {
      findOne: jest.fn().mockResolvedValue(null),
      find: jest.fn().mockResolvedValue([]),
      create: jest.fn((value) => value),
      save: jest.fn(async (value) => ({ id: 'tariff-id', ...value })),
    };
    routesService = { findById: jest.fn().mockResolvedValue(route) };
    manager = {
      query: jest.fn().mockResolvedValue(undefined),
      findOne: jest.fn(),
      find: jest.fn().mockResolvedValue([]),
      save: jest.fn(async (value) => value),
    };
    dataSource = {
      transaction: jest.fn(async (cb: (m: unknown) => unknown) => cb(manager)),
    };

    const module: TestingModule = await Test.createTestingModule({
      providers: [
        TariffsService,
        { provide: getRepositoryToken(Tariff), useValue: tariffRepository },
        { provide: RoutesService, useValue: routesService },
        { provide: DataSource, useValue: dataSource },
      ],
    }).compile();

    service = module.get<TariffsService>(TariffsService);
  });

  describe('create', () => {
    it('always starts a new tariff in DRAFT, never live', async () => {
      await service.create(validDto());

      expect(tariffRepository.create).toHaveBeenCalledWith(
        expect.objectContaining({
          version: 'TARIFF-2026-001',
          status: TariffStatus.DRAFT,
        }),
      );
    });

    it('rejects a version that already exists', async () => {
      tariffRepository.findOne.mockResolvedValue({ id: 'existing' });

      await expect(service.create(validDto())).rejects.toMatchObject({
        response: { code: ErrorCode.TARIFF_VERSION_EXISTS },
        status: 409,
      });
    });

    it('maps a concurrent unique violation to the same conflict error', async () => {
      tariffRepository.save.mockRejectedValue({ code: '23505' });

      await expect(service.create(validDto())).rejects.toMatchObject({
        response: { code: ErrorCode.TARIFF_VERSION_EXISTS },
      });
    });

    it('rejects an empty rule set', async () => {
      await expect(
        service.create(validDto({ rules: [] })),
      ).rejects.toMatchObject({
        response: { code: ErrorCode.TARIFF_RULE_NOT_FOUND },
      });
    });

    it('rejects validTo not after validFrom', async () => {
      const now = new Date().toISOString();

      await expect(
        service.create(validDto({ validFrom: now, validTo: now })),
      ).rejects.toMatchObject({
        response: { code: ErrorCode.TARIFF_WINDOW_INVALID },
      });
    });

    it('rejects a non-integer or non-positive basePrice', async () => {
      for (const basePrice of [0, -100, 12.5]) {
        await expect(
          service.create(validDto({ rules: [{ ...rule, basePrice }] })),
        ).rejects.toMatchObject({
          response: { code: ErrorCode.VALIDATION_ERROR },
        });
      }
    });

    it('rejects an impossible stop range', async () => {
      await expect(
        service.create(
          validDto({
            rules: [{ ...rule, startStopSequence: 3, endStopSequence: 1 }],
          }),
        ),
      ).rejects.toMatchObject({
        response: { code: ErrorCode.STOP_ORDER_INVALID },
      });
    });

    it('rejects a stop range that references a sequence the route lacks', async () => {
      await expect(
        service.create(
          validDto({
            rules: [{ ...rule, startStopSequence: 1, endStopSequence: 9 }],
          }),
        ),
      ).rejects.toMatchObject({
        response: { code: ErrorCode.STOP_NOT_FOUND },
      });
    });

    it('rejects a rule for an inactive route', async () => {
      routesService.findById.mockResolvedValue({
        ...route,
        status: RouteStatus.INACTIVE,
      });

      await expect(service.create(validDto())).rejects.toMatchObject({
        response: { code: ErrorCode.ROUTE_INACTIVE },
      });
    });

    it('rejects a rule for a route that does not exist', async () => {
      routesService.findById.mockRejectedValue(
        Object.assign(new Error('Route not found'), {
          response: { code: ErrorCode.ROUTE_NOT_FOUND },
        }),
      );

      await expect(service.create(validDto())).rejects.toMatchObject({
        response: { code: ErrorCode.ROUTE_NOT_FOUND },
      });
    });
  });

  describe('getActiveTariff', () => {
    it('finds only an ACTIVE tariff whose window covers now', async () => {
      tariffRepository.findOne.mockResolvedValue({
        id: 'a',
        status: TariffStatus.ACTIVE,
      });

      await service.getActiveTariff();

      const where = tariffRepository.findOne.mock.calls[0][0].where;
      expect(where).toEqual(
        expect.arrayContaining([
          expect.objectContaining({ status: TariffStatus.ACTIVE }),
        ]),
      );
    });

    it('reports TARIFF_NOT_FOUND when nothing is active', async () => {
      tariffRepository.findOne.mockResolvedValue(null);

      await expect(service.getActiveTariff()).rejects.toMatchObject({
        response: { code: ErrorCode.TARIFF_NOT_FOUND },
        status: 404,
      });
    });
  });

  describe('activate', () => {
    const draft = (overrides: Partial<Tariff> = {}) =>
      ({
        id: 'tariff-draft',
        version: 'TARIFF-2026-002',
        status: TariffStatus.DRAFT,
        validFrom: new Date(Date.now() - 60_000),
        validTo: undefined,
        ...overrides,
      }) as Tariff;

    it('promotes a DRAFT tariff that is inside its validity window', async () => {
      manager.findOne.mockResolvedValue(draft());

      await expect(service.activate('tariff-draft')).resolves.toMatchObject({
        status: TariffStatus.ACTIVE,
      });
      // Activation is serialised so two admins cannot both win the race.
      expect(manager.query).toHaveBeenCalledWith(
        expect.stringContaining('pg_advisory_xact_lock'),
        expect.any(Array),
      );
    });

    it('refuses to activate anything that is not a DRAFT', async () => {
      for (const status of [TariffStatus.ACTIVE, TariffStatus.EXPIRED]) {
        manager.findOne.mockResolvedValue(draft({ status }));

        await expect(service.activate('tariff-draft')).rejects.toMatchObject({
          response: { code: ErrorCode.TARIFF_STATUS_INVALID },
          status: 409,
        });
      }
    });

    it('refuses to activate outside the validity window', async () => {
      manager.findOne.mockResolvedValue(
        draft({ validFrom: new Date(Date.now() + 86_400_000) }),
      );

      await expect(service.activate('tariff-draft')).rejects.toMatchObject({
        response: { code: ErrorCode.TARIFF_WINDOW_INVALID },
      });
    });

    it('rejects a second active tariff over an overlapping window', async () => {
      manager.findOne.mockResolvedValue(draft());
      manager.find.mockResolvedValue([
        {
          id: 'incumbent',
          version: 'TARIFF-2026-001',
          status: TariffStatus.ACTIVE,
          validFrom: new Date(Date.now() - 3_600_000),
          validTo: undefined,
        },
      ]);

      await expect(service.activate('tariff-draft')).rejects.toMatchObject({
        response: { code: ErrorCode.TARIFF_WINDOW_OVERLAP },
        status: 409,
      });
    });

    it('retires a stale ACTIVE tariff before activating the next one', async () => {
      manager.findOne.mockResolvedValue(draft());
      manager.find.mockResolvedValue([
        {
          id: 'stale',
          version: 'TARIFF-2025-999',
          status: TariffStatus.ACTIVE,
          validFrom: new Date(Date.now() - 172_800_000),
          validTo: new Date(Date.now() - 86_400_000),
        },
      ]);

      await service.activate('tariff-draft');

      expect(manager.save).toHaveBeenCalledWith(
        expect.objectContaining({
          id: 'stale',
          status: TariffStatus.EXPIRED,
        }),
      );
    });

    it('reports a race lost to the database constraint as an overlap conflict', async () => {
      manager.findOne.mockResolvedValue(draft());
      manager.save.mockRejectedValue({ code: '23505' });

      await expect(service.activate('tariff-draft')).rejects.toMatchObject({
        response: { code: ErrorCode.TARIFF_WINDOW_OVERLAP },
      });
    });

    it('reports an unknown tariff as not found', async () => {
      manager.findOne.mockResolvedValue(null);

      await expect(service.activate('missing')).rejects.toMatchObject({
        response: { code: ErrorCode.TARIFF_NOT_FOUND },
      });
    });
  });

  describe('expire', () => {
    it('expires an ACTIVE tariff, freeing the active slot', async () => {
      tariffRepository.findOne.mockResolvedValue({
        id: 't1',
        status: TariffStatus.ACTIVE,
      });

      await expect(service.expire('t1')).resolves.toMatchObject({
        status: TariffStatus.EXPIRED,
      });
    });

    it('allows retiring a DRAFT tariff', async () => {
      tariffRepository.findOne.mockResolvedValue({
        id: 't1',
        status: TariffStatus.DRAFT,
      });

      await expect(service.expire('t1')).resolves.toMatchObject({
        status: TariffStatus.EXPIRED,
      });
    });

    it('refuses to expire an already EXPIRED tariff', async () => {
      tariffRepository.findOne.mockResolvedValue({
        id: 't1',
        status: TariffStatus.EXPIRED,
      });

      await expect(service.expire('t1')).rejects.toMatchObject({
        response: { code: ErrorCode.TARIFF_STATUS_INVALID },
      });
    });
  });
});
