# Semuni Backend

Semuni is a digital fare, wallet, payment, and settlement platform for Ethiopia's minibus taxi transportation network. This backend provides a robust, idempotent, and transactional foundation for managing passengers, drivers, routes, tariffs, and financial operations.

## Architecture

The application is built using **NestJS** (with Fastify) as a modular monolith. 

Key architectural highlights:
- **Fastify**: Used as the underlying HTTP adapter for maximum performance.
- **TypeORM**: Handles database interactions with PostgreSQL.
- **Modular Monolith**: The business logic is separated into distinct domains (Modules):
  - `Auth`: Handles JWT-based authentication and role-based access control.
  - `Passengers` / `Drivers` / `Vehicles`: Core user and asset management.
  - `Routes` / `Tariffs` / `Fares`: Configuration and calculation of dynamic pricing based on distance/stops.
  - `Wallets` / `Ledger` / `Payments`: The financial core, using pessimistic locking and double-entry accounting to ensure zero data anomalies.
  - `Withdrawals` / `Settlements`: Handles driver cash-outs. Batch settlement is triggered explicitly by an admin via `POST /settlements/process` (no background timers: a process restart must never lose or mutate financial state).
  - `Trips`: Aggregates the journey details resulting from a successful payment.
  - `Notifications`: Stubs for sending Push and SMS notifications.

- **Idempotency**: Payment, withdrawal and top-up endpoints require an `idempotencyKey` to prevent double charging on retries. Keys are scoped to their owner (`(ownerId, idempotencyKey)`), so one user's key can never resolve to another user's operation.
- **Financial Integrity**: All wallet balance changes and ledger entries occur within strict PostgreSQL transactions. Minor units (e.g., santim) are used for all currency values to avoid floating-point errors.

## Getting Started

### Prerequisites
- Node.js (v18 or higher)
- Docker & Docker Compose (for the PostgreSQL database)

### Installation

1. Copy `.env.example` to `.env`:
   ```bash
   cp .env.example .env
   ```
2. Install dependencies:
   ```bash
   npm install
   ```

### Running the Database

**Local Homebrew PostgreSQL (this machine):** Postgres is already listening on `127.0.0.1:5432`. Create a role and database that match `.env` / `docker-compose.yml`:

```bash
psql -d postgres -c "CREATE ROLE semuni LOGIN PASSWORD 'semuni_dev_password';"
psql -d postgres -c "CREATE DATABASE semuni OWNER semuni;"
```

**Docker Compose:** start only the database service (stop anything else bound to 5432, or change the host port in `docker-compose.yml`):

```bash
docker compose up -d postgres
```

Do not point local development at a remote pooler unless `DB_USERNAME` and `DB_PASSWORD` are a real Postgres role and password. A JWT or service-role key is not a database password and will fail with `password authentication failed for user "postgres"`.

### First run on a new machine (`JWT_ACCESS_SECRET` does not exist)

`.env` is deliberately **not** committed — it holds credentials — so a fresh
clone has no database or JWT configuration, and `npm run start` fails with:

```
TypeError: Configuration key "JWT_ACCESS_SECRET" does not exist
    at ConfigService.getOrThrow (...\@nestjs\config\dist\config.service.js)
    at InstanceWrapper.useFactory (...\src\auth\auth.module.ts)
```

That error means exactly one thing: the process found no `.env` in `backend/`
(ConfigModule reads `envFilePath: ['.env']`, which is resolved relative to the
**working directory**), or the file exists but lacks `JWT_ACCESS_SECRET` /
`JWT_REFRESH_SECRET`.

Fix it on the new machine:

1. Create `backend/.env` **next to `package.json`** (`cp .env.example .env`).
2. Fill in at minimum:

   | Key | Notes |
   | --- | --- |
   | `DB_HOST`, `DB_PORT`, `DB_DATABASE`, `DB_USERNAME`, `DB_PASSWORD` | a reachable PostgreSQL instance (local Docker or a Supabase pooler) |
   | `JWT_ACCESS_SECRET` | random, ≥32 chars |
   | `JWT_REFRESH_SECRET` | random, ≥32 chars, **different** from the access secret |
   | `SEED_*_PASSWORD` | optional, only used by `npm run seed:dev` |

   Generate secrets with `openssl rand -hex 32`, or on Windows with
   `node -e "console.log(require('crypto').randomBytes(32).toString('hex'))"`.
3. Run `npm run migration:run` once, then `npm run start:prod` (or
   `npm run start:dev`) **from `backend/`**, because the `.env` path is relative
   to the working directory.

### Running the Application

```bash
# Development mode
npm run start:dev

# Production build
npm run build
npm run start:prod
```

### Creating a User

The database is the single source of truth for identities, and no credentials are
checked into this repository. For local development fixtures there is an optional
seed (`npm run seed:dev`) that creates an admin, a passenger and a driver plus a
sample route and tariff. Every seed password comes from `SEED_*_PASSWORD` (with a
random one-off fallback that is printed once), never from source. The seed runs
repeatedly without duplicating data, publishes its sample tariff as
`TARIFF-SAMPLE-V1` and activates it — and refuses to displace a schedule that is
already active, so it can never override a real regulator tariff.

**Login is by `username`; `phone` is an optional contact detail.** Create an
account through the real registration endpoint — it hashes the password with
bcrypt and provisions the matching passenger/driver profile row atomically (in a
single transaction, so a failure cannot leave an orphaned user):

```bash
curl -X POST http://localhost:3000/api/v1/auth/register \
  -H 'Content-Type: application/json' \
  -d '{"username":"testpassenger","fullName":"Test Passenger","password":"<choose-a-password>","phone":"+251911000001","role":"PASSENGER"}'
```

Then sign in with the username:

```bash
curl -X POST http://localhost:3000/api/v1/auth/login \
  -H 'Content-Type: application/json' \
  -d '{"username":"testpassenger","password":"<choose-a-password>","role":"PASSENGER"}'
```

Drivers must additionally supply a `licenseNumber`. A passenger's wallet is created lazily the first time their wallet or profile is requested.

### Identity model (deliberate deviation)

Some specifications written for this project describe `phone` as the *primary*
login identifier (`POST /auth/login` with `{ phone, password }`). This
implementation **deliberately deviates**: it keeps a single, role-agnostic
`username` as the login handle and treats `phone` as a unique but **optional**
contact field.

Consequences worth knowing:

* `users.username` is `NOT NULL UNIQUE`; `users.phone` is nullable and unique when present.
* Phone numbers are **not** normalized, so `+251911000001` and `0911000001` are
  currently distinct values. If phone ever becomes an identifier, one
  normalization strategy must be introduced first.
* Login must include a `role` that matches the account's role — this is how a
  single `/auth/login` endpoint serves passengers, drivers and admins without
  separate endpoints.

### Token lifecycle

* **Access token** — JWT (HS256), `JWT_ACCESS_EXPIRES_IN` (default 15m), claims `sub` + `role` only.
* **Refresh token** — separate secret (`JWT_REFRESH_SECRET`), default 7d. Each issued token is
  persisted in `refresh_sessions` as a SHA-256 hash, keyed by its `jti`.
* **Rotation** — exchanging a refresh token revokes it and issues a new one; refresh tokens are single-use.
* **Reuse detection** — presenting an already-revoked token revokes *every* session for that user.
* **Logout** — revokes the supplied refresh session, or all of the caller's sessions when none is supplied.

Account status is re-checked on every request, so suspending a user takes effect immediately rather
than when their access token expires, and a refresh token issued before a suspension cannot be
exchanged for new tokens (the whole session chain is revoked instead). Only `ACTIVE` accounts may
authenticate; `PENDING`, `SUSPENDED` and `INACTIVE` are refused with `AUTH_USER_PENDING` /
`AUTH_USER_SUSPENDED` / `AUTH_USER_INACTIVE`.

### Authorization policy

Authentication proves *who* the caller is; it never proves they may touch a particular object. Every
lookup therefore goes through an ownership-aware service method (`findByIdForUser` on trips and
payments, scoped queries for history endpoints) rather than handing a raw `findById` to a controller.

* **Trips** — the owning passenger and the assigned driver may read a trip; any other authenticated
  user gets `403 TRIP_NOT_OWNED`. `ADMIN` has an explicit privileged branch.
* **Payments** — only the paying passenger, the paid driver, or `ADMIN` may read a payment. Responses
  omit provider internals (`providerReference`) and `idempotencyKey`.
* **Withdrawals** — driver-only at the route (`@Roles(DRIVER)`) *and* in the service
  (`WithdrawalsService.assertOperationalDriver`): a caller must be a `DRIVER` user with a driver
  profile whose status is `ACTIVE`. A passenger can never initiate or list a withdrawal, and a second
  driver can never see the first driver's history.
* **Drivers** — `user.status = ACTIVE` (re-checked per request) **and** `driver.status = ACTIVE` are
  both required for operational surfaces (`/drivers/me/earnings`, `/drivers/me/transactions`,
  withdrawals, and being selected as a trip driver). The profile itself stays readable so a `PENDING`
  driver's app can show the status.
* **Vehicles** — a trip may only use an existing, `ACTIVE` vehicle that is assigned to the driver
  operating the trip: `VEHICLE_NOT_FOUND` (404), `VEHICLE_NOT_ACTIVE` (400), `VEHICLE_NOT_OWNED`
  (403), `VEHICLE_TYPE_MISMATCH` (400).
* **IDs** — every `:id` route parameter is UUID-validated (`ParseUUIDPipe`), so a malformed id is
  `400 VALIDATION_ERROR` instead of a database error.

**Disclosure policy:** a resource that exists but belongs to someone else returns `403` with a
`*_NOT_OWNED` code; a resource that does not exist returns `404`. Clients branch on `code`, never on
`message`.

### Idempotency ownership

An idempotency key belongs to the user who created it, not to the whole database. Payment, withdrawal
and top-up keys are stored and looked up as `(ownerId, idempotencyKey)` — enforced by unique database
indexes — so one user's key can never return, block, or alias another user's operation.

Replaying the *same* request returns the same stored operation. Reusing a key with a *different*
payload (another trip, amount or destination) is refused with `409 IDEMPOTENCY_CONFLICT`; it is never
silently treated as the first request, and it never moves money.

### Running Tests

```bash
npm run test        # unit tests
npm run test:e2e    # integration tests (boots the real app against PostgreSQL)
```

The e2e suites all boot the real application against the same configured
database, so they run **serially** (`maxWorkers: 1`): parallel workers contend for
the same connections and can time out during setup, and a suite that temporarily
changes shared state — `tariff.e2e-spec.ts` parks and restores whichever tariff is
active — must not overlap with another suite's assertions. Timeouts are generous
because the development database may be a remote, shared instance; a local
PostgreSQL makes the suite markedly faster and less variable.

The unit suite covers idempotency checks (including key ownership and payload
conflicts), tariff lifecycle and rule-precedence decisions, and strict
transactional bounds for financial operations. The e2e suites boot the real app
against the configured database and clean up after themselves:
`auth.e2e-spec.ts` covers registration, login, rotation, reuse detection, logout
and account status; `authorization.e2e-spec.ts` covers object-level authorization
on trips and payments, driver-only withdrawals, the driver operational-status
policy, vehicle ownership, admin-only endpoints, idempotency conflicts and UUID
validation; and `tariff.e2e-spec.ts` covers the tariff lifecycle, deterministic
pricing and the immutability of a historical trip's fare.

### API Documentation

Swagger API documentation is available at:
`http://localhost:3000/api/docs` (when running locally).

## Money representation

All monetary values are integers in **minor units (santim)**, never floating point.
`ETB 85.00` is stored and transported as `8500`. Every amount is accompanied by a
`currency` field, which is `ETB` by default. Converting to a display value is the
client's job (`balance / 100`).

The server is the only source of truth for a fare: it is derived from the active
tariff, never accepted from the client.

## Tariff lifecycle and fare calculation

A tariff is a regulator-controlled price schedule identified by an immutable
`version` label (for example `TARIFF-2026-001`). The version is unique and never
reused; `name` is descriptive only. A newly created tariff is stored as `DRAFT`
and prices nothing until an administrator activates it, so inserting a row can
never change what a ride costs.

| Operation | Endpoint | Effect (all require `ADMIN`) |
| --- | --- | --- |
| create | `POST /tariffs` | stores a new `DRAFT` version |
| read | `GET /tariffs/:id` | returns one version with its rules |
| activate | `POST /tariffs/:id/activate` | `DRAFT → ACTIVE` |
| expire | `POST /tariffs/:id/expire` | `DRAFT`/`ACTIVE → EXPIRED` |

* Only an `ACTIVE` tariff whose validity window currently covers *now* may price a
  fare (`GET /tariffs/active`). A `DRAFT` or `EXPIRED` version is never used, and
  neither is an `ACTIVE` one whose window has not opened or has already closed.
* **At most one tariff may be `ACTIVE`.** Activating a second one over an
  overlapping window is refused with `409 TARIFF_WINDOW_OVERLAP`; the incumbent
  must be expired first, which is an explicit regulator decision. The rule is
  enforced in the application *and* in PostgreSQL — a partial unique index
  (`UQ_tariffs_single_active`), with activation serialised by an advisory lock so
  concurrent admin requests cannot both win. A schedule whose window has already
  closed is retired automatically at activation time.
* Creation rejects an inverted window (`TARIFF_WINDOW_INVALID`), an empty rule
  set, non-integer/zero/negative minor-unit prices, impossible or unknown stop
  ranges, and rules pointing at inactive routes — all before anything is stored.
* A tariff that has already priced a trip is immutable: a database trigger
  refuses price edits to its rules, so a change means publishing a new version.

### Deterministic fare calculation

The fare is computed server-side from `routeId`, `originStopId` and
`destinationStopId` (plus an optional `vehicleType`) — never from client-supplied
text, and never from a client-supplied amount.

1. the route must be `ACTIVE` and both stops must belong to it (`STOP_NOT_FOUND`);
2. the origin stop must precede the destination stop (`STOP_ORDER_INVALID`) —
   reverse-direction travel is not a valid fare;
3. matching rules must be scoped to the route, contain the requested segment in
   the travel direction, and be compatible with the requested vehicle type;
4. candidates are ranked deterministically: a rule naming the requested vehicle
   type beats a generic rule, then a narrower stop range beats a broader one;
5. if two rules remain equally applicable the request is rejected with
   `409 TARIFF_RULE_AMBIGUOUS` instead of being resolved by row order.

### Trip fare snapshots

A trip preserves everything needed to reconstruct its price without consulting the
current tariff: `tariffId`, `tariffVersion`, `tariffRuleId`, `routeId`,
`originStopId`, `destinationStopId`, `fareAmount`, `currency` and the route/stop
name snapshots. Activating a new version therefore never changes what a historical
trip cost. If a client does send `fareAmount`, it is accepted only when it equals
the server's calculation — otherwise `400 FARE_MISMATCH`, and the stored fare is
always the server's.

## Main Passenger-Driver Payment Flow

1. **Seed or create the parties** — `npm run seed:dev` (see above) or
   `POST /auth/register` with `role: DRIVER` (plus `licenseNumber`) and `role: PASSENGER`.
2. **Admin approves the driver** — `POST /drivers/admin/:id/approve`. Trips cannot be
   created against a driver who is not `ACTIVE`.
3. **Login** — `POST /auth/login` with `{ username, password, role }`; keep `accessToken`.
3a. **Find the driver to pay (passenger)** — `GET /drivers/available` returns only `ACTIVE`
   drivers, and only what a passenger needs to identify the minibus they are riding in:
   `{ driverUserId, fullName, vehiclePlate, vehicleType }`. `driverUserId` is the
   `driverId` that `POST /trips` expects.
4. **Fund the passenger wallet** — top-up is a two-step flow because money entering
   the platform cannot be taken on the client's word:
   ```bash
   # 4a. initiate -> returns a PENDING intent, wallet balance is NOT changed
   curl -X POST $API/wallet/top-up -H "Authorization: Bearer $PAX" \
     -H 'Content-Type: application/json' \
     -d '{"amount":100000,"idempotencyKey":"topup-1"}'

   # 4b. confirm -> verifies with the provider, then credits exactly once
   curl -X POST $API/wallet/top-up/$INTENT_ID/confirm -H "Authorization: Bearer $PAX"
   ```
   A provider callback may instead arrive at `POST /wallet/webhooks/:provider` with
   `{ "providerReference": "..." }`. Both paths are idempotent.
5. **Create the trip** — `POST /trips` with `driverId`, `origin`, `destination` and
   optionally `vehicleType`. **Do not send an amount.** The backend resolves the route,
   reads the active tariff and stores the authoritative fare. If you do send
   `fareAmount` it must equal the server's figure, otherwise the request is rejected
   with `FARE_MISMATCH`.
6. **Pay the trip** — `POST /payments/trip` with `{ tripId, idempotencyKey }`. Only the
   server-stored fare is ever debited.

Step 6 runs as a single PostgreSQL transaction that validates ownership and balance,
creates the payment, debits the passenger, credits the driver, writes both ledger
entries and marks the trip PAID — all or nothing. Repeating it with the same
`idempotencyKey` returns the original payment and never charges twice; the key is
scoped to that passenger, and reusing it for a different trip is rejected with
`IDEMPOTENCY_CONFLICT`.

```
Passenger wallet --DEBIT 8500--> Trip payment --CREDIT 8500--> Driver wallet
        100000 -> 91500                        0 -> 8500
```

## Operations

Probes, scheduled jobs (top-up reconciliation, notification dispatch, integrity checks), Telebirr setup, logs, audit trail and incident steps: see [docs/RUNBOOK.md](docs/RUNBOOK.md).

## Payment providers

The wallet core depends only on the `PaymentProviderGateway` port
(`src/payments/providers/payment-provider.gateway.ts`). The implementation is chosen
from `PAYMENT_PROVIDER` (default `MOCK`, refused in production). `MockPaymentProvider`
performs no network calls and holds no credentials. `TelebirrPaymentProvider`
implements Telebirr H5 C2B web checkout (signed preOrder/queryOrder, RSA-verified
notifications); configure it with the `TELEBIRR_*` variables in `.env.example`.
Telebirr withdrawals and Chapa are not implemented — the registry raises an error
rather than silently falling back to the mock provider, which would fake a settlement.
