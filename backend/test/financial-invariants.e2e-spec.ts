/**
 * Financial invariants (e2e) — Phase 6 + Phase 7.
 *
 * Runs the real AppModule against the configured PostgreSQL database, so each
 * assertion is really about the whole path: routing, guards, validation, the
 * service layer, the wallet mutation mechanism, the ledger and the database
 * constraints that back all of them.
 *
 * The suite is deliberately about *money*, not about endpoints:
 *
 *   - a trip settles at most once, even under concurrent requests
 *   - a failed payment leaves a durable, readable attempt and no money moved
 *   - every balance change has exactly one matching ledger entry
 *   - replayed top-up confirmations and withdrawal requests move money once
 *   - receipt numbers are unique and sequence-derived
 *
 * Fixtures are prefixed `fin_` (accounts) / `FIN-E2E-` (tariff versions) so the
 * cleanup cannot touch another suite's data. Whatever tariff was ACTIVE in the
 * shared development database is parked during the run and restored afterwards.
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
  PaymentRecordStatus,
  PaymentStatus,
  UserRole,
  VehicleStatus,
} from '../src/common/enums';
import { ErrorCode } from '../src/common/error-codes';
import { GlobalExceptionFilter } from '../src/common/filters/global-exception.filter';
import { deleteLedgerEntries } from './utils/ledger-cleanup';

describe('Financial invariants (e2e)', () => {
  let app: NestFastifyApplication;
  let dataSource: DataSource;

  const suffix = Date.now().toString(36);
  const password = 'password123';
  const prefix = 'fin_';
  const usernamePattern = `^${prefix}`;
  const VERSION_PREFIX = 'FIN-E2E-';
  const ROUTE_CODE = `FIN-${suffix}`;
  const FARE = 1250;

  interface Account {
    id: string;
    username: string;
    token: string;
  }

  let admin: Account;
  let passenger: Account;
  let brokePassenger: Account;
  let driver: Account;
  let routeId: string;
  let originStopId: string;
  let destinationStopId: string;
  let vehicleId: string;
  let parkedTariffId: string | undefined;

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
        fullName: `Fin ${name}`,
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

  const auth = (account: Account) => `Bearer ${account.token}`;

  const getBalance = async (account: Account): Promise<number> => {
    const response = await request(app.getHttpServer())
      .get('/api/v1/wallet')
      .set('Authorization', auth(account))
      .expect(HttpStatus.OK);
    return response.body.data.balance;
  };

  const createTrip = async (account: Account = passenger): Promise<string> => {
    const response = await request(app.getHttpServer())
      .post('/api/v1/trips')
      .set('Authorization', auth(account))
      .send({
        driverId: driver.id,
        vehicleId,
        routeId,
        originStopId,
        destinationStopId,
        origin: 'Fin Origin',
        destination: 'Fin Terminus',
      })
      .expect(HttpStatus.CREATED);
    return response.body.data.id;
  };

  const pay = (account: Account, tripId: string, key: string) =>
    request(app.getHttpServer())
      .post('/api/v1/payments/trip')
      .set('Authorization', auth(account))
      .send({ tripId, idempotencyKey: key });

  const ledgerRowsForReference = (referenceId: string) =>
    dataSource.query(
      `SELECT "walletId", "transactionId", "entryType", direction, amount,
              "balanceBefore", "balanceAfter", "referenceType", "referenceId"
         FROM ledger_entries WHERE "referenceId" = $1 ORDER BY "entryType"`,
      [referenceId],
    );

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
    brokePassenger = await register(UserRole.PASSENGER, 'broke');
    driver = await register(UserRole.DRIVER, 'driver', {
      licenseNumber: `FIN-${suffix}`,
    });
    await dataSource.query(`UPDATE drivers SET status = $1 WHERE "userId" = $2`, [
      DriverStatus.ACTIVE,
      driver.id,
    ]);

    const [vehicleRow] = await dataSource.query(
      `INSERT INTO vehicles ("plateNumber", status, "driverId")
       VALUES ($1, $2, $3) RETURNING id`,
      [`FIN-${suffix}`, VehicleStatus.ACTIVE, driver.id],
    );
    vehicleId = vehicleRow.id;

    // ADMIN accounts are never self-registerable; insert the fixture directly
    // and then authenticate through the real login path.
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
      .set('Authorization', auth(admin))
      .send({
        name: `Financial Route ${suffix}`,
        code: ROUTE_CODE,
        origin: 'Fin Origin',
        destination: 'Fin Terminus',
        stops: [
          { name: 'Fin Origin', sequence: 1, latitude: 9.01, longitude: 38.76 },
          { name: 'Fin Midpoint', sequence: 2, latitude: 9.02, longitude: 38.77 },
          { name: 'Fin Terminus', sequence: 3, latitude: 9.03, longitude: 38.78 },
        ],
      })
      .expect(HttpStatus.CREATED);

    routeId = routeResponse.body.data.id;
    const stops = routeResponse.body.data.stops as {
      id: string;
      sequence: number;
    }[];
    originStopId = stops.find((stop) => stop.sequence === 1)!.id;
    destinationStopId = stops.find((stop) => stop.sequence === 3)!.id;

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

    const tariffResponse = await request(app.getHttpServer())
      .post('/api/v1/tariffs')
      .set('Authorization', auth(admin))
      .send({
        version: `${VERSION_PREFIX}${suffix.toUpperCase()}`,
        name: `Financial schedule ${suffix}`,
        validFrom: new Date(Date.now() - 60_000).toISOString(),
        rules: [
          {
            routeId,
            vehicleType: 'MINIBUS',
            startStopSequence: 1,
            endStopSequence: 3,
            basePrice: FARE,
          },
        ],
      })
      .expect(HttpStatus.CREATED);

    await request(app.getHttpServer())
      .post(`/api/v1/tariffs/${tariffResponse.body.data.id}/activate`)
      .set('Authorization', auth(admin))
      .expect(HttpStatus.CREATED);
  });

  afterAll(async () => {
    if (dataSource?.isInitialized) {
      // Owner columns differ in type across tables (`wallets."userId"` is uuid,
      // `payments."passengerId"` is varchar), and PostgreSQL does not compare
      // uuid to varchar implicitly — each statement names the matching form.
      const inUsersUuid = `SELECT id FROM users WHERE username ~ $1`;
      const inUsersText = `SELECT id FROM users WHERE username ~ $1`;

      await deleteLedgerEntries(
        dataSource,
        `DELETE FROM ledger_entries WHERE "walletId" IN (SELECT id FROM wallets WHERE "userId" IN (${inUsersUuid}))`,
        [usernamePattern],
      );
      await dataSource.query(
        `DELETE FROM payments WHERE "passengerId" IN (${inUsersText}) OR "driverId" IN (${inUsersText})`,
        [usernamePattern],
      );
      await dataSource.query(
        `DELETE FROM top_up_intents WHERE "userId" IN (${inUsersUuid})`,
        [usernamePattern],
      );
      await dataSource.query(
        `DELETE FROM withdrawals WHERE "userId" IN (${inUsersText})`,
        [usernamePattern],
      );
      await dataSource.query(
        `DELETE FROM wallets WHERE "userId" IN (${inUsersUuid})`,
        [usernamePattern],
      );
      await dataSource.query(
        `DELETE FROM trips WHERE "passengerId" IN (${inUsersText}) OR "driverId" IN (${inUsersText})`,
        [usernamePattern],
      );
      await dataSource.query(
        `DELETE FROM vehicles WHERE "driverId" IN (${inUsersText}) OR "plateNumber" LIKE 'FIN-%'`,
        [usernamePattern],
      );
      await dataSource.query(
        `DELETE FROM passengers WHERE "userId" IN (${inUsersUuid})`,
        [usernamePattern],
      );
      await dataSource.query(
        `DELETE FROM drivers WHERE "userId" IN (${inUsersUuid})`,
        [usernamePattern],
      );
      await dataSource.query(`DELETE FROM users WHERE username ~ $1`, [
        usernamePattern,
      ]);
      await dataSource.query(`DELETE FROM tariffs WHERE version LIKE $1`, [
        `${VERSION_PREFIX}%`,
      ]);
      await dataSource.query(`DELETE FROM routes WHERE code = $1`, [ROUTE_CODE]);

      if (parkedTariffId) {
        await dataSource.query(
          `UPDATE tariffs SET status = 'ACTIVE' WHERE id = $1 AND "validFrom" <= now() AND ("validTo" IS NULL OR "validTo" >= now())`,
          [parkedTariffId],
        );
      }
    }
    await app?.close();
  });

  describe('wallet and ledger invariants', () => {
    it('credits a top-up exactly once, even when the confirmation is replayed', async () => {
      const before = await getBalance(passenger);

      const initiated = await request(app.getHttpServer())
        .post('/api/v1/wallet/top-up')
        .set('Authorization', auth(passenger))
        .send({ amount: 100_000, idempotencyKey: `fin-topup-${suffix}` })
        .expect(HttpStatus.CREATED);

      const intentId = initiated.body.data.intentId;

      const first = await request(app.getHttpServer())
        .post(`/api/v1/wallet/top-up/${intentId}/confirm`)
        .set('Authorization', auth(passenger))
        .expect(HttpStatus.CREATED);
      expect(first.body.data.balance).toBe(before + 100_000);

      // A replayed confirmation must be an idempotent success, not a second credit.
      const replay = await request(app.getHttpServer())
        .post(`/api/v1/wallet/top-up/${intentId}/confirm`)
        .set('Authorization', auth(passenger))
        .expect(HttpStatus.CREATED);
      expect(replay.body.data.balance).toBe(before + 100_000);

      expect(await getBalance(passenger)).toBe(before + 100_000);

      const rows = await dataSource.query(
        `SELECT direction, amount, "balanceBefore", "balanceAfter"
           FROM ledger_entries le
           JOIN wallets w ON w.id = le."walletId"
          WHERE w."userId" = $1::uuid AND le."referenceType" = 'TOP_UP'`,
        [passenger.id],
      );
      expect(rows).toHaveLength(1);
      expect(rows[0]).toMatchObject({
        direction: 'CREDIT',
        amount: 100_000,
        balanceBefore: before,
        balanceAfter: before + 100_000,
      });
    });

    it.each([0, -5000, 12.5])(
      'rejects a non-positive or fractional top-up amount (%p)',
      async (amount) => {
        const response = await request(app.getHttpServer())
          .post('/api/v1/wallet/top-up')
          .set('Authorization', auth(passenger))
          .send({ amount, idempotencyKey: `fin-bad-${amount}-${suffix}` });

        expect(response.status).toBe(HttpStatus.BAD_REQUEST);
        expect(response.body.code).toBe(ErrorCode.VALIDATION_ERROR);
      },
    );

    it('treats the same top-up key with a different amount as a conflict', async () => {
      const key = `fin-conflict-${suffix}`;
      await request(app.getHttpServer())
        .post('/api/v1/wallet/top-up')
        .set('Authorization', auth(passenger))
        .send({ amount: 5_000, idempotencyKey: key })
        .expect(HttpStatus.CREATED);

      const conflict = await request(app.getHttpServer())
        .post('/api/v1/wallet/top-up')
        .set('Authorization', auth(passenger))
        .send({ amount: 9_000, idempotencyKey: key })
        .expect(HttpStatus.CONFLICT);

      expect(conflict.body.code).toBe(ErrorCode.IDEMPOTENCY_CONFLICT);
    });

    it('CRITICAL: PostgreSQL refuses a wallet balance below zero', async () => {
      const [wallet] = await dataSource.query(
        `SELECT id FROM wallets WHERE "userId" = $1::uuid`,
        [passenger.id],
      );

      await expect(
        dataSource.query(`UPDATE wallets SET balance = -1 WHERE id = $1`, [
          wallet.id,
        ]),
      ).rejects.toMatchObject({ code: '23514' });
    });

    it('CRITICAL: PostgreSQL refuses a ledger row whose arithmetic does not hold', async () => {
      const [wallet] = await dataSource.query(
        `SELECT id FROM wallets WHERE "userId" = $1::uuid`,
        [passenger.id],
      );

      // DEBIT of 100 that claims the balance went *up* by 100.
      await expect(
        dataSource.query(
          `INSERT INTO ledger_entries ("walletId", "entryType", direction, amount, "balanceBefore", "balanceAfter")
           VALUES ($1, 'ADJUSTMENT', 'DEBIT', 100, 0, 100)`,
          [wallet.id],
        ),
      ).rejects.toMatchObject({ code: '23514' });
    });

    it('CRITICAL: PostgreSQL refuses to UPDATE, DELETE or TRUNCATE ledger rows', async () => {
      const [wallet] = await dataSource.query(
        `SELECT id FROM wallets WHERE "userId" = $1::uuid`,
        [passenger.id],
      );
      const reference = `fin-append-only-${suffix}`;
      const [entry] = await dataSource.query(
        `INSERT INTO ledger_entries ("walletId", "entryType", direction, amount, "balanceBefore", "balanceAfter", "referenceType", "referenceId")
         VALUES ($1, 'ADJUSTMENT', 'CREDIT', 100, 0, 100, 'PROBE', $2) RETURNING id`,
        [wallet.id, reference],
      );

      await expect(
        dataSource.query(
          `UPDATE ledger_entries SET amount = 1, "balanceAfter" = 1 WHERE id = $1`,
          [entry.id],
        ),
      ).rejects.toMatchObject({ code: '23001' });
      await expect(
        dataSource.query(`DELETE FROM ledger_entries WHERE id = $1`, [entry.id]),
      ).rejects.toMatchObject({ code: '23001' });
      await expect(
        dataSource.query(`TRUNCATE ledger_entries`),
      ).rejects.toMatchObject({ code: '23001' });

      await deleteLedgerEntries(
        dataSource,
        `DELETE FROM ledger_entries WHERE id = $1`,
        [entry.id],
      );
    });

    it('CRITICAL: PostgreSQL refuses a payment for a trip that does not exist', async () => {
      await expect(
        dataSource.query(
          `INSERT INTO payments ("tripId", "passengerId", "driverId", amount, "idempotencyKey")
           VALUES (gen_random_uuid(), $1, $1, 100, $2)`,
          [passenger.id, `fin-orphan-${suffix}`],
        ),
      ).rejects.toMatchObject({ code: '23503' });
    });

    it('CRITICAL: PostgreSQL refuses a second movement for the same wallet reference', async () => {
      const [wallet] = await dataSource.query(
        `SELECT id FROM wallets WHERE "userId" = $1::uuid`,
        [passenger.id],
      );
      const reference = `fin-ledger-dup-${suffix}`;

      await dataSource.query(
        `INSERT INTO ledger_entries ("walletId", "entryType", direction, amount, "balanceBefore", "balanceAfter", "referenceType", "referenceId")
         VALUES ($1, 'ADJUSTMENT', 'CREDIT', 100, 0, 100, 'PROBE', $2)`,
        [wallet.id, reference],
      );

      await expect(
        dataSource.query(
          `INSERT INTO ledger_entries ("walletId", "entryType", direction, amount, "balanceBefore", "balanceAfter", "referenceType", "referenceId")
           VALUES ($1, 'ADJUSTMENT', 'CREDIT', 100, 100, 200, 'PROBE', $2)`,
          [wallet.id, reference],
        ),
      ).rejects.toMatchObject({ code: '23505' });

      await deleteLedgerEntries(
        dataSource,
        `DELETE FROM ledger_entries WHERE "referenceId" = $1`,
        [reference],
      );
    });

    it('refuses two top-up intents sharing one provider reference', async () => {
      const reference = `fin-provider-ref-${suffix}`;
      const [wallet] = await dataSource.query(
        `SELECT id FROM wallets WHERE "userId" = $1::uuid`,
        [passenger.id],
      );
      expect(wallet).toBeDefined();

      await dataSource.query(
        `INSERT INTO top_up_intents ("userId", "amountMinor", provider, status, "idempotencyKey", "providerReference")
         VALUES ($1, 100, 'MOCK', 'SUCCESS', $2, $3)`,
        [passenger.id, `fin-ref-a-${suffix}`, reference],
      );

      await expect(
        dataSource.query(
          `INSERT INTO top_up_intents ("userId", "amountMinor", provider, status, "idempotencyKey", "providerReference")
           VALUES ($1, 100, 'MOCK', 'SUCCESS', $2, $3)`,
          [passenger.id, `fin-ref-b-${suffix}`, reference],
        ),
      ).rejects.toMatchObject({ code: '23505' });

      await dataSource.query(
        `DELETE FROM top_up_intents WHERE "providerReference" = $1`,
        [reference],
      );
    });
  });

  describe('trip payment invariants', () => {
    it('CRITICAL: concurrent payment attempts settle the trip exactly once', async () => {
      const tripId = await createTrip();

      const passengerBefore = await getBalance(passenger);
      const driverBefore = await getBalance(driver);

      // Same trip, two different idempotency keys, at the same time.
      const [first, second] = await Promise.all([
        pay(passenger, tripId, `fin-race-a-${suffix}`),
        pay(passenger, tripId, `fin-race-b-${suffix}`),
      ]);

      const statuses = [first.status, second.status].sort();
      expect(statuses.filter((status) => status === HttpStatus.OK)).toHaveLength(1);
      // The loser is told the trip is already paid — a deterministic conflict,
      // never a second charge and never a 500.
      expect(statuses.filter((status) => status === HttpStatus.CONFLICT)).toHaveLength(1);
      expect(statuses).toEqual([HttpStatus.OK, HttpStatus.CONFLICT]);

      const successful = first.status === HttpStatus.OK ? first : second;
      const losing = first.status === HttpStatus.OK ? second : first;
      expect(losing.body.code).toBe(ErrorCode.TRIP_ALREADY_PAID);

      // Exactly one successful payment.
      const payments = await dataSource.query(
        `SELECT id, status, amount, currency, "receiptNumber" FROM payments WHERE "tripId" = $1`,
        [tripId],
      );
      const successes = payments.filter(
        (payment: { status: string }) => payment.status === 'SUCCESS',
      );
      expect(successes).toHaveLength(1);
      expect(successes[0].id).toBe(successful.body.data.paymentId);
      expect(successes[0].amount).toBe(FARE);
      expect(successes[0].currency).toBe('ETB');
      expect(successes[0].receiptNumber).toMatch(/^SEM-\d{4}-\d{6}$/);

      // Exactly one passenger debit and one driver credit for this trip.
      const ledger = await ledgerRowsForReference(tripId);
      expect(ledger).toHaveLength(2);
      const debit = ledger.find((row: any) => row.direction === 'DEBIT');
      const credit = ledger.find((row: any) => row.direction === 'CREDIT');
      expect(debit).toMatchObject({
        entryType: 'TRIP_PAYMENT',
        amount: FARE,
        balanceBefore: passengerBefore,
        balanceAfter: passengerBefore - FARE,
        transactionId: successes[0].id,
      });
      expect(credit).toMatchObject({
        entryType: 'DRIVER_EARNING',
        amount: FARE,
        balanceBefore: driverBefore,
        balanceAfter: driverBefore + FARE,
        transactionId: successes[0].id,
      });

      // The wallets moved exactly once, in opposite directions, by the same amount.
      expect(await getBalance(passenger)).toBe(passengerBefore - FARE);
      expect(await getBalance(driver)).toBe(driverBefore + FARE);

      // And the trip is settled.
      const [trip] = await dataSource.query(
        `SELECT status, "paymentStatus", "paymentId" FROM trips WHERE id = $1`,
        [tripId],
      );
      expect(trip.paymentStatus).toBe(PaymentStatus.PAID);
      expect(trip.status).toBe('COMPLETED');
      expect(trip.paymentId).toBe(successes[0].id);
    });

    it('replays the same idempotency key as the same payment, with no second charge', async () => {
      const tripId = await createTrip();
      const key = `fin-idem-${suffix}`;

      const first = await pay(passenger, tripId, key).expect(HttpStatus.OK);
      const passengerAfterFirst = await getBalance(passenger);

      const replay = await pay(passenger, tripId, key).expect(HttpStatus.OK);

      expect(replay.body.data.paymentId).toBe(first.body.data.paymentId);
      expect(replay.body.data.receiptNumber).toBe(first.body.data.receiptNumber);
      expect(await getBalance(passenger)).toBe(passengerAfterFirst);
      expect(await ledgerRowsForReference(tripId)).toHaveLength(2);
    });

    it('rejects the same key used for a different trip', async () => {
      const firstTrip = await createTrip();
      const secondTrip = await createTrip();
      const key = `fin-idem-conflict-${suffix}`;

      await pay(passenger, firstTrip, key).expect(HttpStatus.OK);

      const conflict = await pay(passenger, secondTrip, key).expect(
        HttpStatus.CONFLICT,
      );
      expect(conflict.body.code).toBe(ErrorCode.IDEMPOTENCY_CONFLICT);
      expect(await ledgerRowsForReference(secondTrip)).toHaveLength(0);
    });

    it('refuses a second payment for an already-paid trip', async () => {
      const tripId = await createTrip();
      await pay(passenger, tripId, `fin-once-a-${suffix}`).expect(HttpStatus.OK);

      const again = await pay(passenger, tripId, `fin-once-b-${suffix}`).expect(
        HttpStatus.CONFLICT,
      );
      expect(again.body.code).toBe(ErrorCode.TRIP_ALREADY_PAID);
      expect(await ledgerRowsForReference(tripId)).toHaveLength(2);
    });

    it('CRITICAL: insufficient balance moves no money and leaves a durable failed attempt', async () => {
      const tripId = await createTrip(brokePassenger);

      const failed = await pay(
        brokePassenger,
        tripId,
        `fin-broke-${suffix}`,
      ).expect(HttpStatus.BAD_REQUEST);
      expect(failed.body.code).toBe(ErrorCode.WALLET_INSUFFICIENT_BALANCE);

      // No money moved, and the trip is still unpaid.
      expect(await getBalance(brokePassenger)).toBe(0);
      expect(await ledgerRowsForReference(tripId)).toHaveLength(0);
      const [trip] = await dataSource.query(
        `SELECT "paymentStatus" FROM trips WHERE id = $1`,
        [tripId],
      );
      expect(trip.paymentStatus).toBe(PaymentStatus.UNPAID);

      // The attempt survives as a FAILED row rather than vanishing with the
      // rolled-back transaction.
      const attempts = await dataSource.query(
        `SELECT status, "failureReason" FROM payments WHERE "tripId" = $1`,
        [tripId],
      );
      expect(attempts).toHaveLength(1);
      expect(attempts[0].status).toBe(PaymentRecordStatus.FAILED);
      expect(attempts[0].failureReason).toBe(
        ErrorCode.WALLET_INSUFFICIENT_BALANCE,
      );
    });

    it('does not let a passenger pay for another passenger’s trip', async () => {
      const tripId = await createTrip();

      const forbidden = await pay(
        brokePassenger,
        tripId,
        `fin-foreign-${suffix}`,
      ).expect(HttpStatus.FORBIDDEN);
      expect(forbidden.body.code).toBe(ErrorCode.TRIP_NOT_OWNED);
      expect(await ledgerRowsForReference(tripId)).toHaveLength(0);
    });

    it('rejects a missing or malformed idempotency key', async () => {
      const tripId = await createTrip();

      const response = await request(app.getHttpServer())
        .post('/api/v1/payments/trip')
        .set('Authorization', auth(passenger))
        .send({ tripId })
        .expect(HttpStatus.BAD_REQUEST);
      expect(response.body.code).toBe(ErrorCode.VALIDATION_ERROR);
      expect(await ledgerRowsForReference(tripId)).toHaveLength(0);
    });
  });

  describe('withdrawal invariants', () => {
    it('replays the same withdrawal request instead of debiting twice', async () => {
      const driverBefore = await getBalance(driver);
      const key = `fin-wd-${suffix}`;
      const body = {
        amount: 500,
        destinationType: 'BANK',
        destination: 'Commercial Bank of Ethiopia',
        destinationAccount: `fin-acct-${suffix}`,
        idempotencyKey: key,
      };

      const first = await request(app.getHttpServer())
        .post('/api/v1/drivers/me/withdrawals')
        .set('Authorization', auth(driver))
        .send(body)
        .expect(HttpStatus.CREATED);

      const replay = await request(app.getHttpServer())
        .post('/api/v1/drivers/me/withdrawals')
        .set('Authorization', auth(driver))
        .send(body)
        .expect(HttpStatus.CREATED);

      expect(replay.body.data.id).toBe(first.body.data.id);
      expect(await getBalance(driver)).toBe(driverBefore - 500);

      const rows = await dataSource.query(
        `SELECT COUNT(*)::int AS n FROM ledger_entries le
           JOIN wallets w ON w.id = le."walletId"
          WHERE w."userId" = $1::uuid AND le."entryType" = 'WITHDRAWAL' AND le."referenceId" = $2`,
        [driver.id, first.body.data.id],
      );
      expect(rows[0].n).toBe(1);
    });

    it('rejects a reused withdrawal key with a different payload', async () => {
      const key = `fin-wd-conflict-${suffix}`;
      const base = {
        amount: 100,
        destinationType: 'BANK',
        destinationAccount: `fin-acct-a-${suffix}`,
        idempotencyKey: key,
      };

      await request(app.getHttpServer())
        .post('/api/v1/drivers/me/withdrawals')
        .set('Authorization', auth(driver))
        .send(base)
        .expect(HttpStatus.CREATED);

      const conflict = await request(app.getHttpServer())
        .post('/api/v1/drivers/me/withdrawals')
        .set('Authorization', auth(driver))
        .send({ ...base, amount: 999 })
        .expect(HttpStatus.CONFLICT);

      expect(conflict.body.code).toBe(ErrorCode.IDEMPOTENCY_CONFLICT);
    });

    it.each([0, -100, 5.5])(
      'rejects a non-positive or fractional withdrawal amount (%p)',
      async (amount) => {
        const response = await request(app.getHttpServer())
          .post('/api/v1/drivers/me/withdrawals')
          .set('Authorization', auth(driver))
          .send({
            amount,
            destinationType: 'BANK',
            idempotencyKey: `fin-wd-bad-${amount}-${suffix}`,
          });

        expect(response.status).toBe(HttpStatus.BAD_REQUEST);
        expect(response.body.code).toBe(ErrorCode.VALIDATION_ERROR);
      },
    );

    it('refuses a withdrawal beyond the available balance', async () => {
      const balance = await getBalance(driver);
      const response = await request(app.getHttpServer())
        .post('/api/v1/drivers/me/withdrawals')
        .set('Authorization', auth(driver))
        .send({
          amount: balance + 100_000,
          destinationType: 'BANK',
          idempotencyKey: `fin-wd-over-${suffix}`,
        })
        .expect(HttpStatus.BAD_REQUEST);

      expect(response.body.code).toBe(
        ErrorCode.WITHDRAWAL_INSUFFICIENT_BALANCE,
      );
      expect(await getBalance(driver)).toBe(balance);
    });
  });
});
