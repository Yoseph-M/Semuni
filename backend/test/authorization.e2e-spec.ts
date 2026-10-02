/**
 * Authorization (e2e) — Phase 3 security hardening.
 *
 * Boots the real AppModule against the configured PostgreSQL database, so every
 * assertion runs through routing, guards, the validation pipe and the actual
 * persistence layer. Mirrors main.ts (global prefix + validation) because e2e
 * tests bypass bootstrap().
 *
 * Accounts created here are prefixed `authz_` rather than `e2e_`: auth.e2e-spec
 * cleans up by the broad `^e2e_` prefix, and Jest runs suites in parallel, so a
 * shared prefix would let one suite delete the other's fixtures mid-run.
 *
 * Covers:
 *   - object-level authorization on trips and payments (own = 200, foreign = 403)
 *   - ADMIN privileged branches
 *   - driver-only withdrawal authorization (role + profile + ACTIVE status)
 *   - vehicle ownership / status on trip creation
 *   - driver operational status
 *   - idempotency key ownership and payload conflicts
 *   - UUID validation on :id parameters
 *   - user status re-checked on refresh
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
  PaymentProvider,
  PaymentRecordStatus,
  UserRole,
  UserStatus,
  VehicleStatus,
} from '../src/common/enums';
import { ErrorCode } from '../src/common/error-codes';
import { GlobalExceptionFilter } from '../src/common/filters/global-exception.filter';

describe('Authorization (e2e)', () => {
  let app: NestFastifyApplication;
  let dataSource: DataSource;

  const suffix = Date.now().toString(36);
  const password = 'password123';
  const prefix = `authz_`;
  const usernamePattern = `^${prefix}`;

  interface Account {
    id: string;
    username: string;
    token: string;
    refreshToken: string;
  }

  let passengerA: Account;
  let passengerB: Account;
  let passengerC: Account;
  let driverA: Account;
  let driverB: Account;
  let driverPending: Account;
  let driverSuspended: Account;
  let admin: Account;
  let statusCase: Account;

  let driverAPlate: string;
  let vehicleA: string;
  let vehicleInactive: string;
  let vehicleB: string;
  let driverPendingRecordId: string;

  let tripA: string;
  let tripA2: string;
  let tripC: string;
  let paymentA: string;

  const PAID_FARE_MINOR = 5000;

  const register = async (
    role: UserRole,
    name: string,
    extra: Record<string, unknown> = {},
  ) => {
    const username = `${prefix}${name}_${suffix}`;
    const response = await request(app.getHttpServer())
      .post('/api/v1/auth/register')
      .send({
        username,
        fullName: `Authz ${name}`,
        password,
        role,
        ...extra,
      })
      .expect(HttpStatus.CREATED);

    return {
      id: response.body.data.user.id as string,
      username,
      token: response.body.data.accessToken as string,
      refreshToken: response.body.data.refreshToken as string,
    };
  };

  const login = async (
    username: string,
    role: UserRole,
  ): Promise<Account> => {
    const response = await request(app.getHttpServer())
      .post('/api/v1/auth/login')
      .send({ username, password, role })
      .expect(HttpStatus.OK);

    return {
      id: response.body.data.user.id,
      username,
      token: response.body.data.accessToken,
      refreshToken: response.body.data.refreshToken,
    };
  };

  beforeAll(async () => {
    const moduleFixture: TestingModule = await Test.createTestingModule({
      imports: [AppModule],
    }).compile();

    app = moduleFixture.createNestApplication<NestFastifyApplication>(
      new FastifyAdapter(),
    );
    app.setGlobalPrefix('api/v1');
    // Mirror main.ts including the exception filter, so the `code` contract
    // asserted below is the one production actually returns.
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

    passengerA = await register(UserRole.PASSENGER, 'passenger_a');
    passengerB = await register(UserRole.PASSENGER, 'passenger_b');
    passengerC = await register(UserRole.PASSENGER, 'passenger_c');

    driverA = await register(UserRole.DRIVER, 'driver_a', {
      licenseNumber: `AUTHZ-A-${suffix}`,
    });
    driverB = await register(UserRole.DRIVER, 'driver_b', {
      licenseNumber: `AUTHZ-B-${suffix}`,
    });
    driverPending = await register(UserRole.DRIVER, 'driver_pending', {
      licenseNumber: `AUTHZ-P-${suffix}`,
    });
    driverSuspended = await register(UserRole.DRIVER, 'driver_suspended', {
      licenseNumber: `AUTHZ-S-${suffix}`,
    });

    // Driver A and B are approved; the others stay PENDING / SUSPENDED so the
    // operational-status policy can be exercised.
    await dataSource.query(
      `UPDATE drivers SET status = $1 WHERE "userId" = $2`,
      [DriverStatus.ACTIVE, driverA.id],
    );
    await dataSource.query(
      `UPDATE drivers SET status = $1 WHERE "userId" = $2`,
      [DriverStatus.ACTIVE, driverB.id],
    );
    await dataSource.query(
      `UPDATE drivers SET status = $1 WHERE "userId" = $2`,
      [DriverStatus.SUSPENDED, driverSuspended.id],
    );

    // ADMIN accounts are never self-registerable, so the fixture is inserted
    // directly — the login path under test is still the real one.
    const adminUsername = `${prefix}admin_${suffix}`;
    const [adminRow] = await dataSource.query(
      `INSERT INTO users (username, "passwordHash", role, status)
       VALUES ($1, $2, 'ADMIN', 'ACTIVE') RETURNING id`,
      [adminUsername, await bcrypt.hash(password, 10)],
    );
    admin = await login(adminUsername, UserRole.ADMIN);
    admin.id = adminRow.id;

    const [driverPendingRow] = await dataSource.query(
      `SELECT id FROM drivers WHERE "userId" = $1`,
      [driverPending.id],
    );
    driverPendingRecordId = driverPendingRow.id;

    // Wallets: passenger A funds the payment tests, passenger C proves key
    // scoping, driver A has a balance to withdraw.
    await dataSource.query(
      `INSERT INTO wallets (balance, currency, status, "userId")
       VALUES (100000, 'ETB', 'ACTIVE', $1), (100000, 'ETB', 'ACTIVE', $2), (10000, 'ETB', 'ACTIVE', $3)`,
      [passengerA.id, passengerC.id, driverA.id],
    );

    // Vehicles: A and B are ACTIVE and assigned to their drivers, `inactive`
    // belongs to driver A but is off the road.
    driverAPlate = `AUTHZ-${suffix}-A`;
    const [vehicleARow] = await dataSource.query(
      `INSERT INTO vehicles ("plateNumber", status, "driverId")
       VALUES ($1, $2, $3) RETURNING id`,
      [driverAPlate, VehicleStatus.ACTIVE, driverA.id],
    );
    vehicleA = vehicleARow.id;
    const [vehicleInactiveRow] = await dataSource.query(
      `INSERT INTO vehicles ("plateNumber", status, "driverId")
       VALUES ($1, $2, $3) RETURNING id`,
      [`AUTHZ-${suffix}-X`, VehicleStatus.INACTIVE, driverA.id],
    );
    vehicleInactive = vehicleInactiveRow.id;
    const [vehicleBRow] = await dataSource.query(
      `INSERT INTO vehicles ("plateNumber", status, "driverId")
       VALUES ($1, $2, $3) RETURNING id`,
      [`AUTHZ-${suffix}-B`, VehicleStatus.ACTIVE, driverB.id],
    );
    vehicleB = vehicleBRow.id;

    const insertTrip = async (
      passengerId: string,
      fareAmount: number,
    ): Promise<string> => {
      const [row] = await dataSource.query(
        `INSERT INTO trips
           ("passengerId", "driverId", "vehicleId", origin, destination,
            "fareAmount", currency, status, "paymentStatus")
         VALUES ($1, $2, $3, 'Authz Origin', 'Authz Destination', $4, 'ETB', 'PENDING', 'UNPAID')
         RETURNING id`,
        [passengerId, driverA.id, vehicleA, fareAmount],
      );
      return row.id;
    };

    tripA = await insertTrip(passengerA.id, PAID_FARE_MINOR);
    tripA2 = await insertTrip(passengerA.id, 1000);
    tripC = await insertTrip(passengerC.id, 2000);
  });

  afterAll(async () => {
    if (dataSource?.isInitialized) {
      const inUsers = `SELECT id::text FROM users WHERE username ~ $1`;
      await dataSource.query(
        `DELETE FROM ledger_entries WHERE "walletId" IN (
           SELECT w.id::text FROM wallets w JOIN users u ON u.id = w."userId"
           WHERE u.username ~ $1
         )`,
        [usernamePattern],
      );
      await dataSource.query(
        `DELETE FROM settlements WHERE "driverId" IN (${inUsers})`,
        [usernamePattern],
      );
      await dataSource.query(
        `DELETE FROM payments WHERE "passengerId" IN (${inUsers}) OR "driverId" IN (${inUsers})`,
        [usernamePattern],
      );
      await dataSource.query(
        `DELETE FROM withdrawals WHERE "userId" IN (${inUsers})`,
        [usernamePattern],
      );
      await dataSource.query(
        `DELETE FROM trips WHERE "passengerId" IN (${inUsers}) OR "driverId" IN (${inUsers})`,
        [usernamePattern],
      );
      await dataSource.query(
        `DELETE FROM top_up_intents WHERE "userId" IN (SELECT id FROM users WHERE username ~ $1)`,
        [usernamePattern],
      );
      await dataSource.query(
        `DELETE FROM vehicles WHERE "driverId" IN (${inUsers}) OR "plateNumber" LIKE 'AUTHZ-%'`,
        [usernamePattern],
      );
      await dataSource.query(
        `DELETE FROM wallets WHERE "userId" IN (SELECT id FROM users WHERE username ~ $1)`,
        [usernamePattern],
      );
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
    }
    await app?.close();
  });

  describe('GET /trips/:id — object-level authorization', () => {
    it('lets the owning passenger read their trip', async () => {
      const response = await request(app.getHttpServer())
        .get(`/api/v1/trips/${tripA}`)
        .set('Authorization', `Bearer ${passengerA.token}`)
        .expect(HttpStatus.OK);

      expect(response.body.data.id).toEqual(tripA);
    });

    it('lets the assigned driver read the trip', async () => {
      await request(app.getHttpServer())
        .get(`/api/v1/trips/${tripA}`)
        .set('Authorization', `Bearer ${driverA.token}`)
        .expect(HttpStatus.OK);
    });

    it('denies a different passenger (valid UUID is not authorization)', async () => {
      await request(app.getHttpServer())
        .get(`/api/v1/trips/${tripA}`)
        .set('Authorization', `Bearer ${passengerB.token}`)
        .expect(HttpStatus.FORBIDDEN)
        .expect((res) => {
          expect(res.body.code).toEqual(ErrorCode.TRIP_NOT_OWNED);
        });
    });

    it('denies a different driver', async () => {
      await request(app.getHttpServer())
        .get(`/api/v1/trips/${tripA}`)
        .set('Authorization', `Bearer ${driverB.token}`)
        .expect(HttpStatus.FORBIDDEN)
        .expect((res) => {
          expect(res.body.code).toEqual(ErrorCode.TRIP_NOT_OWNED);
        });
    });

    it('allows ADMIN through the explicit privileged branch', async () => {
      await request(app.getHttpServer())
        .get(`/api/v1/trips/${tripA}`)
        .set('Authorization', `Bearer ${admin.token}`)
        .expect(HttpStatus.OK);
    });

    it('rejects an unauthenticated caller', async () => {
      await request(app.getHttpServer())
        .get(`/api/v1/trips/${tripA}`)
        .expect(HttpStatus.UNAUTHORIZED);
    });

    it('rejects a malformed id with 400, not a database error', async () => {
      await request(app.getHttpServer())
        .get('/api/v1/trips/not-a-uuid')
        .set('Authorization', `Bearer ${passengerA.token}`)
        .expect(HttpStatus.BAD_REQUEST)
        .expect((res) => {
          expect(res.body.code).toEqual(ErrorCode.VALIDATION_ERROR);
        });
    });

    it('returns 404 (not 403) for an unknown trip', async () => {
      await request(app.getHttpServer())
        .get('/api/v1/trips/00000000-0000-4000-8000-000000000000')
        .set('Authorization', `Bearer ${passengerA.token}`)
        .expect(HttpStatus.NOT_FOUND)
        .expect((res) => {
          expect(res.body.code).toEqual(ErrorCode.TRIP_NOT_FOUND);
        });
    });
  });

  describe('POST /trips — driver and vehicle policy', () => {
    // Phase 4 made authoritative route and stop IDs part of the trip contract,
    // so a stop-less payload no longer reaches the service at all. The driver
    // and vehicle policy asserted below is evaluated before the fare lookup,
    // so format-valid placeholder IDs are enough to exercise it.
    const placeholderStops = {
      routeId: '00000000-0000-4000-8000-000000000000',
      originStopId: '00000000-0000-4000-8000-000000000001',
      destinationStopId: '00000000-0000-4000-8000-000000000002',
    };

    const createTrip = (as: Account, body: Record<string, unknown>) =>
      request(app.getHttpServer())
        .post('/api/v1/trips')
        .set('Authorization', `Bearer ${as.token}`)
        .send({
          origin: 'Authz Origin',
          destination: 'Authz Destination',
          ...placeholderStops,
          ...body,
        });

    it('denies a vehicle registered to a different driver', async () => {
      await createTrip(passengerA, {
        driverId: driverA.id,
        vehicleId: vehicleB,
      })
        .expect(HttpStatus.FORBIDDEN)
        .expect((res) => {
          expect(res.body.code).toEqual(ErrorCode.VEHICLE_NOT_OWNED);
        });
    });

    it('denies an inactive vehicle', async () => {
      await createTrip(passengerA, {
        driverId: driverA.id,
        vehicleId: vehicleInactive,
      })
        .expect(HttpStatus.BAD_REQUEST)
        .expect((res) => {
          expect(res.body.code).toEqual(ErrorCode.VEHICLE_NOT_ACTIVE);
        });
    });

    it('denies a driver whose profile is not ACTIVE', async () => {
      await createTrip(passengerA, { driverId: driverPending.id })
        .expect(HttpStatus.BAD_REQUEST)
        .expect((res) => {
          expect(res.body.code).toEqual(ErrorCode.DRIVER_NOT_ACTIVE);
        });
    });

    it('denies a suspended driver', async () => {
      await createTrip(passengerA, { driverId: driverSuspended.id })
        .expect(HttpStatus.BAD_REQUEST)
        .expect((res) => {
          expect(res.body.code).toEqual(ErrorCode.DRIVER_NOT_ACTIVE);
        });
    });

    it('denies a userId that has no driver profile', async () => {
      await createTrip(passengerA, { driverId: passengerB.id })
        .expect(HttpStatus.NOT_FOUND)
        .expect((res) => {
          expect(res.body.code).toEqual(ErrorCode.DRIVER_NOT_FOUND);
        });
    });

    it('denies a driver from creating a trip (passenger-only route)', async () => {
      await createTrip(driverA, { driverId: driverA.id }).expect(
        HttpStatus.FORBIDDEN,
      );
    });
  });

  describe('POST /payments/trip — ownership, idempotency and conflicts', () => {
    const paymentKey = `authz-pay-${suffix}`;
    let firstPaymentId: string;

    it('pays the trip and records exactly one successful payment', async () => {
      const response = await request(app.getHttpServer())
        .post('/api/v1/payments/trip')
        .set('Authorization', `Bearer ${passengerA.token}`)
        .send({ tripId: tripA, idempotencyKey: paymentKey })
        .expect(HttpStatus.OK);

      expect(response.body.data.status).toEqual(
        PaymentRecordStatus.SUCCESS,
      );
      firstPaymentId = response.body.data.paymentId;

      const [counts] = await dataSource.query(
        `SELECT COUNT(*)::int AS payments FROM payments WHERE "tripId" = $1`,
        [tripA],
      );
      expect(counts.payments).toEqual(1);

      const ledger = await dataSource.query(
        `SELECT direction, amount FROM ledger_entries WHERE "referenceId" = $1 ORDER BY direction`,
        [tripA],
      );
      expect(ledger).toHaveLength(2);
      expect(ledger.map((e: { direction: string }) => e.direction)).toEqual([
        'CREDIT',
        'DEBIT',
      ]);
      expect(ledger.every((e: { amount: number }) => e.amount === PAID_FARE_MINOR)).toBe(
        true,
      );
    });

    it('returns the same payment for a repeated identical request', async () => {
      const response = await request(app.getHttpServer())
        .post('/api/v1/payments/trip')
        .set('Authorization', `Bearer ${passengerA.token}`)
        .send({ tripId: tripA, idempotencyKey: paymentKey })
        .expect(HttpStatus.OK);

      expect(response.body.data.paymentId).toEqual(firstPaymentId);

      const [counts] = await dataSource.query(
        `SELECT COUNT(*)::int AS payments FROM payments WHERE "tripId" = $1`,
        [tripA],
      );
      expect(counts.payments).toEqual(1);
    });

    it('rejects the same key reused for a different trip (payload conflict)', async () => {
      await request(app.getHttpServer())
        .post('/api/v1/payments/trip')
        .set('Authorization', `Bearer ${passengerA.token}`)
        .send({ tripId: tripA2, idempotencyKey: paymentKey })
        .expect(HttpStatus.CONFLICT)
        .expect((res) => {
          expect(res.body.code).toEqual(ErrorCode.IDEMPOTENCY_CONFLICT);
        });

      // The conflicting request must not have paid anything.
      const [counts] = await dataSource.query(
        `SELECT COUNT(*)::int AS payments FROM payments WHERE "tripId" = $1`,
        [tripA2],
      );
      expect(counts.payments).toEqual(0);
    });

    it('allows another passenger to use the same key for their own trip', async () => {
      const response = await request(app.getHttpServer())
        .post('/api/v1/payments/trip')
        .set('Authorization', `Bearer ${passengerC.token}`)
        .send({ tripId: tripC, idempotencyKey: paymentKey })
        .expect(HttpStatus.OK);

      // Same key, different owner ⇒ a different operation, never a shared one.
      expect(response.body.data.paymentId).not.toEqual(firstPaymentId);
      expect(response.body.data.tripId).toEqual(tripC);
    });

    it('denies paying a trip that belongs to another passenger', async () => {
      await request(app.getHttpServer())
        .post('/api/v1/payments/trip')
        .set('Authorization', `Bearer ${passengerB.token}`)
        .send({ tripId: tripA2, idempotencyKey: `authz-foreign-${suffix}` })
        .expect(HttpStatus.FORBIDDEN)
        .expect((res) => {
          expect(res.body.code).toEqual(ErrorCode.TRIP_NOT_OWNED);
        });
    });

    it('denies a driver from initiating a trip payment', async () => {
      await request(app.getHttpServer())
        .post('/api/v1/payments/trip')
        .set('Authorization', `Bearer ${driverA.token}`)
        .send({ tripId: tripA, idempotencyKey: `authz-driver-${suffix}` })
        .expect(HttpStatus.FORBIDDEN);
    });

    it('stores paid receipts without exposing provider internals', async () => {
      paymentA = firstPaymentId;

      const response = await request(app.getHttpServer())
        .get(`/api/v1/payments/${paymentA}`)
        .set('Authorization', `Bearer ${passengerA.token}`)
        .expect(HttpStatus.OK);

      expect(response.body.data.receiptNumber).toBeDefined();
      expect(response.body.data.idempotencyKey).toBeUndefined();
      expect(response.body.data.providerReference).toBeUndefined();
    });
  });

  describe('GET /payments/:id — object-level authorization', () => {
    it('lets the paying passenger read the payment', async () => {
      await request(app.getHttpServer())
        .get(`/api/v1/payments/${paymentA}`)
        .set('Authorization', `Bearer ${passengerA.token}`)
        .expect(HttpStatus.OK);
    });

    it('lets the paid driver read the payment', async () => {
      await request(app.getHttpServer())
        .get(`/api/v1/payments/${paymentA}`)
        .set('Authorization', `Bearer ${driverA.token}`)
        .expect(HttpStatus.OK);
    });

    it('denies an unrelated passenger', async () => {
      await request(app.getHttpServer())
        .get(`/api/v1/payments/${paymentA}`)
        .set('Authorization', `Bearer ${passengerB.token}`)
        .expect(HttpStatus.FORBIDDEN)
        .expect((res) => {
          expect(res.body.code).toEqual(ErrorCode.PAYMENT_NOT_OWNED);
        });
    });

    it('denies an unrelated driver', async () => {
      await request(app.getHttpServer())
        .get(`/api/v1/payments/${paymentA}`)
        .set('Authorization', `Bearer ${driverB.token}`)
        .expect(HttpStatus.FORBIDDEN)
        .expect((res) => {
          expect(res.body.code).toEqual(ErrorCode.PAYMENT_NOT_OWNED);
        });
    });

    it('allows ADMIN through the explicit privileged branch', async () => {
      await request(app.getHttpServer())
        .get(`/api/v1/payments/${paymentA}`)
        .set('Authorization', `Bearer ${admin.token}`)
        .expect(HttpStatus.OK);
    });

    it('rejects a malformed id with 400', async () => {
      await request(app.getHttpServer())
        .get('/api/v1/payments/12345')
        .set('Authorization', `Bearer ${passengerA.token}`)
        .expect(HttpStatus.BAD_REQUEST)
        .expect((res) => {
          expect(res.body.code).toEqual(ErrorCode.VALIDATION_ERROR);
        });
    });
  });

  describe('withdrawals — driver-only, operational-status gated', () => {
    const withdrawalKey = `authz-wd-${suffix}`;
    const withdrawalBody = {
      amount: 2000,
      destinationType: 'BANK',
      destination: 'Commercial Bank of Ethiopia',
      destinationAccount: '10001234567890',
      provider: PaymentProvider.MOCK,
      idempotencyKey: withdrawalKey,
    };
    let withdrawalId: string;

    it('denies a passenger', async () => {
      await request(app.getHttpServer())
        .post('/api/v1/withdrawals')
        .set('Authorization', `Bearer ${passengerA.token}`)
        .send(withdrawalBody)
        .expect(HttpStatus.FORBIDDEN)
        .expect((res) => {
          expect(res.body.code).toEqual(ErrorCode.AUTH_FORBIDDEN);
        });
    });

    it('denies a driver whose profile is PENDING', async () => {
      await request(app.getHttpServer())
        .post('/api/v1/withdrawals')
        .set('Authorization', `Bearer ${driverPending.token}`)
        .send(withdrawalBody)
        .expect(HttpStatus.FORBIDDEN)
        .expect((res) => {
          expect(res.body.code).toEqual(ErrorCode.DRIVER_NOT_ACTIVE);
        });
    });

    it('denies a suspended driver', async () => {
      await request(app.getHttpServer())
        .post('/api/v1/withdrawals')
        .set('Authorization', `Bearer ${driverSuspended.token}`)
        .send(withdrawalBody)
        .expect(HttpStatus.FORBIDDEN)
        .expect((res) => {
          expect(res.body.code).toEqual(ErrorCode.DRIVER_NOT_ACTIVE);
        });
    });

    it('allows an ACTIVE driver and debits the wallet once', async () => {
      // Driver A has already been credited by the trip-payment tests, so the
      // assertion is a delta rather than a hard-coded balance.
      const [before] = await dataSource.query(
        `SELECT balance FROM wallets WHERE "userId" = $1`,
        [driverA.id],
      );

      const response = await request(app.getHttpServer())
        .post('/api/v1/withdrawals')
        .set('Authorization', `Bearer ${driverA.token}`)
        .send(withdrawalBody)
        .expect(HttpStatus.CREATED);

      withdrawalId = response.body.data.id;

      const [after] = await dataSource.query(
        `SELECT balance FROM wallets WHERE "userId" = $1`,
        [driverA.id],
      );
      expect(after.balance).toEqual(before.balance - 2000);
    });

    it('returns the same withdrawal for the same key and payload', async () => {
      const response = await request(app.getHttpServer())
        .post('/api/v1/withdrawals')
        .set('Authorization', `Bearer ${driverA.token}`)
        .send(withdrawalBody)
        .expect(HttpStatus.CREATED);

      expect(response.body.data.id).toEqual(withdrawalId);

      const [counts] = await dataSource.query(
        `SELECT COUNT(*)::int AS withdrawals FROM withdrawals WHERE "userId" = $1`,
        [driverA.id],
      );
      expect(counts.withdrawals).toEqual(1);
    });

    it('rejects the same key with a different amount', async () => {
      await request(app.getHttpServer())
        .post('/api/v1/withdrawals')
        .set('Authorization', `Bearer ${driverA.token}`)
        .send({ ...withdrawalBody, amount: 3000 })
        .expect(HttpStatus.CONFLICT)
        .expect((res) => {
          expect(res.body.code).toEqual(ErrorCode.IDEMPOTENCY_CONFLICT);
        });
    });

    it('rejects a withdrawal beyond the wallet balance', async () => {
      await request(app.getHttpServer())
        .post('/api/v1/withdrawals')
        .set('Authorization', `Bearer ${driverA.token}`)
        .send({
          ...withdrawalBody,
          amount: 999999,
          idempotencyKey: `${withdrawalKey}-big`,
        })
        .expect(HttpStatus.BAD_REQUEST)
        .expect((res) => {
          expect(res.body.code).toEqual(ErrorCode.WITHDRAWAL_INSUFFICIENT_BALANCE);
        });
    });

    it('scopes the withdrawal history to the caller', async () => {
      const own = await request(app.getHttpServer())
        .get('/api/v1/withdrawals')
        .set('Authorization', `Bearer ${driverA.token}`)
        .expect(HttpStatus.OK);

      expect(own.body.data.map((w: { id: string }) => w.id)).toContain(
        withdrawalId,
      );

      const other = await request(app.getHttpServer())
        .get('/api/v1/withdrawals')
        .set('Authorization', `Bearer ${driverB.token}`)
        .expect(HttpStatus.OK);

      expect(other.body.data).toHaveLength(0);
    });

    it('denies a passenger the withdrawal history endpoint', async () => {
      await request(app.getHttpServer())
        .get('/api/v1/withdrawals')
        .set('Authorization', `Bearer ${passengerB.token}`)
        .expect(HttpStatus.FORBIDDEN);
    });
  });

  describe('driver operational status on financial reads', () => {
    it('denies earnings to a PENDING driver', async () => {
      await request(app.getHttpServer())
        .get('/api/v1/drivers/me/earnings')
        .set('Authorization', `Bearer ${driverPending.token}`)
        .expect(HttpStatus.FORBIDDEN)
        .expect((res) => {
          expect(res.body.code).toEqual(ErrorCode.DRIVER_NOT_ACTIVE);
        });
    });

    it('denies transactions to a SUSPENDED driver', async () => {
      await request(app.getHttpServer())
        .get('/api/v1/drivers/me/transactions')
        .set('Authorization', `Bearer ${driverSuspended.token}`)
        .expect(HttpStatus.FORBIDDEN)
        .expect((res) => {
          expect(res.body.code).toEqual(ErrorCode.DRIVER_NOT_ACTIVE);
        });
    });

    it('allows the profile itself so the app can display the status', async () => {
      const response = await request(app.getHttpServer())
        .get('/api/v1/drivers/me')
        .set('Authorization', `Bearer ${driverPending.token}`)
        .expect(HttpStatus.OK);

      expect(response.body.data.status).toEqual(DriverStatus.PENDING);
    });

    it('allows earnings for an ACTIVE driver', async () => {
      await request(app.getHttpServer())
        .get('/api/v1/drivers/me/earnings')
        .set('Authorization', `Bearer ${driverA.token}`)
        .expect(HttpStatus.OK);
    });
  });

  describe('admin endpoints', () => {
    it('denies a passenger', async () => {
      await request(app.getHttpServer())
        .post(`/api/v1/drivers/admin/${driverPendingRecordId}/approve`)
        .set('Authorization', `Bearer ${passengerA.token}`)
        .expect(HttpStatus.FORBIDDEN)
        .expect((res) => {
          expect(res.body.code).toEqual(ErrorCode.AUTH_FORBIDDEN);
        });
    });

    it('denies a driver', async () => {
      await request(app.getHttpServer())
        .post(`/api/v1/drivers/admin/${driverPendingRecordId}/approve`)
        .set('Authorization', `Bearer ${driverA.token}`)
        .expect(HttpStatus.FORBIDDEN);
    });

    it('rejects a malformed driver id with 400', async () => {
      await request(app.getHttpServer())
        .post('/api/v1/drivers/admin/not-a-uuid/approve')
        .set('Authorization', `Bearer ${admin.token}`)
        .expect(HttpStatus.BAD_REQUEST)
        .expect((res) => {
          expect(res.body.code).toEqual(ErrorCode.VALIDATION_ERROR);
        });
    });

    it('returns 404 for an unknown driver id', async () => {
      await request(app.getHttpServer())
        .post('/api/v1/drivers/admin/00000000-0000-4000-8000-000000000000/approve')
        .set('Authorization', `Bearer ${admin.token}`)
        .expect(HttpStatus.NOT_FOUND)
        .expect((res) => {
          expect(res.body.code).toEqual(ErrorCode.DRIVER_NOT_FOUND);
        });
    });

    it('allows an ADMIN to approve a driver', async () => {
      const response = await request(app.getHttpServer())
        .post(`/api/v1/drivers/admin/${driverPendingRecordId}/approve`)
        .set('Authorization', `Bearer ${admin.token}`)
        .expect(HttpStatus.CREATED);

      expect(response.body.data.status).toEqual(DriverStatus.ACTIVE);
    });
  });

  describe('refresh tokens respect user status', () => {
    it('refuses to refresh for a suspended account and revokes the chain', async () => {
      statusCase = await register(UserRole.PASSENGER, 'status_case');

      await dataSource.query(`UPDATE users SET status = $1 WHERE id = $2`, [
        UserStatus.SUSPENDED,
        statusCase.id,
      ]);

      await request(app.getHttpServer())
        .post('/api/v1/auth/refresh')
        .send({ refreshToken: statusCase.refreshToken })
        .expect(HttpStatus.FORBIDDEN)
        .expect((res) => {
          expect(res.body.code).toEqual(ErrorCode.AUTH_USER_SUSPENDED);
        });

      // The status change also invalidated every session for that user.
      await request(app.getHttpServer())
        .post('/api/v1/auth/refresh')
        .send({ refreshToken: statusCase.refreshToken })
        .expect(HttpStatus.UNAUTHORIZED)
        .expect((res) => {
          expect(res.body.code).toEqual(ErrorCode.AUTH_REFRESH_TOKEN_REVOKED);
        });
    });
  });
});
