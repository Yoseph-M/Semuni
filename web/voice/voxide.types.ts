/**
 * Voxide Web Voice Action Layer — Type Definitions
 *
 * Defines the typed interface between the Voxide voice AI and the semuni web
 * API client. All actions are mediated through the standard semuni REST API;
 * Voxide never bypasses backend authorization.
 *
 * Actions are categorised as **read-only** (safe to execute immediately) or
 * **dangerous** (require explicit user confirmation before execution).
 */

// ─── Action Error Codes ──────────────────────────────────────────────────────

/**
 * Standard machine-readable error codes returned from voice action handlers.
 * These map to user-understandable voice feedback messages.
 */
export enum VoxideErrorCode {
  AUTH_EXPIRED = 'AUTH_EXPIRED',
  INSUFFICIENT_BALANCE = 'INSUFFICIENT_BALANCE',
  TRIP_NOT_FOUND = 'TRIP_NOT_FOUND',
  TRIP_ALREADY_PAID = 'TRIP_ALREADY_PAID',
  PAYMENT_PENDING = 'PAYMENT_PENDING',
  PAYMENT_FAILED = 'PAYMENT_FAILED',
  TOP_UP_PENDING = 'TOP_UP_PENDING',
  PROVIDER_UNAVAILABLE = 'PROVIDER_UNAVAILABLE',
  WITHDRAWAL_PENDING = 'WITHDRAWAL_PENDING',
  CONFIRMATION_REQUIRED = 'CONFIRMATION_REQUIRED',
  CONFIRMATION_CANCELLED = 'CONFIRMATION_CANCELLED',
  RATE_LIMITED = 'RATE_LIMITED',
  INVALID_PARAMS = 'INVALID_PARAMS',
  NETWORK_ERROR = 'NETWORK_ERROR',
  UNKNOWN_ACTION = 'UNKNOWN_ACTION',
  UNKNOWN_ERROR = 'UNKNOWN_ERROR',
}

// ─── Parameter Schema ────────────────────────────────────────────────────────

export interface VoxideParamSchema {
  name: string;
  type: 'string' | 'number' | 'boolean';
  required: boolean;
  description: string;
  enum?: string[];
  min?: number;
  max?: number;
}

// ─── Action Definition ───────────────────────────────────────────────────────

export interface VoxideActionDefinition<
  TParams = Record<string, unknown>,
  TResult = unknown,
> {
  /** Unique name for this action (e.g., 'getWalletBalance'). */
  name: string;
  /** Human-readable description for voice AI context. */
  description: string;
  /** Whether this action mutates state and requires user confirmation. */
  dangerous: boolean;
  /** Typed parameter schema for validation. */
  parameters: VoxideParamSchema[];
  /** The handler function — receives validated params and returns a result. */
  handler: (params: TParams) => Promise<TResult>;
}

// ─── Action Result ───────────────────────────────────────────────────────────

export interface VoxideActionResult<T = unknown> {
  success: boolean;
  data?: T;
  errorCode?: VoxideErrorCode;
  errorMessage?: string;
}

// ─── Confirmation Context ────────────────────────────────────────────────────

/**
 * Context presented to the user for dangerous action confirmation.
 * Contains only safe, non-sensitive information.
 */
export interface VoxideConfirmationContext {
  actionName: string;
  summary: string;
  details: Record<string, string | number>;
}

// ─── Client State (Safe Context) ─────────────────────────────────────────────

/**
 * Safe contextual state bound to voice interactions.
 * Strictly strips authentication secrets, private keys, and refresh tokens.
 */
export interface VoxideClientState {
  currentScreen?: string;
  selectedRouteId?: string;
  selectedRouteName?: string;
  currentFare?: number;
  currentBalance?: number;
  currentCurrency?: string;
  userId?: string;
  userRole?: string;
  activeTrip?: {
    tripId: string;
    routeName: string;
    status: string;
    fare?: number;
  };
}

// ─── Read-Only Action Result Types ───────────────────────────────────────────

export interface WalletBalanceResult {
  /** Balance in minor units (santim). */
  balance: number;
  currency: string;
  status?: string;
}

export interface TransactionEntry {
  id: string;
  entryType: string;
  /** The sign of a ledger amount is carried by the direction, never the number. */
  direction: 'CREDIT' | 'DEBIT';
  /** Amount in minor units (santim). */
  amount: number;
  currency?: string;
  description?: string;
  referenceId?: string;
  createdAt: string;
}

export interface RouteInfo {
  id: string;
  name: string;
  origin: string;
  destination: string;
  code?: string;
  status: string;
}

/** What the fare engine answers for one segment of a route. */
export interface FareInfo {
  /** The official fare in minor units (santim). Never calculated client-side. */
  fare: number;
  currency: string;
  routeId: string;
  originStopId: string;
  destinationStopId: string;
  routeName?: string;
  originStopName?: string;
  destinationStopName?: string;
  tariffVersion?: string;
}

/** A trip as the list endpoint reports it (it adds the ETB convenience field). */
export interface TripInfo {
  id: string;
  origin: string;
  destination: string;
  /** The stored fare, in minor units (santim). */
  fareAmount: number;
  /** The same fare in ETB, as reported by `GET /trips`. */
  amountPaid: number;
  status: string;
  paymentStatus: string;
  createdAt: string;
}

/** A single trip as `GET /trips/:id` returns it (the stored record). */
export interface TripDetailInfo {
  id: string;
  origin: string;
  destination: string;
  fareAmount: number;
  status: string;
  paymentStatus: string;
  routeId?: string;
  driverId?: string;
  passengerId?: string;
  receiptNumber?: string;
  createdAt: string;
  completedAt?: string;
}

/**
 * Driver earnings summary.
 *
 * This endpoint reports ETB, not minor units, because the backend formats these
 * totals for the driver dashboard. Every other money field in this layer is in
 * santim.
 */
export interface DriverEarningsResult {
  todayEarnings: number;
  totalEarnings: number;
  walletBalance: number;
  completedRides: number;
  averageFare: number;
}

/** One withdrawal record, newest first from `GET /drivers/me/withdrawals`. */
export interface WithdrawalStatusResult {
  id: string;
  /** Amount in minor units (santim). */
  amount: number;
  currency: string;
  status: string;
  destinationType: 'BANK' | 'MOBILE_MONEY';
  destination?: string;
  createdAt: string;
}

// ─── Dangerous Action Result Types ───────────────────────────────────────────

export interface CreateTripResult {
  id: string;
  origin: string;
  destination: string;
  /** The server-calculated fare, in minor units (santim). */
  fareAmount: number;
  status: string;
  paymentStatus: string;
}

export interface PayForTripResult {
  paymentId: string;
  tripId: string;
  /** Amount charged, in minor units (santim). */
  amount: number;
  currency: string;
  status: string;
  receiptNumber?: string;
}

export interface InitiateTopUpResult {
  intentId: string;
  /** Amount in minor units (santim). */
  amount?: number;
  currency?: string;
  provider?: string;
  status: string;
  providerReference?: string;
  checkoutUrl?: string;
}

export interface RequestWithdrawalResult {
  id: string;
  /** Amount in minor units (santim). */
  amount: number;
  currency: string;
  status: string;
  destinationType: 'BANK' | 'MOBILE_MONEY';
  createdAt: string;
}

// ─── Middleware Types ────────────────────────────────────────────────────────

export interface VoxideMiddlewareContext {
  /** JWT access token for authenticated API calls. */
  accessToken: string | null;
  /** User ID from the current session. */
  userId: string | null;
  /** User role from the current session. */
  userRole: string | null;
  /** Current client state for context-aware interactions. */
  clientState: VoxideClientState;
  /** Idempotency key for financial mutations. */
  idempotencyKey?: string;
}

export interface VoxideInteractionLog {
  client: 'WEB';
  interactionChannel: 'VOICE';
  actionName: string;
  userId: string | null;
  timestamp: string;
  result: 'SUCCESS' | 'FAILED' | 'CANCELLED';
  errorCode?: VoxideErrorCode;
  durationMs: number;
}
