# semuni

semuni is a digital fare, wallet, payment and settlement platform for Ethiopia's
minibus taxi network. Passengers pay fares from a wallet; drivers receive
earnings, see settlements and request withdrawals.

## Repository layout

```
.
├── backend/          NestJS 11 (Fastify) API — PostgreSQL, TypeORM migrations
│   ├── src/          domain modules: auth, wallets, ledger, payments, trips, …
│   └── test/         e2e suites (run against a real PostgreSQL)
├── lib/              Flutter app (package `smuni`): screens → repositories → services
├── test/             Flutter unit, widget and integration tests
└── android/ ios/ linux/ macos/ web/ windows/   Flutter platform runners
```

## Quick start

### Backend

See [`backend/README.md`](backend/README.md) for the full guide. In short:

```bash
cd backend
cp .env.example .env            # then set JWT_ACCESS_SECRET / JWT_REFRESH_SECRET
docker compose up -d postgres
npm ci
npm run migration:run
npm run start:dev               # http://localhost:3000, docs at /api/docs
```

### Flutter app

```bash
flutter pub get
flutter run --dart-define=SMUNI_API_BASE=http://localhost:3000
```

On the Android emulator the default API base is `http://10.0.2.2:3000`.

## Tests

```bash
# backend
cd backend
npm run lint:ci
npx tsc --noEmit
npm test                         # unit
npm run test:e2e                 # needs PostgreSQL + migrations
npm run verify:financial -- --strict          # read-only integrity report
npm run verify:financial -- --probe --strict  # DB constraint probes (rolled back)

# app
flutter analyze
flutter test
```

Backend CI (`.github/workflows/backend.yml`) runs all of the backend checks
above against a PostgreSQL service on every pull request that touches `backend/`.

## Git hooks

`npm ci` in `backend/` installs a Husky pre-commit hook that lints staged
backend TypeScript files with `--max-warnings=0`.
