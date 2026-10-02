/**
 * Domain-specific error codes.
 *
 * Each code is a unique machine-readable string returned in error responses
 * so that Flutter can branch on error type without parsing human text.
 */
export enum ErrorCode {
  // Auth
  AUTH_INVALID_CREDENTIALS = 'AUTH_INVALID_CREDENTIALS',
  AUTH_USER_EXISTS = 'AUTH_USER_EXISTS',
  AUTH_TOKEN_EXPIRED = 'AUTH_TOKEN_EXPIRED',
  AUTH_TOKEN_INVALID = 'AUTH_TOKEN_INVALID',
  AUTH_REFRESH_TOKEN_INVALID = 'AUTH_REFRESH_TOKEN_INVALID',
  AUTH_REFRESH_TOKEN_EXPIRED = 'AUTH_REFRESH_TOKEN_EXPIRED',
  AUTH_REFRESH_TOKEN_REVOKED = 'AUTH_REFRESH_TOKEN_REVOKED',
  AUTH_FORBIDDEN = 'AUTH_FORBIDDEN',
  AUTH_UNAUTHORIZED = 'AUTH_UNAUTHORIZED',
  AUTH_USER_NOT_FOUND = 'AUTH_USER_NOT_FOUND',
  /** Credentials were valid, but the account has been suspended. */
  AUTH_USER_SUSPENDED = 'AUTH_USER_SUSPENDED',
  /** Credentials were valid, but the account is inactive. */
  AUTH_USER_INACTIVE = 'AUTH_USER_INACTIVE',
  /** Credentials were valid, but the account has not been activated yet. */
  AUTH_USER_PENDING = 'AUTH_USER_PENDING',
  /** Too many consecutive failed logins; the account is temporarily locked. */
  AUTH_ACCOUNT_LOCKED = 'AUTH_ACCOUNT_LOCKED',

  // Wallet
  WALLET_INSUFFICIENT_BALANCE = 'WALLET_INSUFFICIENT_BALANCE',
  WALLET_NOT_FOUND = 'WALLET_NOT_FOUND',
  WALLET_FROZEN = 'WALLET_FROZEN',
  /** The operation's currency does not match the wallet's currency. */
  CURRENCY_MISMATCH = 'CURRENCY_MISMATCH',

  // Trip
  TRIP_NOT_FOUND = 'TRIP_NOT_FOUND',
  TRIP_ALREADY_PAID = 'TRIP_ALREADY_PAID',
  TRIP_NOT_OWNED = 'TRIP_NOT_OWNED',
  /** The trip cannot be settled: cancelled, refunded, or missing its driver/fare. */
  TRIP_NOT_PAYABLE = 'TRIP_NOT_PAYABLE',

  // Payment
  PAYMENT_ALREADY_PROCESSED = 'PAYMENT_ALREADY_PROCESSED',
  PAYMENT_FAILED = 'PAYMENT_FAILED',
  PAYMENT_NOT_FOUND = 'PAYMENT_NOT_FOUND',
  /** The payment exists but belongs to a different passenger/driver. */
  PAYMENT_NOT_OWNED = 'PAYMENT_NOT_OWNED',

  // Fare / Tariff
  TARIFF_NOT_FOUND = 'TARIFF_NOT_FOUND',
  TARIFF_RULE_NOT_FOUND = 'TARIFF_RULE_NOT_FOUND',
  /** The requested tariff version identifier is already taken. Versions are never reused. */
  TARIFF_VERSION_EXISTS = 'TARIFF_VERSION_EXISTS',
  /** The requested lifecycle transition is not allowed from the tariff's current status. */
  TARIFF_STATUS_INVALID = 'TARIFF_STATUS_INVALID',
  /** validTo <= validFrom, or the window does not currently permit activation. */
  TARIFF_WINDOW_INVALID = 'TARIFF_WINDOW_INVALID',
  /** Another ACTIVE tariff already covers this window; regulators must expire it first. */
  TARIFF_WINDOW_OVERLAP = 'TARIFF_WINDOW_OVERLAP',
  /**
   * More than one rule matched a fare request equally well (same route, segment
   * containment, vehicle specificity and range width). Guessing would make the
   * fare non-deterministic, so the pricing configuration is rejected instead.
   */
  TARIFF_RULE_AMBIGUOUS = 'TARIFF_RULE_AMBIGUOUS',
  FARE_CALCULATION_FAILED = 'FARE_CALCULATION_FAILED',
  /** The client-quoted fare disagreed with the server-calculated official fare. */
  FARE_MISMATCH = 'FARE_MISMATCH',

  // Route
  ROUTE_NOT_FOUND = 'ROUTE_NOT_FOUND',
  ROUTE_INACTIVE = 'ROUTE_INACTIVE',
  STOP_NOT_FOUND = 'STOP_NOT_FOUND',
  STOP_ORDER_INVALID = 'STOP_ORDER_INVALID',

  // Driver
  DRIVER_NOT_ACTIVE = 'DRIVER_NOT_ACTIVE',
  DRIVER_NOT_FOUND = 'DRIVER_NOT_FOUND',

  // Passenger
  PASSENGER_NOT_FOUND = 'PASSENGER_NOT_FOUND',

  // Withdrawal
  WITHDRAWAL_INSUFFICIENT_BALANCE = 'WITHDRAWAL_INSUFFICIENT_BALANCE',
  WITHDRAWAL_NOT_FOUND = 'WITHDRAWAL_NOT_FOUND',

  // Vehicle
  VEHICLE_NOT_FOUND = 'VEHICLE_NOT_FOUND',
  /** The vehicle exists but is not operational (INACTIVE / MAINTENANCE). */
  VEHICLE_NOT_ACTIVE = 'VEHICLE_NOT_ACTIVE',
  /** The vehicle is registered to a different driver than the one on the trip. */
  VEHICLE_NOT_OWNED = 'VEHICLE_NOT_OWNED',
  /** The vehicle type does not match the type the trip/tariff was quoted for. */
  VEHICLE_TYPE_MISMATCH = 'VEHICLE_TYPE_MISMATCH',

  // General
  VALIDATION_ERROR = 'VALIDATION_ERROR',
  INTERNAL_ERROR = 'INTERNAL_ERROR',
  IDEMPOTENCY_CONFLICT = 'IDEMPOTENCY_CONFLICT',
}
