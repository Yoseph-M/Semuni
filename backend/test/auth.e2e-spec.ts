/**
 * Auth integration tests.
 *
 * Boots the real AppModule against the configured PostgreSQL database, so this
 * suite exercises the actual routing, validation pipe and persistence contract
 * rather than mocks. It mirrors main.ts (global prefix + validation) because
 * e2e tests bypass bootstrap().
 *
 * Every run uses uniquely-suffixed usernames and deletes what it created, so it
 * is safe to run repeatedly against a shared database.
 */
import { Test, TestingModule } from '@nestjs/testing';
import { ValidationPipe, HttpStatus } from '@nestjs/common';
import {
  FastifyAdapter,
  NestFastifyApplication,
} from '@nestjs/platform-fastify';
import * as request from 'supertest';
import { DataSource } from 'typeorm';
import { AppModule } from '../src/app.module';
import { UserRole, UserStatus } from '../src/common/enums';
import { ErrorCode } from '../src/common/error-codes';
import { deleteLedgerEntries } from './utils/ledger-cleanup';

describe('Auth (e2e)', () => {
  let app: NestFastifyApplication;
  let dataSource: DataSource;
  let accessToken: string;
  let refreshToken: string;
  let rotatedRefreshToken: string;

  // Unique per run so repeated runs never collide in a shared database.
  const suffix = Date.now().toString(36);
  const passengerUsername = `e2e_passenger_${suffix}`;
  const driverUsername = `e2e_driver_${suffix}`;
  const password = 'password123';

  const passengerRegister = {
    username: passengerUsername,
    fullName: 'E2E Passenger',
    password,
    role: UserRole.PASSENGER,
  };

  const driverRegister = {
    username: driverUsername,
    fullName: 'E2E Driver',
    password,
    role: UserRole.DRIVER,
    licenseNumber: 'E2E-LIC-001',
  };

  beforeAll(async () => {
    // Note: the auth-endpoint rate limits are raised for this run via
    // test/throttle-test-env.ts (loaded by jest setupFiles), because the suite
    // makes far more auth calls than a human would.
    const moduleFixture: TestingModule = await Test.createTestingModule({
      imports: [AppModule],
    }).compile();

    app = moduleFixture.createNestApplication<NestFastifyApplication>(
      new FastifyAdapter(),
    );
    // Mirror main.ts — the API contract under test includes these two.
    app.setGlobalPrefix('api/v1');
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
  });

  afterAll(async () => {
    // Leave the shared database exactly as we found it.
    if (dataSource?.isInitialized) {
      // Every account this suite creates is prefixed `e2e_`, so cleanup is a
      // single prefix match (refresh_sessions cascade from users).
      const prefix = '^e2e_';
      await deleteLedgerEntries(
        dataSource,
        `DELETE FROM ledger_entries WHERE "walletId" IN (
           SELECT w.id FROM wallets w JOIN users u ON u.id = w."userId"
           WHERE u.username ~ $1
         )`,
        [prefix],
      );
      await dataSource.query(
        `DELETE FROM wallets WHERE "userId" IN (SELECT id FROM users WHERE username ~ $1)`,
        [prefix],
      );
      await dataSource.query(
        `DELETE FROM passengers WHERE "userId" IN (SELECT id FROM users WHERE username ~ $1)`,
        [prefix],
      );
      await dataSource.query(
        `DELETE FROM drivers WHERE "userId" IN (SELECT id FROM users WHERE username ~ $1)`,
        [prefix],
      );
      await dataSource.query(`DELETE FROM users WHERE username ~ $1`, [
        prefix,
      ]);
    }
    await app?.close();
  });

  it('POST /auth/register — registers a passenger and issues tokens', async () => {
    const response = await request(app.getHttpServer())
      .post('/api/v1/auth/register')
      .send(passengerRegister)
      .expect(HttpStatus.CREATED);

    expect(response.body.data.accessToken).toBeDefined();
    expect(response.body.data.refreshToken).toBeDefined();
    // The password hash must never cross the wire.
    expect(response.body.data.passwordHash).toBeUndefined();

    accessToken = response.body.data.accessToken;
    refreshToken = response.body.data.refreshToken;
  });

  it('POST /auth/register — rejects a duplicate username', async () => {
    await request(app.getHttpServer())
      .post('/api/v1/auth/register')
      .send(passengerRegister)
      .expect(HttpStatus.CONFLICT)
      .expect((res) => {
        expect(res.body.code).toEqual(ErrorCode.AUTH_USER_EXISTS);
      });
  });

  it('POST /auth/register — rejects a phone-only body (login is username-based)', async () => {
    await request(app.getHttpServer())
      .post('/api/v1/auth/register')
      .send({
        phone: '+251911000999',
        fullName: 'Legacy Client',
        password,
        role: UserRole.PASSENGER,
      })
      .expect(HttpStatus.BAD_REQUEST);
  });

  it('POST /auth/login — authenticates with username and password', async () => {
    const response = await request(app.getHttpServer())
      .post('/api/v1/auth/login')
      .send({ username: passengerUsername, password, role: UserRole.PASSENGER })
      .expect(HttpStatus.OK);

    expect(response.body.data.accessToken).toBeDefined();
    expect(response.body.data.refreshToken).toBeDefined();
    // The documented contract returns the non-sensitive identity alongside tokens.
    expect(response.body.data.user.role).toEqual(UserRole.PASSENGER);
    expect(response.body.data.user.id).toBeDefined();
    accessToken = response.body.data.accessToken;
    refreshToken = response.body.data.refreshToken;
  });

  it('POST /auth/login — rejects a wrong password', async () => {
    await request(app.getHttpServer())
      .post('/api/v1/auth/login')
      .send({
        username: passengerUsername,
        password: 'not-the-password',
        role: UserRole.PASSENGER,
      })
      .expect(HttpStatus.UNAUTHORIZED)
      .expect((res) => {
        expect(res.body.code).toEqual(ErrorCode.AUTH_INVALID_CREDENTIALS);
      });
  });

  it('POST /auth/login — rejects a mismatched role', async () => {
    await request(app.getHttpServer())
      .post('/api/v1/auth/login')
      .send({ username: passengerUsername, password, role: UserRole.DRIVER })
      .expect(HttpStatus.UNAUTHORIZED);
  });

  it('POST /auth/login — locks the account after repeated failed passwords', async () => {
    const username = `e2e_lockout_${suffix}`;
    await request(app.getHttpServer())
      .post('/api/v1/auth/register')
      .send({ ...passengerRegister, username })
      .expect(HttpStatus.CREATED);

    const attempt = (pw: string) =>
      request(app.getHttpServer())
        .post('/api/v1/auth/login')
        .send({ username, password: pw, role: UserRole.PASSENGER });

    for (let i = 0; i < 5; i++) {
      await attempt('wrong-password').expect(HttpStatus.UNAUTHORIZED);
    }
    // Locked: even the correct password is refused until the lock expires.
    await attempt(password)
      .expect(HttpStatus.TOO_MANY_REQUESTS)
      .expect((res) => {
        expect(res.body.code).toEqual(ErrorCode.AUTH_ACCOUNT_LOCKED);
      });

    await dataSource.query(
      `UPDATE users SET "lockedUntil" = now() - interval '1 minute' WHERE username = $1`,
      [username],
    );
    await attempt(password).expect(HttpStatus.OK);
    const [row] = await dataSource.query(
      `SELECT "failedLoginAttempts", "lockedUntil" FROM users WHERE username = $1`,
      [username],
    );
    expect(row).toEqual({ failedLoginAttempts: 0, lockedUntil: null });
  });

  it('GET /auth/me — returns the current user without the password hash', async () => {
    const response = await request(app.getHttpServer())
      .get('/api/v1/auth/me')
      .set('Authorization', `Bearer ${accessToken}`)
      .expect(HttpStatus.OK);

    expect(response.body.data.username).toEqual(passengerUsername);
    expect(response.body.data.role).toEqual(UserRole.PASSENGER);
    expect(response.body.data.passwordHash).toBeUndefined();
  });

  it('GET /auth/me — rejects a missing token', async () => {
    await request(app.getHttpServer())
      .get('/api/v1/auth/me')
      .expect(HttpStatus.UNAUTHORIZED);
  });

  it('POST /auth/refresh — rotates the refresh token', async () => {
    const response = await request(app.getHttpServer())
      .post('/api/v1/auth/refresh')
      .send({ refreshToken })
      .expect(HttpStatus.OK);

    expect(response.body.data.accessToken).toBeDefined();
    expect(response.body.data.refreshToken).toBeDefined();

    rotatedRefreshToken = response.body.data.refreshToken;
    // Rotation means a genuinely new credential, not the same one echoed back.
    expect(rotatedRefreshToken).not.toEqual(refreshToken);
  });

  it('POST /auth/refresh — rejects a malformed refresh token', async () => {
    await request(app.getHttpServer())
      .post('/api/v1/auth/refresh')
      .send({ refreshToken: 'not-a-real-token' })
      .expect(HttpStatus.UNAUTHORIZED)
      .expect((res) => {
        expect(res.body.code).toEqual(ErrorCode.AUTH_REFRESH_TOKEN_INVALID);
      });
  });

  it('POST /auth/logout — revokes the supplied refresh session', async () => {
    await request(app.getHttpServer())
      .post('/api/v1/auth/logout')
      .set('Authorization', `Bearer ${accessToken}`)
      .send({ refreshToken: rotatedRefreshToken })
      .expect(HttpStatus.OK);

    // The revoked refresh token can no longer be exchanged for tokens.
    await request(app.getHttpServer())
      .post('/api/v1/auth/refresh')
      .send({ refreshToken: rotatedRefreshToken })
      .expect(HttpStatus.UNAUTHORIZED)
      .expect((res) => {
        expect(res.body.code).toEqual(ErrorCode.AUTH_REFRESH_TOKEN_REVOKED);
      });
  });

  it('POST /auth/refresh — rejects reuse of an already-rotated token', async () => {
    // `refreshToken` was consumed by the rotation test above; presenting it
    // again is the token-reuse signal and must be refused.
    await request(app.getHttpServer())
      .post('/api/v1/auth/refresh')
      .send({ refreshToken })
      .expect(HttpStatus.UNAUTHORIZED)
      .expect((res) => {
        expect(res.body.code).toEqual(ErrorCode.AUTH_REFRESH_TOKEN_REVOKED);
      });
  });

  it('POST /auth/register — registers a driver when a licence is supplied', async () => {
    await request(app.getHttpServer())
      .post('/api/v1/auth/register')
      .send(driverRegister)
      .expect(HttpStatus.CREATED);
  });

  it('POST /auth/register — rejects a driver with no licence', async () => {
    await request(app.getHttpServer())
      .post('/api/v1/auth/register')
      .send({
        username: `${driverUsername}_nolicence`,
        fullName: 'No Licence',
        password,
        role: UserRole.DRIVER,
      })
      .expect(HttpStatus.BAD_REQUEST);
  });

  it('POST /auth/login — authenticates the driver', async () => {
    await request(app.getHttpServer())
      .post('/api/v1/auth/login')
      .send({ username: driverUsername, password, role: UserRole.DRIVER })
      .expect(HttpStatus.OK);
  });

  it('POST /auth/register — refuses to self-register an ADMIN', async () => {
    const adminUsername = `${passengerUsername}_admin`;

    await request(app.getHttpServer())
      .post('/api/v1/auth/register')
      .send({
        username: adminUsername,
        fullName: 'Sneaky Admin',
        password,
        role: UserRole.ADMIN,
      })
      .expect(HttpStatus.BAD_REQUEST);

    // Nothing may be persisted for the rejected attempt.
    const created = await dataSource.query(
      'SELECT id FROM users WHERE username = $1',
      [adminUsername],
    );
    expect(created).toHaveLength(0);
  });

  it('POST /auth/register — enforces the minimum password length', async () => {
    await request(app.getHttpServer())
      .post('/api/v1/auth/register')
      .send({
        username: `e2e_shortpw_${suffix}`,
        fullName: 'Short Password',
        password: 'short',
        role: UserRole.PASSENGER,
      })
      .expect(HttpStatus.BAD_REQUEST);
  });

  it('denies login and invalidates existing tokens for non-ACTIVE accounts', async () => {
    const cases: Array<{ status: UserStatus; code: ErrorCode }> = [
      { status: UserStatus.SUSPENDED, code: ErrorCode.AUTH_USER_SUSPENDED },
      { status: UserStatus.INACTIVE, code: ErrorCode.AUTH_USER_INACTIVE },
      // Policy: a PENDING account is denied until an operator activates it.
      { status: UserStatus.PENDING, code: ErrorCode.AUTH_USER_PENDING },
    ];

    for (const { status, code } of cases) {
      const username = `e2e_status_${status.toLowerCase()}_${suffix}`;

      const register = await request(app.getHttpServer())
        .post('/api/v1/auth/register')
        .send({
          username,
          fullName: 'Status Case',
          password,
          role: UserRole.PASSENGER,
        })
        .expect(HttpStatus.CREATED);

      const tokenBeforeStatusChange = register.body.data.accessToken as string;

      await dataSource.query(
        'UPDATE users SET status = $1 WHERE username = $2',
        [status, username],
      );

      await request(app.getHttpServer())
        .post('/api/v1/auth/login')
        .send({ username, password, role: UserRole.PASSENGER })
        .expect(HttpStatus.FORBIDDEN)
        .expect((res) => {
          expect(res.body.code).toEqual(code);
        });

      // A token issued before the status change must stop working immediately.
      await request(app.getHttpServer())
        .get('/api/v1/auth/me')
        .set('Authorization', `Bearer ${tokenBeforeStatusChange}`)
        .expect(HttpStatus.FORBIDDEN);
    }
  });
});
