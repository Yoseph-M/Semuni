/**
 * Tariff versioning and fare-snapshot immutability (e2e) — Phase 5.
 *
 * Runs the real AppModule against the configured PostgreSQL database so the
 * assertions cover routing, guards, validation, the service layer and the
 * database constraints together — including the partial unique index that makes
 * a second ACTIVE tariff impossible.
 *
 * The suite temporarily parks whatever tariff is active in the shared
 * development database and restores it in afterAll, so running it does not
 * leave the environment without a usable schedule.
 *
 * Fixtures are prefixed `tarf_` (accounts) / `TARIFF-E2E-` (versions) so this
 * suite's cleanup cannot touch another suite's data.
 */
import { Test, TestingModule } from '@nestjs/testing';
import { ValidationPipe, HttpStatus } from '@nestjs/common';
import {
  FastifyAdapter,
  NestFastifyApplication,
} from '@nestjs/platform-fastify';
import * as request from 'supertest';
import * as bcrypt from 'bcrypt';
import { DataSource } from 'typeorm';
import { AppModule } from '../src/app.module';
import {
  DriverStatus,
  TariffStatus,
  UserRole,
  VehicleStatus,
} from '../src/common/enums';
import { ErrorCode } from '../src/common/error-codes';
import { GlobalExceptionFilter } from '../src/common/filters/global-exception.filter';

describe('Tariff versioning and lifecycle (e2e)', () => {
  let app: NestFastifyApplication;
  let dataSource: DataSource;

  const suffix = Date.now().toString(36);
  const password = 'password123';
  const prefix = 'tarf_';
  const usernamePattern = `^${prefix}`;
  const VERSION_PREFIX = 'TARIFF-E2E-';
  const ROUTE_CODE = `TARF-${suffix}`;

  interface Account {
    id: string;
    username: string;
    token: string;
  }

  let admin: Account;
  let passenger: Account;
  let driver: Account;
  let vehicleId: string;
  let routeId: string;
  let originStopId: string;
  let destinationStopId: string;

  let parkedTariffId: string | undefined;

  const V1_FARE = 1234;
  const V2_FARE = 2345;

  // Version identifiers are canonical uppercase, so the fixture normalises the
  // random suffix rather than depending on base-36 producing uppercase.
  const versionFor = (label: string) =>
    `${VERSION_PREFIX}${label}-${suffix.toUpperCase()}`;

  const register = async (
    role: UserRole,
    name: string,
    extra: Record<string, unknown> = {},
  ): Promise<Account> => {
    const username = `${prefix}${name}_${suffix}`;
    const response = await request(app.getHttpServer())
      .post('/api/v1/auth/register')
      .send({
        username,
        fullName: `Tarf ${name}`,
        password,
        role,
        ...extra,
      })
      .expect(HttpStatus.CREATED);

    return {
      id: response.body.data.user.id,
      username,
      token: response.body.data.accessToken,
    };
  };

  const createTariff = (
    version: string,
    basePrice: number,
    rules?: Record<string, unknown>[],
  ) =>
    request(app.getHttpServer())
      .post('/api/v1/tariffs')
      .set('Authorization', `Bearer ${admin.token}`)
      .send({
        version,
        name: `Regulator schedule ${version}`,
        validFrom: new Date(Date.now() - 60_000).toISOString(),
        rules: rules ?? [
          {
            routeId,
            vehicleType: 'MINIBUS',
            startStopSequence: 1,
            endStopSequence: 3,
            basePrice,
          },
        ],
      });

  const activate = (id: string, token = admin.token) =>
    request(app.getHttpServer())
      .post(`/api/v1/tariffs/${id}/activate`)
      .set('Authorization', `Bearer ${token}`);

  const expire = (id: string) =>
    request(app.getHttpServer())
      .post(`/api/v1/tariffs/${id}/expire`)
      .set('Authorization', `Bearer ${admin.token}`);

  const quote = (token = passenger.token) =>
    request(app.getHttpServer())
      .post('/api/v1/fares/calculate')
      .set('Authorization', `Bearer ${token}`)
      .send({ routeId, originStopId, destinationStopId });

  beforeAll(async () => {
    const moduleFixture: TestingModule = await Test.createTestingModule({
      imports: [AppModule],
    }).compile();

    app = moduleFixture.createNestApplication<NestFastifyApplication>(
      new FastifyAdapter(),
    );
    app.setGlobalPrefix('api/v1');
    app.useGlobalFilters(new GlobalExceptionFilter());
    app.useGlobalPipes(
      new ValidationPipe({
        whitelist: true,
        forbidNonWhitelisted: true,
        transform: true,
        transformOptions: { enableImplicitConversion: true },
      }),
    );
    await app.init();
    await app.getHttpAdapter().getInstance().ready();

    dataSource = app.get(DataSource);

    passenger = await register(UserRole.PASSENGER, 'passenger');
    driver = await register(UserRole.DRIVER, 'driver', {
      licenseNumber: `TARF-${suffix}`,
    });
    await dataSource.query(`UPDATE drivers SET status = $1 WHERE "userId" = $2`, [
      DriverStatus.ACTIVE,
      driver.id,
    ]);

    const [vehicleRow] = await dataSource.query(
      `INSERT INTO vehicles ("plateNumber", status, "driverId")
       VALUES ($1, $2, $3) RETURNING id`,
      [`TARF-${suffix}`, VehicleStatus.ACTIVE, driver.id],
    );
    vehicleId = vehicleRow.id;

    // ADMIN accounts are never self-registerable; the fixture is inserted
    // directly and then logged in through the real login path.
    const adminUsername = `${prefix}admin_${suffix}`;
    const [adminRow] = await dataSource.query(
      `INSERT INTO users (username, "passwordHash", role, status)
       VALUES ($1, $2, 'ADMIN', 'ACTIVE') RETURNING id`,
      [adminUsername, await bcrypt.hash(password, 10)],
    );
    const loginResponse = await request(app.getHttpServer())
      .post('/api/v1/auth/login')
      .send({ username: adminUsername, password, role: UserRole.ADMIN })
      .expect(HttpStatus.OK);
    admin = {
      id: adminRow.id,
      username: adminUsername,
      token: loginResponse.body.data.accessToken,
    };

    const routeResponse = await request(app.getHttpServer())
      .post('/api/v1/routes')
      .set('Authorization', `Bearer ${admin.token}`)
      .send({
        name: `Tariff Route ${suffix}`,
        code: ROUTE_CODE,
        origin: 'Tarf Origin',
        destination: 'Tarf Terminus',
        stops: [
          { name: 'Tarf Origin', sequence: 1, latitude: 9.01, longitude: 38.76 },
          { name: 'Tarf Midpoint', sequence: 2, latitude: 9.02, longitude: 38.77 },
          { name: 'Tarf Terminus', sequence: 3, latitude: 9.03, longitude: 38.78 },
        ],
      })
      .expect(HttpStatus.CREATED);

    routeId = routeResponse.body.data.id;
    const stops = routeResponse.body.data.stops as { id: string; sequence: number }[];
    originStopId = stops.find((stop) => stop.sequence === 1)!.id;
    destinationStopId = stops.find((stop) => stop.sequence === 3)!.id;

    // Park any schedule already live in the shared development database so this
    // suite controls which tariff is authoritative. Restored in afterAll.
    const parked = await dataSource.query(
      `SELECT id FROM tariffs WHERE status = 'ACTIVE' LIMIT 1`,
    );
    parkedTariffId = parked[0]?.id;
    if (parkedTariffId) {
      await dataSource.query(
        `UPDATE tariffs SET status = 'EXPIRED' WHERE id = $1`,
        [parkedTariffId],
      );
    }
  });

  afterAll(async () => {
    if (dataSource?.isInitialized) {
      const inUsers = `SELECT id FROM users WHERE username ~ $1`;
      await dataSource.query(
        `DELETE FROM trips WHERE "passengerId" IN (${inUsers}) OR "driverId" IN (${inUsers})`,
        [usernamePattern],
      );
      await dataSource.query(
        `DELETE FROM vehicles WHERE "driverId" IN (${inUsers}) OR "plateNumber" LIKE 'TARF-%'`,
        [usernamePattern],
      );
      // The immutability trigger ignores DELETE, so cleaning up test tariffs is
      // still possible even though their rules may have priced a trip.
      await dataSource.query(`DELETE FROM tariffs WHERE version LIKE $1`, [
        `${VERSION_PREFIX}%`,
      ]);
      await dataSource.query(
        `DELETE FROM passengers WHERE "userId" IN (SELECT id FROM users WHERE username ~ $1)`,
        [usernamePattern],
      );
      await dataSource.query(
        `DELETE FROM drivers WHERE "userId" IN (SELECT id FROM users WHERE username ~ $1)`,
        [usernamePattern],
      );
      await dataSource.query(`DELETE FROM users WHERE username ~ $1`, [
        usernamePattern,
      ]);
      await dataSource.query(`DELETE FROM routes WHERE code = $1`, [ROUTE_CODE]);

      // Hand the environment back exactly as it was found.
      if (parkedTariffId) {
        await dataSource.query(
          `UPDATE tariffs SET status = 'ACTIVE' WHERE id = $1 AND "validFrom" <= now() AND ("validTo" IS NULL OR "validTo" >= now())`,
          [parkedTariffId],
        );
      }
    }
    await app?.close();
  });

  describe('lifecycle authorization', () => {
    it('rejects an unauthenticated caller', async () => {
      await request(app.getHttpServer())
        .post('/api/v1/tariffs')
        .send({ version: versionFor('anon'), name: 'x', validFrom: new Date().toISOString(), rules: [] })
        .expect(HttpStatus.UNAUTHORIZED);
    });

    it('denies a non-admin the ability to create a tariff version', async () => {
      await request(app.getHttpServer())
        .post('/api/v1/tariffs')
        .set('Authorization', `Bearer ${passenger.token}`)
        .send({
          version: versionFor('passenger'),
          name: 'x',
          validFrom: new Date().toISOString(),
          rules: [{ routeId, basePrice: 100 }],
        })
        .expect(HttpStatus.FORBIDDEN);
    });

    it('rejects a malformed tariff id with 400, not a database error', async () => {
      await request(app.getHttpServer())
        .get('/api/v1/tariffs/not-a-uuid')
        .set('Authorization', `Bearer ${admin.token}`)
        .expect(HttpStatus.BAD_REQUEST)
        .expect((res) => {
          expect(res.body.code).toEqual(ErrorCode.VALIDATION_ERROR);
        });
    });
  });

  describe('create → activate → expire', () => {
    let v1Id: string;
    const v1Version = versionFor('V1');

    it('creates a tariff in DRAFT, never live', async () => {
      const response = await createTariff(v1Version, V1_FARE).expect(
        HttpStatus.CREATED,
      );

      expect(response.body.data.status).toEqual(TariffStatus.DRAFT);
      expect(response.body.data.version).toEqual(v1Version);
      v1Id = response.body.data.id;
    });

    it('does not let a DRAFT tariff price a fare', async () => {
      await request(app.getHttpServer())
        .get('/api/v1/tariffs/active')
        .set('Authorization', `Bearer ${passenger.token}`)
        .expect(HttpStatus.NOT_FOUND)
        .expect((res) => {
          expect(res.body.code).toEqual(ErrorCode.TARIFF_NOT_FOUND);
        });

      await quote()
        .expect(HttpStatus.NOT_FOUND)
        .expect((res) => {
          expect(res.body.code).toEqual(ErrorCode.TARIFF_NOT_FOUND);
        });
    });

    it('refuses to reuse a version identifier', async () => {
      await createTariff(v1Version, V1_FARE)
        .expect(HttpStatus.CONFLICT)
        .expect((res) => {
          expect(res.body.code).toEqual(ErrorCode.TARIFF_VERSION_EXISTS);
        });
    });

    it('rejects a window that ends before it starts', async () => {
      const now = new Date().toISOString();

      await request(app.getHttpServer())
        .post('/api/v1/tariffs')
        .set('Authorization', `Bearer ${admin.token}`)
        .send({
          version: versionFor('BAD-WINDOW'),
          name: 'x',
          validFrom: now,
          validTo: now,
          rules: [{ routeId, basePrice: 100 }],
        })
        .expect(HttpStatus.BAD_REQUEST)
        .expect((res) => {
          expect(res.body.code).toEqual(ErrorCode.TARIFF_WINDOW_INVALID);
        });
    });

    it('rejects an impossible stop range', async () => {
      await createTariff(versionFor('BAD-RANGE'), V1_FARE, [
        {
          routeId,
          startStopSequence: 3,
          endStopSequence: 1,
          basePrice: V1_FARE,
        },
      ])
        .expect(HttpStatus.BAD_REQUEST)
        .expect((res) => {
          expect(res.body.code).toEqual(ErrorCode.STOP_ORDER_INVALID);
        });
    });

    it('rejects a non-integer minor-unit price', async () => {
      await createTariff(versionFor('BAD-PRICE'), 12.5)
        .expect(HttpStatus.BAD_REQUEST)
        .expect((res) => {
          expect(res.body.code).toEqual(ErrorCode.VALIDATION_ERROR);
        });
    });

    it('denies a non-admin the ability to activate', async () => {
      await activate(v1Id, passenger.token).expect(HttpStatus.FORBIDDEN);
    });

    it('activates the DRAFT tariff for admin', async () => {
      const response = await activate(v1Id).expect(HttpStatus.CREATED);
      expect(response.body.data.status).toEqual(TariffStatus.ACTIVE);
    });

    it('reads the version back by id for admin', async () => {
      const response = await request(app.getHttpServer())
        .get(`/api/v1/tariffs/${v1Id}`)
        .set('Authorization', `Bearer ${admin.token}`)
        .expect(HttpStatus.OK);

      expect(response.body.data.id).toEqual(v1Id);
      expect(response.body.data.rules).toHaveLength(1);
    });
  });

  describe('authoritative pricing and trip snapshot', () => {
    let v1Id: string;
    let v1Version: string;
    let tripId: string;
    let tripFare: number;

    beforeAll(async () => {
      const response = await request(app.getHttpServer())
        .get('/api/v1/tariffs/active')
        .set('Authorization', `Bearer ${passenger.token}`)
        .expect(HttpStatus.OK);

      v1Id = response.body.data.id;
      v1Version = response.body.data.version;
    });

    it('quotes the fare from the active tariff and ordered stops', async () => {
      const response = await quote().expect(HttpStatus.CREATED);

      expect(response.body.data.fare).toEqual(V1_FARE);
      expect(response.body.data.tariffVersion).toEqual(v1Version);
      expect(response.body.data.routeId).toEqual(routeId);
    });

    it('rejects reverse-direction travel', async () => {
      await request(app.getHttpServer())
        .post('/api/v1/fares/calculate')
        .set('Authorization', `Bearer ${passenger.token}`)
        .send({
          routeId,
          originStopId: destinationStopId,
          destinationStopId: originStopId,
        })
        .expect(HttpStatus.BAD_REQUEST)
        .expect((res) => {
          expect(res.body.code).toEqual(ErrorCode.STOP_ORDER_INVALID);
        });
    });

    it('rejects a stop that belongs to another route', async () => {
      await request(app.getHttpServer())
        .post('/api/v1/fares/calculate')
        .set('Authorization', `Bearer ${passenger.token}`)
        .send({
          routeId,
          originStopId,
          destinationStopId: '00000000-0000-4000-8000-000000000009',
        })
        .expect(HttpStatus.BAD_REQUEST)
        .expect((res) => {
          expect(res.body.code).toEqual(ErrorCode.STOP_NOT_FOUND);
        });
    });

    it('stores the authoritative fare and snapshot on the trip', async () => {
      const response = await request(app.getHttpServer())
        .post('/api/v1/trips')
        .set('Authorization', `Bearer ${passenger.token}`)
        .send({
          driverId: driver.id,
          vehicleId,
          routeId,
          originStopId,
          destinationStopId,
          origin: 'client supplied text',
          destination: 'client supplied text',
        })
        .expect(HttpStatus.CREATED);

      tripId = response.body.data.id;
      tripFare = response.body.data.fareAmount;

      expect(response.body.data.fareAmount).toEqual(V1_FARE);
      expect(response.body.data.tariffId).toEqual(v1Id);
      expect(response.body.data.tariffVersion).toEqual(v1Version);
      expect(response.body.data.originStopId).toEqual(originStopId);
      expect(response.body.data.destinationStopId).toEqual(destinationStopId);
      // Stop names come from the route, not from the client.
      expect(response.body.data.origin).toEqual('Tarf Origin');
      expect(response.body.data.destination).toEqual('Tarf Terminus');
    });

    it('rejects a client-quoted fare that disagrees with the server', async () => {
      await request(app.getHttpServer())
        .post('/api/v1/trips')
        .set('Authorization', `Bearer ${passenger.token}`)
        .send({
          driverId: driver.id,
          vehicleId,
          routeId,
          originStopId,
          destinationStopId,
          origin: 'Tarf Origin',
          destination: 'Tarf Terminus',
          fareAmount: 1,
        })
        .expect(HttpStatus.BAD_REQUEST)
        .expect((res) => {
          expect(res.body.code).toEqual(ErrorCode.FARE_MISMATCH);
        });
    });

    it('rejects a second active tariff over an overlapping window', async () => {
      const created = await createTariff(versionFor('V2'), V2_FARE).expect(
        HttpStatus.CREATED,
      );

      await activate(created.body.data.id)
        .expect(HttpStatus.CONFLICT)
        .expect((res) => {
          expect(res.body.code).toEqual(ErrorCode.TARIFF_WINDOW_OVERLAP);
        });
    });

    it('keeps the historical trip fare after a new version becomes active', async () => {
      // Retire V1 explicitly, then publish V2 at a different price.
      await expire(v1Id).expect(HttpStatus.CREATED);

      const v2 = await request(app.getHttpServer())
        .get('/api/v1/tariffs')
        .set('Authorization', `Bearer ${admin.token}`)
        .expect(HttpStatus.OK);
      const v2Id = (v2.body.data as { id: string; version: string }[]).find(
        (tariff) => tariff.version.startsWith(`${VERSION_PREFIX}V2`),
      )!.id;

      await activate(v2Id).expect(HttpStatus.CREATED);

      // New quotes use V2…
      const freshQuote = await quote().expect(HttpStatus.CREATED);
      expect(freshQuote.body.data.fare).toEqual(V2_FARE);

      // …but the trip priced under V1 is unchanged, version label included.
      const trip = await request(app.getHttpServer())
        .get(`/api/v1/trips/${tripId}`)
        .set('Authorization', `Bearer ${passenger.token}`)
        .expect(HttpStatus.OK);

      expect(trip.body.data.fareAmount).toEqual(tripFare);
      expect(trip.body.data.fareAmount).toEqual(V1_FARE);
      expect(trip.body.data.tariffVersion).toEqual(v1Version);
    });
  });

  describe('ambiguous pricing configuration', () => {
    let ambiguousId: string;

    it('rejects a fare when two rules match equally well', async () => {
      // Clear the active slot, then publish a deliberately ambiguous schedule.
      const active = await request(app.getHttpServer())
        .get('/api/v1/tariffs/active')
        .set('Authorization', `Bearer ${admin.token}`)
        .expect(HttpStatus.OK);
      await expire(active.body.data.id).expect(HttpStatus.CREATED);

      const ambiguous = await createTariff(versionFor('AMBIGUOUS'), V1_FARE, [
        {
          routeId,
          vehicleType: 'MINIBUS',
          startStopSequence: 1,
          endStopSequence: 3,
          basePrice: V1_FARE,
        },
        {
          routeId,
          vehicleType: 'MINIBUS',
          startStopSequence: 1,
          endStopSequence: 3,
          basePrice: V2_FARE,
        },
      ]).expect(HttpStatus.CREATED);

      ambiguousId = ambiguous.body.data.id;
      await activate(ambiguousId).expect(HttpStatus.CREATED);

      await quote()
        .expect(HttpStatus.CONFLICT)
        .expect((res) => {
          expect(res.body.code).toEqual(ErrorCode.TARIFF_RULE_AMBIGUOUS);
        });
    });

    it('refuses to re-activate a version that has been expired', async () => {
      await expire(ambiguousId).expect(HttpStatus.CREATED);

      await activate(ambiguousId)
        .expect(HttpStatus.CONFLICT)
        .expect((res) => {
          expect(res.body.code).toEqual(ErrorCode.TARIFF_STATUS_INVALID);
        });
    });
  });
});
