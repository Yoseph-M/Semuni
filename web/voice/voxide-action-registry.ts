/**
 * Voxide Action Registry
 *
 * Central registry that registers all read-only and dangerous voice actions,
 * enforces parameter validation, and provides handlers connecting to the
 * semuni web API client.
 *
 * Every endpoint and payload below mirrors the **current** NestJS controllers
 * and DTOs — the backend is the source of truth. Nothing is derived on the
 * client: ids come from route/driver discovery, fares come from the fare
 * engine, and balances come from the wallet. Voxide never bypasses backend
 * authorization, and never talks to a database.
 */
import {
  VoxideActionDefinition,
  VoxideActionResult,
  VoxideErrorCode,
  VoxideParamSchema,
  WalletBalanceResult,
  TransactionEntry,
  RouteInfo,
  FareInfo,
  TripInfo,
  TripDetailInfo,
  DriverEarningsResult,
  WithdrawalStatusResult,
  CreateTripResult,
  PayForTripResult,
  InitiateTopUpResult,
  RequestWithdrawalResult,
} from './voxide.types';

// ─── API Client Interface ────────────────────────────────────────────────────

/**
 * HTTP client interface for the semuni REST API.
 * Injected at construction so the registry stays testable and decoupled.
 */
export interface SemunApiClient {
  get<T>(path: string, headers?: Record<string, string>): Promise<T>;
  post<T>(
    path: string,
    body: unknown,
    headers?: Record<string, string>,
  ): Promise<T>;
}

// ─── Parameter Validation ────────────────────────────────────────────────────

function validateParams(
  params: Record<string, unknown>,
  schema: VoxideParamSchema[],
): { valid: boolean; error?: string } {
  for (const field of schema) {
    const value = params[field.name];
    if (field.required && (value === undefined || value === null || value === '')) {
      return { valid: false, error: `Missing required parameter: ${field.name}` };
    }
    if (value !== undefined && value !== null) {
      if (field.type === 'number' && typeof value !== 'number') {
        return { valid: false, error: `Parameter '${field.name}' must be a number` };
      }
      if (field.type === 'string' && typeof value !== 'string') {
        return { valid: false, error: `Parameter '${field.name}' must be a string` };
      }
      if (field.type === 'boolean' && typeof value !== 'boolean') {
        return { valid: false, error: `Parameter '${field.name}' must be a boolean` };
      }
      if (
        field.type === 'number' &&
        typeof value === 'number'
      ) {
        if (field.min !== undefined && value < field.min) {
          return { valid: false, error: `Parameter '${field.name}' must be >= ${field.min}` };
        }
        if (field.max !== undefined && value > field.max) {
          return { valid: false, error: `Parameter '${field.name}' must be <= ${field.max}` };
        }
      }
      if (field.enum && typeof value === 'string' && !field.enum.includes(value)) {
        return {
          valid: false,
          error: `Parameter '${field.name}' must be one of: ${field.enum.join(', ')}`,
        };
      }
    }
  }
  return { valid: true };
}

// ─── Action Registry ─────────────────────────────────────────────────────────

export class VoxideActionRegistry {
  private readonly actions = new Map<string, VoxideActionDefinition>();

  register(action: VoxideActionDefinition): void {
    if (this.actions.has(action.name)) {
      throw new Error(`Action '${action.name}' is already registered`);
    }
    this.actions.set(action.name, action);
  }

  get(name: string): VoxideActionDefinition | undefined {
    return this.actions.get(name);
  }

  has(name: string): boolean {
    return this.actions.has(name);
  }

  listActions(): VoxideActionDefinition[] {
    return Array.from(this.actions.values());
  }

  listReadOnly(): VoxideActionDefinition[] {
    return this.listActions().filter((a) => !a.dangerous);
  }

  listDangerous(): VoxideActionDefinition[] {
    return this.listActions().filter((a) => a.dangerous);
  }

  /**
   * Execute an action by name with validated parameters.
   * Returns a typed VoxideActionResult; never throws.
   */
  async execute(
    name: string,
    params: Record<string, unknown>,
  ): Promise<VoxideActionResult> {
    const action = this.actions.get(name);
    if (!action) {
      return {
        success: false,
        errorCode: VoxideErrorCode.UNKNOWN_ACTION,
        errorMessage: `Unknown action: ${name}`,
      };
    }

    const validation = validateParams(params, action.parameters);
    if (!validation.valid) {
      return {
        success: false,
        errorCode: VoxideErrorCode.INVALID_PARAMS,
        errorMessage: validation.error,
      };
    }

    try {
      const data = await action.handler(params);
      return { success: true, data };
    } catch (err) {
      const errorCode = mapErrorCode(err);
      return {
        success: false,
        errorCode,
        errorMessage: (err as Error).message,
      };
    }
  }
}

// ─── Error Mapping ───────────────────────────────────────────────────────────

function mapErrorCode(err: unknown): VoxideErrorCode {
  if (!(err instanceof Error)) return VoxideErrorCode.UNKNOWN_ERROR;

  const message = err.message.toLowerCase();

  if (message.includes('401') || message.includes('unauthorized') || message.includes('token expired')) {
    return VoxideErrorCode.AUTH_EXPIRED;
  }
  if (message.includes('insufficient') || message.includes('not enough')) {
    return VoxideErrorCode.INSUFFICIENT_BALANCE;
  }
  if (message.includes('not found') && message.includes('trip')) {
    return VoxideErrorCode.TRIP_NOT_FOUND;
  }
  if (message.includes('already paid')) {
    return VoxideErrorCode.TRIP_ALREADY_PAID;
  }
  if (message.includes('pending') && message.includes('payment')) {
    return VoxideErrorCode.PAYMENT_PENDING;
  }
  if (message.includes('payment') && message.includes('fail')) {
    return VoxideErrorCode.PAYMENT_FAILED;
  }
  if (message.includes('pending') && message.includes('top-up')) {
    return VoxideErrorCode.TOP_UP_PENDING;
  }
  if (message.includes('unavailable') || message.includes('502')) {
    return VoxideErrorCode.PROVIDER_UNAVAILABLE;
  }
  if (message.includes('pending') && message.includes('withdrawal')) {
    return VoxideErrorCode.WITHDRAWAL_PENDING;
  }
  if (message.includes('rate') && message.includes('limit')) {
    return VoxideErrorCode.RATE_LIMITED;
  }
  if (message.includes('network') || message.includes('fetch') || message.includes('timeout')) {
    return VoxideErrorCode.NETWORK_ERROR;
  }
  return VoxideErrorCode.UNKNOWN_ERROR;
}

// ─── Registry Factory ────────────────────────────────────────────────────────

/**
 * Creates a fully populated VoxideActionRegistry backed by the supplied API client.
 * Every action handler calls the standard semuni REST API.
 */
export function createDefaultRegistry(api: SemunApiClient, authHeaders: () => Record<string, string>): VoxideActionRegistry {
  const registry = new VoxideActionRegistry();

  /** A fresh correlation id per attempt; the backend logs it against the call. */
  const requestId = (): string => {
    const unique =
      typeof crypto !== 'undefined' && typeof crypto.randomUUID === 'function'
        ? crypto.randomUUID()
        : `${Date.now()}-${Math.random().toString(36).slice(2, 11)}`;
    return `voxide-${unique}`;
  };

  /** Headers for every call: the session plus a correlation id. */
  const callHeaders = (extra?: Record<string, string>): Record<string, string> => ({
    ...authHeaders(),
    'X-Request-Id': requestId(),
    ...extra,
  });

  /**
   * Headers for a financial call.
   *
   * The same idempotency key travels as a header (the convention the Flutter
   * client uses) *and* in the validated body field the backend DTO requires, so
   * a retry is recognisable to the server either way.
   */
  const financialHeaders = (params: Record<string, unknown>): Record<string, string> => {
    const key = typeof params.idempotencyKey === 'string' ? params.idempotencyKey : '';
    return callHeaders(key ? { 'Idempotency-Key': key } : undefined);
  };

  // ── Read-Only Actions ────────────────────────────────────────────────────

  registry.register({
    name: 'getWalletBalance',
    description: 'Get the current wallet balance for the authenticated user.',
    dangerous: false,
    parameters: [],
    handler: async (): Promise<WalletBalanceResult> => {
      const res = await api.get<{ data: WalletBalanceResult }>('/wallet', callHeaders());
      return res.data;
    },
  });

  registry.register({
    name: 'getRecentTransactions',
    description: 'Get the most recent wallet transactions for the authenticated user.',
    dangerous: false,
    parameters: [],
    handler: async (): Promise<TransactionEntry[]> => {
      const res = await api.get<{ data: TransactionEntry[] }>('/wallet/transactions', callHeaders());
      return res.data;
    },
  });

  registry.register({
    name: 'getActiveRoutes',
    description: 'Get all transportation routes.',
    dangerous: false,
    parameters: [],
    handler: async (): Promise<RouteInfo[]> => {
      const res = await api.get<{ data: RouteInfo[] }>('/routes', callHeaders());
      return res.data;
    },
  });

  registry.register({
    name: 'getCurrentFare',
    description:
      'Get the official fare for one segment of a route. The backend prices it; the client never calculates a fare.',
    dangerous: false,
    parameters: [
      { name: 'routeId', type: 'string', required: true, description: 'The route ID to price' },
      { name: 'originStopId', type: 'string', required: true, description: 'Boarding stop ID' },
      { name: 'destinationStopId', type: 'string', required: true, description: 'Drop-off stop ID' },
    ],
    handler: async (params: Record<string, unknown>): Promise<FareInfo> => {
      const res = await api.post<{ data: FareInfo }>(
        '/fares/calculate',
        {
          routeId: params.routeId,
          originStopId: params.originStopId,
          destinationStopId: params.destinationStopId,
        },
        callHeaders(),
      );
      return res.data;
    },
  });

  registry.register({
    name: 'getMyTrips',
    description: 'Get the trip history for the authenticated user.',
    dangerous: false,
    parameters: [],
    handler: async (): Promise<TripInfo[]> => {
      const res = await api.get<{ data: TripInfo[] }>('/trips', callHeaders());
      return res.data;
    },
  });

  registry.register({
    name: 'getTripDetails',
    description: 'Get detailed information about a specific trip.',
    dangerous: false,
    parameters: [
      { name: 'tripId', type: 'string', required: true, description: 'The trip ID to query' },
    ],
    handler: async (params: Record<string, unknown>): Promise<TripDetailInfo> => {
      const tripId = params.tripId as string;
      const res = await api.get<{ data: TripDetailInfo }>(`/trips/${tripId}`, callHeaders());
      return res.data;
    },
  });

  registry.register({
    name: 'getDriverEarnings',
    description:
      'Get today and lifetime earnings for the authenticated driver (ETB, not santim).',
    dangerous: false,
    parameters: [],
    handler: async (): Promise<DriverEarningsResult> => {
      const res = await api.get<{ data: DriverEarningsResult }>(
        '/drivers/me/earnings',
        callHeaders(),
      );
      return res.data;
    },
  });

  registry.register({
    name: 'getWithdrawalStatus',
    description:
      'Get the most recent withdrawal request for the authenticated driver, or null if none.',
    dangerous: false,
    parameters: [],
    handler: async (): Promise<WithdrawalStatusResult | null> => {
      const res = await api.get<{ data: WithdrawalStatusResult[] }>(
        '/drivers/me/withdrawals',
        callHeaders(),
      );
      return res.data.length > 0 ? res.data[0] : null;
    },
  });

  // ── Dangerous (Financial) Actions ────────────────────────────────────────

  registry.register({
    name: 'createTrip',
    description:
      'Create a new trip booking. Requires user confirmation. Every identifier is backend-authoritative: ids come from route and driver discovery, and the fare is calculated by the server.',
    dangerous: true,
    parameters: [
      { name: 'driverId', type: 'string', required: true, description: "Driver user id from `GET /drivers/available`" },
      { name: 'routeId', type: 'string', required: true, description: 'Route ID being travelled' },
      { name: 'originStopId', type: 'string', required: true, description: 'Boarding RouteStop ID' },
      { name: 'destinationStopId', type: 'string', required: true, description: 'Drop-off RouteStop ID' },
      { name: 'origin', type: 'string', required: true, description: 'Boarding stop name (descriptive label)' },
      { name: 'destination', type: 'string', required: true, description: 'Drop-off stop name (descriptive label)' },
      { name: 'vehicleId', type: 'string', required: false, description: 'Vehicle ID, when known' },
      { name: 'vehicleType', type: 'string', required: false, description: 'Vehicle type, when known', enum: ['MINIBUS'] },
      { name: 'idempotencyKey', type: 'string', required: true, description: 'Stable key for this logical booking' },
    ],
    handler: async (params: Record<string, unknown>): Promise<CreateTripResult> => {
      const res = await api.post<{ data: CreateTripResult }>(
        '/trips',
        {
          driverId: params.driverId,
          routeId: params.routeId,
          originStopId: params.originStopId,
          destinationStopId: params.destinationStopId,
          origin: params.origin,
          destination: params.destination,
          ...(params.vehicleId ? { vehicleId: params.vehicleId } : {}),
          ...(params.vehicleType ? { vehicleType: params.vehicleType } : {}),
          idempotencyKey: params.idempotencyKey,
        },
        financialHeaders(params),
      );
      return res.data;
    },
  });

  registry.register({
    name: 'payForTrip',
    description:
      'Pay for an existing trip from the semuni wallet. Requires user confirmation; the transfer is idempotent.',
    dangerous: true,
    parameters: [
      { name: 'tripId', type: 'string', required: true, description: 'Trip ID to pay for' },
      { name: 'idempotencyKey', type: 'string', required: true, description: 'Stable key for this logical payment' },
    ],
    handler: async (params: Record<string, unknown>): Promise<PayForTripResult> => {
      const res = await api.post<{ data: PayForTripResult }>(
        '/payments/trip',
        { tripId: params.tripId, idempotencyKey: params.idempotencyKey },
        financialHeaders(params),
      );
      return res.data;
    },
  });

  registry.register({
    name: 'initiateTopUp',
    description:
      'Start a wallet top-up. Returns a pending intent and, when the provider hosts checkout, its URL. The balance only changes once the backend verifies the payment. Requires user confirmation.',
    dangerous: true,
    parameters: [
      { name: 'amount', type: 'number', required: true, description: 'Amount in santim (minor units)', min: 100 },
      { name: 'idempotencyKey', type: 'string', required: true, description: 'Stable key for this logical top-up' },
      { name: 'provider', type: 'string', required: false, description: 'Payment provider', enum: ['MOCK', 'TELEBIRR', 'CHAPA', 'BANK'] },
    ],
    handler: async (params: Record<string, unknown>): Promise<InitiateTopUpResult> => {
      const res = await api.post<{ data: InitiateTopUpResult }>(
        '/wallet/top-up',
        {
          amount: params.amount,
          idempotencyKey: params.idempotencyKey,
          ...(params.provider ? { provider: params.provider } : {}),
        },
        financialHeaders(params),
      );
      return res.data;
    },
  });

  registry.register({
    name: 'requestWithdrawal',
    description:
      'Request a withdrawal of driver earnings. Accepted as PENDING; the backend re-checks the balance and driver status. Requires user confirmation.',
    dangerous: true,
    parameters: [
      { name: 'amount', type: 'number', required: true, description: 'Amount in santim (minor units)', min: 100 },
      { name: 'destinationType', type: 'string', required: true, description: 'Where the money goes', enum: ['BANK', 'MOBILE_MONEY'] },
      { name: 'idempotencyKey', type: 'string', required: true, description: 'Stable key for this logical withdrawal' },
      { name: 'destination', type: 'string', required: false, description: 'Bank or mobile-money provider name' },
      { name: 'destinationAccount', type: 'string', required: false, description: 'Account number or mobile reference' },
    ],
    handler: async (params: Record<string, unknown>): Promise<RequestWithdrawalResult> => {
      const res = await api.post<{ data: RequestWithdrawalResult }>(
        '/drivers/me/withdrawals',
        {
          amount: params.amount,
          destinationType: params.destinationType,
          ...(params.destination ? { destination: params.destination } : {}),
          ...(params.destinationAccount ? { destinationAccount: params.destinationAccount } : {}),
          idempotencyKey: params.idempotencyKey,
        },
        financialHeaders(params),
      );
      return res.data;
    },
  });

  return registry;
}
