/**
 * Development seed data.
 *
 * Creates one ADMIN, one PASSENGER, one DRIVER, a minibus assigned to that
 * driver, three sample routes with stops, and one active tariff with a rule per
 * route. Everything is idempotent — re-running it is a no-op.
 *
 * ⚠️  The routes and tariff below are SAMPLE DATA invented for development.
 * They are NOT official Ethiopian fare schedules and must never be presented as
 * such. Real tariffs must be entered by an administrator from the official
 * gazette/regulator.
 *
 * Credentials are NOT hardcoded. Passwords are read from the environment:
 *
 *   SEED_ADMIN_PASSWORD  SEED_PASSENGER_PASSWORD  SEED_DRIVER_PASSWORD
 *
 * If one is missing, a random password is generated and printed once so the
 * repository never carries a committed credential. Usernames can be overridden
 * with SEED_ADMIN_USERNAME / SEED_PASSENGER_USERNAME / SEED_DRIVER_USERNAME.
 *
 * Run with:  npm run seed:dev
 */
import 'reflect-metadata';
import { NestFactory } from '@nestjs/core';
import { randomBytes } from 'crypto';
import { AppModule } from '../../app.module';
import { AuthService } from '../../auth/auth.service';
import { UsersService } from '../../users/users.service';
import { VehiclesService } from '../../vehicles/vehicles.service';
import { RoutesService } from '../../routes/routes.service';
import { TariffsService } from '../../tariffs/tariffs.service';
import { Currency, TariffStatus, UserRole, VehicleType } from '../../common/enums';
import { RegisterDto } from '../../auth/dto/auth.dto';
import { CreateRouteDto } from '../../routes/dto/route.dto';
import { CreateTariffDto } from '../../tariffs/dto/tariff.dto';

const envOr = (key: string, fallback: string): string =>
  process.env[key]?.trim() || fallback;

/** Never commit a credential: take it from the environment or invent one. */
function resolvePassword(key: string, label: string): string {
  const provided = process.env[key]?.trim();
  if (provided) return provided;

  const generated = randomBytes(12).toString('base64url');
  console.log(
    `[seed] 🔑 ${label}: generated password (set ${key} to control it) => ${generated}`,
  );
  return generated;
}

/**
 * Ensures an account exists, tolerating an existing one so re-runs are safe.
 *
 * ADMIN accounts cannot go through the public registration endpoint — it
 * deliberately refuses that role so nobody can self-promote — so the seeding
 * path creates them directly. Registration is still used for passengers and
 * drivers because it also creates their role profile transactionally.
 */
async function upsertUser(
  authService: AuthService,
  usersService: UsersService,
  account: RegisterDto,
): Promise<void> {
  const existing = await usersService.findByUsername(account.username);
  if (existing) {
    console.log(`[seed] ↩️  ${account.username} already exists — skipped`);
    return;
  }

  if (account.role === UserRole.ADMIN) {
    await usersService.create({
      username: account.username,
      // UsersService hashes the password before persisting it.
      passwordHash: account.password,
      role: UserRole.ADMIN,
    });
    console.log(`[seed] ✅ created ADMIN ${account.username}`);
    return;
  }

  try {
    await authService.register(account);
    console.log(`[seed] ✅ created ${account.role} ${account.username}`);
  } catch (err: unknown) {
    const message = String((err as Error)?.message ?? err).toLowerCase();
    if (message.includes('already exists')) {
      console.log(`[seed] ↩️  ${account.username} already exists — skipped`);
      return;
    }
    throw err;
  }
}

const SAMPLE_ROUTES: CreateRouteDto[] = [
  {
    name: 'Bole – Piazza',
    origin: 'Bole',
    destination: 'Piazza',
    code: 'SAMPLE-01',
    stops: [
      { name: 'Bole', sequence: 1, latitude: 8.9944, longitude: 38.7994 },
      { name: 'Meskel Square', sequence: 2, latitude: 9.0107, longitude: 38.7612 },
      { name: 'Piazza', sequence: 3, latitude: 9.0341, longitude: 38.7516 },
    ],
  },
  {
    name: 'Megenagna – Merkato',
    origin: 'Megenagna',
    destination: 'Merkato',
    code: 'SAMPLE-02',
    stops: [
      { name: 'Megenagna', sequence: 1, latitude: 9.0192, longitude: 38.8023 },
      { name: 'Saris', sequence: 2, latitude: 8.9896, longitude: 38.7701 },
      { name: 'Merkato', sequence: 3, latitude: 9.0345, longitude: 38.7407 },
    ],
  },
  {
    name: 'Kality – Meskel Square',
    origin: 'Kality',
    destination: 'Meskel Square',
    code: 'SAMPLE-03',
    stops: [
      { name: 'Kality', sequence: 1, latitude: 8.9247, longitude: 38.7701 },
      { name: 'Gotera', sequence: 2, latitude: 8.9946, longitude: 38.7612 },
      { name: 'Meskel Square', sequence: 3, latitude: 9.0107, longitude: 38.7612 },
    ],
  },
];

// Indicative SAMPLE fares in santim (minor units). Not official values.
const SAMPLE_FARES_SANTIM = [8500, 7000, 12000];

// Stable sample version so re-running the seed is idempotent. Versions are
// never reused, so the real regulator schedule must use a different one.
const SAMPLE_TARIFF_VERSION = 'TARIFF-SAMPLE-V1';

async function main(): Promise<void> {
  const app = await NestFactory.createApplicationContext(AppModule, {
    logger: ['error', 'warn'],
  });

  try {
    const authService = app.get(AuthService);
    const usersService = app.get(UsersService);
    const vehiclesService = app.get(VehiclesService);
    const routesService = app.get(RoutesService);
    const tariffsService = app.get(TariffsService);

    // ─── Users ────────────────────────────────────────────
    const adminUsername = envOr('SEED_ADMIN_USERNAME', 'admin');
    const passengerUsername = envOr('SEED_PASSENGER_USERNAME', 'passenger');
    const driverUsername = envOr('SEED_DRIVER_USERNAME', 'driver');

    await upsertUser(authService, usersService, {
      username: adminUsername,
      fullName: 'Development Admin',
      password: resolvePassword('SEED_ADMIN_PASSWORD', 'admin'),
      role: UserRole.ADMIN,
    });

    await upsertUser(authService, usersService, {
      username: passengerUsername,
      fullName: 'Development Passenger',
      password: resolvePassword('SEED_PASSENGER_PASSWORD', 'passenger'),
      role: UserRole.PASSENGER,
    });

    await upsertUser(authService, usersService, {
      username: driverUsername,
      fullName: 'Development Driver',
      password: resolvePassword('SEED_DRIVER_PASSWORD', 'driver'),
      role: UserRole.DRIVER,
      licenseNumber: 'DEV-LICENSE-0001',
    });

    // ─── Vehicle (assigned to the driver user) ────────────
    const driverUser = await usersService.findByUsername(driverUsername);
    if (!driverUser) {
      throw new Error('Driver user was not created; aborting seed');
    }

    const existingVehicle = await vehiclesService.findByDriverId(driverUser.id);
    if (existingVehicle) {
      console.log(
        `[seed] ↩️  vehicle ${existingVehicle.plateNumber} already assigned — skipped`,
      );
    } else {
      const vehicle = await vehiclesService.create({
        plateNumber: 'DEV-12345',
        vehicleType: VehicleType.MINIBUS,
        capacity: 12,
        driverId: driverUser.id,
      });
      console.log(`[seed] ✅ created vehicle ${vehicle.plateNumber}`);
    }

    // ─── Routes ───────────────────────────────────────────
    const existingRoutes = await routesService.findAll();
    const byCode = new Map(existingRoutes.map((r) => [r.code, r]));
    const resolvedRoutes: { id: string; code: string }[] = [];

    for (const route of SAMPLE_ROUTES) {
      const found = byCode.get(route.code);
      if (found) {
        console.log(`[seed] ↩️  route ${route.code} already exists — skipped`);
        resolvedRoutes.push({ id: found.id, code: found.code });
        continue;
      }
      const created = await routesService.create(route);
      console.log(`[seed] ✅ created route ${created.code} (${created.name})`);
      resolvedRoutes.push({ id: created.id, code: created.code });
    }

    // ─── Tariff ───────────────────────────────────────────
    // Tariffs are created in DRAFT and only price fares once explicitly
    // activated, so the seed must do both steps.
    const allTariffs = await tariffsService.findAll();
    let sampleTariff = allTariffs.find(
      (tariff) => tariff.version === SAMPLE_TARIFF_VERSION,
    );

    if (sampleTariff) {
      console.log(
        `[seed] ↩️  tariff ${SAMPLE_TARIFF_VERSION} already exists — skipped creation`,
      );
    } else {
      const tariffDto: CreateTariffDto = {
        version: SAMPLE_TARIFF_VERSION,
        // Named to make clear this is not an official schedule.
        name: 'Sample Tariff (development only)',
        validFrom: new Date().toISOString(),
        currency: Currency.ETB,
        rules: resolvedRoutes.map((route, index) => ({
          routeId: route.id,
          vehicleType: VehicleType.MINIBUS,
          basePrice: SAMPLE_FARES_SANTIM[index % SAMPLE_FARES_SANTIM.length],
        })),
      };
      sampleTariff = await tariffsService.create(tariffDto);
      console.log(
        `[seed] ✅ created tariff "${sampleTariff.version}" with ${resolvedRoutes.length} rule(s)`,
      );
    }

    if (sampleTariff.status === TariffStatus.ACTIVE) {
      console.log(
        `[seed] ↩️  tariff ${sampleTariff.version} is already active — skipped`,
      );
    } else {
      try {
        const activated = await tariffsService.activate(sampleTariff.id);
        console.log(`[seed] ✅ activated tariff ${activated.version}`);
      } catch (err) {
        // A real regulator tariff may already be live; the sample must never
        // displace it, so a conflict is reported rather than forced through.
        console.log(
          `[seed] ⚠️  could not activate ${sampleTariff.version}: ${err.message}`,
        );
      }
    }

    console.log(
      '[seed] Done. Sample routes/fares are development data, not official schedules.',
    );
  } finally {
    await app.close();
  }
}

main().catch((err) => {
  console.error('[seed] FAILED:', err);
  process.exit(1);
});
