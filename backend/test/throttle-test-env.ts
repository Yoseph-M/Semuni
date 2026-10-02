/**
 * Loaded via `setupFiles` before the test file's imports, so these values are
 * already in place when the `@Throttle` decorators on AuthController evaluate.
 *
 * The e2e suite legitimately makes far more auth requests than a human would
 * (it registers several accounts and hammers refresh), so the production-tight
 * auth limits are raised for the test run only. The limiter itself is verified
 * against a live server using the real defaults.
 *
 * Suites run serially (`maxWorkers: 1`) because they all boot the real app
 * against one shared database: parallel workers contend for the same remote
 * connection and can time out during setup, and a suite that temporarily
 * changes shared state (e.g. which tariff is active) must not overlap with
 * another suite's assertions.
 */
process.env.AUTH_THROTTLE_REGISTER_LIMIT ??= '1000';
process.env.AUTH_THROTTLE_LOGIN_LIMIT ??= '1000';
process.env.AUTH_THROTTLE_REFRESH_LIMIT ??= '1000';

// The global limiter is shared by every suite (and Jest runs suites in
// parallel workers, all appearing to come from one client), so the production
// default of 100 requests/minute is exhausted by the suite itself and surfaces
// as an unrelated 429. Raised for the test run only — the limiter's real
// behaviour is verified against a live server with the production defaults.
process.env.THROTTLE_LIMIT ??= '100000';
