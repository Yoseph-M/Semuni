/**
 * Loaded via `setupFiles` before the test file's imports, so these values are
 * already in place when the `@Throttle` decorators on AuthController evaluate.
 *
 * The e2e suite legitimately makes far more auth requests than a human would
 * (it registers several accounts and hammers refresh), so the production-tight
 * auth limits are raised for the test run only. The limiter itself is verified
 * against a live server using the real defaults.
 */
process.env.AUTH_THROTTLE_REGISTER_LIMIT ??= '1000';
process.env.AUTH_THROTTLE_LOGIN_LIMIT ??= '1000';
process.env.AUTH_THROTTLE_REFRESH_LIMIT ??= '1000';
