/**
 * Domain enumerations shared across modules.
 *
 * Every enum is intentionally string-valued so that
 * PostgreSQL stores readable text rather than opaque integers.
 */

// ─── User / Auth ─────────────────────────────────────────

export enum UserRole {
  PASSENGER = 'PASSENGER',
  DRIVER = 'DRIVER',
  ADMIN = 'ADMIN',
}

export enum UserStatus {
  /** Created but not yet activated (e.g. awaiting review). */
  PENDING = 'PENDING',
  ACTIVE = 'ACTIVE',
  SUSPENDED = 'SUSPENDED',
  INACTIVE = 'INACTIVE',
}

// ─── Driver ──────────────────────────────────────────────

export enum DriverStatus {
  PENDING = 'PENDING',
  ACTIVE = 'ACTIVE',
  SUSPENDED = 'SUSPENDED',
  INACTIVE = 'INACTIVE',
}

// ─── Vehicle ─────────────────────────────────────────────

export enum VehicleType {
  MINIBUS = 'MINIBUS',
}

export enum VehicleStatus {
  ACTIVE = 'ACTIVE',
  INACTIVE = 'INACTIVE',
  MAINTENANCE = 'MAINTENANCE',
}

// ─── Route ───────────────────────────────────────────────

export enum RouteStatus {
  ACTIVE = 'ACTIVE',
  INACTIVE = 'INACTIVE',
}

// ─── Tariff ──────────────────────────────────────────────

export enum TariffStatus {
  DRAFT = 'DRAFT',
  ACTIVE = 'ACTIVE',
  EXPIRED = 'EXPIRED',
}

// ─── Trip ────────────────────────────────────────────────

export enum TripStatus {
  PENDING = 'PENDING',
  IN_PROGRESS = 'IN_PROGRESS',
  COMPLETED = 'COMPLETED',
  CANCELLED = 'CANCELLED',
}

export enum PaymentStatus {
  PENDING = 'PENDING',
  COMPLETED = 'COMPLETED',
  UNPAID = 'UNPAID',
  PAID = 'PAID',
  REFUNDED = 'REFUNDED',
  FAILED = 'FAILED',
}

// ─── Transaction ─────────────────────────────────────────

export enum TransactionType {
  PAYMENT = 'PAYMENT',
  DEPOSIT = 'DEPOSIT',
  WITHDRAWAL = 'WITHDRAWAL',
  REFUND = 'REFUND',
}

// ─── Wallet ──────────────────────────────────────────────

export enum WalletOwnerType {
  PASSENGER = 'PASSENGER',
  DRIVER = 'DRIVER',
}

export enum WalletStatus {
  ACTIVE = 'ACTIVE',
  FROZEN = 'FROZEN',
  CLOSED = 'CLOSED',
}

/**
 * Currency code.
 * Ethiopian Birr (ETB) is the only supported currency for now.
 */
export enum Currency {
  ETB = 'ETB',
}

// ─── Ledger ──────────────────────────────────────────────

export enum LedgerDirection {
  CREDIT = 'CREDIT',
  DEBIT = 'DEBIT',
}

export enum LedgerEntryType {
  TOP_UP = 'TOP_UP',
  TRIP_PAYMENT = 'TRIP_PAYMENT',
  DRIVER_EARNING = 'DRIVER_EARNING',
  WITHDRAWAL = 'WITHDRAWAL',
  REFUND = 'REFUND',
  ADJUSTMENT = 'ADJUSTMENT',
}// ─── Top-up intent ───────────────────────────────────────

/**
 * Lifecycle of a wallet top-up.
 *
 * A top-up only becomes SUCCESS after the provider confirms it — never merely
 * because the client claimed the payment went through.
 */
export enum TopUpIntentStatus {
  PENDING = 'PENDING',
  SUCCESS = 'SUCCESS',
  FAILED = 'FAILED',
  EXPIRED = 'EXPIRED',
}

// ─── Payment ─────────────────────────────────────────────
export enum PaymentRecordStatus {
  PENDING = 'PENDING',
  SUCCESS = 'SUCCESS',
  FAILED = 'FAILED',
  REFUNDED = 'REFUNDED',
}

export enum PaymentProvider {
  MOCK = 'MOCK',
  TELEBIRR = 'TELEBIRR',
  CHAPA = 'CHAPA',
  BANK = 'BANK',
}

// ─── Withdrawal ──────────────────────────────────────────

export enum WithdrawalStatus {
  PENDING = 'PENDING',
  PROCESSING = 'PROCESSING',
  SUCCESS = 'SUCCESS',
  FAILED = 'FAILED',
}

export enum WithdrawalDestinationType {
  BANK = 'BANK',
  MOBILE_MONEY = 'MOBILE_MONEY',
}
