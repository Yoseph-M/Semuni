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
  - `Withdrawals` / `Settlements`: Handles driver cash-outs. Settlements processing is automated via a nightly `@Cron` job that batches pending withdrawals.
  - `Trips`: Aggregates the journey details resulting from a successful payment.
  - `Notifications`: Stubs for sending Push and SMS notifications.

- **Idempotency**: The `/payments` endpoint requires an `idempotencyKey` to prevent double charging on retries.
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
random one-off fallback that is printed once), never from source.

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
than when their access token expires. Only `ACTIVE` accounts may authenticate; `PENDING`, `SUSPENDED`
and `INACTIVE` are refused with `AUTH_USER_PENDING` / `AUTH_USER_SUSPENDED` / `AUTH_USER_INACTIVE`.

### Running Tests

```bash
npm run test        # unit tests
npm run test:e2e    # integration tests (boots the real app against PostgreSQL)
```

The unit suite covers idempotency checks and strict transactional bounds for
financial operations. The e2e suite exercises the real routing/validation/
persistence contract — including auth, refresh-token rotation and revocation —
against the configured database, and cleans up after itself.

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

## Main Passenger-Driver Payment Flow

1. **Seed or create the parties** — `npm run seed:dev` (see above) or
   `POST /auth/register` with `role: DRIVER` (plus `licenseNumber`) and `role: PASSENGER`.
2. **Admin approves the driver** — `POST /drivers/admin/:id/approve`. Trips cannot be
   created against a driver who is not `ACTIVE`.
3. **Login** — `POST /auth/login` with `{ username, password, role }`; keep `accessToken`.
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
`idempotencyKey` returns the original payment and never charges twice.

```
Passenger wallet --DEBIT 8500--> Trip payment --CREDIT 8500--> Driver wallet
        100000 -> 91500                        0 -> 8500
```

## Payment providers

The wallet core depends only on the `PaymentProviderGateway` port
(`src/payments/providers/payment-provider.gateway.ts`). The implementation is chosen
from `PAYMENT_PROVIDER` (default `MOCK`). `MockPaymentProvider` performs no network
calls and holds no credentials. Telebirr/Chapa are intentionally not implemented —
the registry raises an error rather than silently falling back to the mock provider,
which would fake a settlement.
