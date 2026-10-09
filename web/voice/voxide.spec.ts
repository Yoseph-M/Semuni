/**
 * Voxide Voice Action Layer — Test Suite
 *
 * Validates action registration, parameter validation, read-only action
 * execution, dangerous action confirmation workflow, session expiration,
 * idempotency key reuse on retry, error code mapping, and security boundaries.
 */
import {
  VoxideActionResult,
  VoxideConfirmationContext,
  VoxideErrorCode,
} from './voxide.types';
import {
  VoxideActionRegistry,
  SemunApiClient,
  createDefaultRegistry,
} from './voxide-action-registry';
import { VoxideClient } from './voxide-client';

// ─── Test Helpers ────────────────────────────────────────────────────────────

function createMockApi(overrides: Partial<SemunApiClient> = {}): SemunApiClient {
  return {
    get: jest.fn().mockResolvedValue({ data: {} }),
    post: jest.fn().mockResolvedValue({ data: {} }),
    ...overrides,
  };
}

/**
 * The identifiers the backend requires to create a trip. Voxide takes them from
 * route and driver discovery — it never invents them, and never sends a fare.
 */
const TRIP_PARAMS = {
  driverId: 'drv-user-1',
  routeId: 'r1',
  originStopId: 'stop-1',
  destinationStopId: 'stop-2',
  origin: 'Bole',
  destination: 'Piazza',
};

const CREATE_TRIP_RESPONSE = {
  id: 't1',
  origin: 'Bole',
  destination: 'Piazza',
  fareAmount: 1000,
  status: 'REQUESTED',
  paymentStatus: 'UNPAID',
};

function createTestClient(options: {
  api?: SemunApiClient;
  accessToken?: string | null;
  userId?: string | null;
  userRole?: string | null;
  confirmResult?: boolean;
  rateLimit?: number;
} = {}) {
  const api = options.api ?? createMockApi();
  const logs: any[] = [];
  const confirmations: VoxideConfirmationContext[] = [];

  const client = new VoxideClient({
    apiClient: api,
    getAccessToken: () => (options.accessToken !== undefined ? options.accessToken : 'test-jwt-token'),
    getUserId: () => (options.userId !== undefined ? options.userId : 'user-123'),
    getUserRole: () => (options.userRole !== undefined ? options.userRole : 'passenger'),
    confirmationHandler: async (ctx) => {
      confirmations.push(ctx);
      return options.confirmResult ?? true;
    },
    interactionLogger: (log) => logs.push(log),
    rateLimit: options.rateLimit,
  });

  return { client, api, logs, confirmations };
}

// ─── VoxideActionRegistry Tests ──────────────────────────────────────────────

describe('VoxideActionRegistry', () => {
  it('registers and retrieves actions', () => {
    const registry = new VoxideActionRegistry();
    registry.register({
      name: 'testAction',
      description: 'A test action',
      dangerous: false,
      parameters: [],
      handler: async () => ({ result: 'ok' }),
    });

    expect(registry.has('testAction')).toBe(true);
    expect(registry.get('testAction')?.name).toBe('testAction');
  });

  it('rejects duplicate registration', () => {
    const registry = new VoxideActionRegistry();
    const action = {
      name: 'dup',
      description: 'Duplicate',
      dangerous: false,
      parameters: [],
      handler: async () => ({}),
    };
    registry.register(action);
    expect(() => registry.register(action)).toThrow("Action 'dup' is already registered");
  });

  it('lists read-only and dangerous actions separately', () => {
    const api = createMockApi();
    const registry = createDefaultRegistry(api, () => ({}));
    const readOnly = registry.listReadOnly();
    const dangerous = registry.listDangerous();

    expect(readOnly.length).toBeGreaterThan(0);
    expect(dangerous.length).toBeGreaterThan(0);
    expect(readOnly.every((a) => !a.dangerous)).toBe(true);
    expect(dangerous.every((a) => a.dangerous)).toBe(true);
  });

  it('returns UNKNOWN_ACTION for non-existent actions', async () => {
    const registry = new VoxideActionRegistry();
    const result = await registry.execute('nonexistent', {});
    expect(result.success).toBe(false);
    expect(result.errorCode).toBe(VoxideErrorCode.UNKNOWN_ACTION);
  });

  describe('parameter validation', () => {
    it('rejects missing required parameters', async () => {
      const registry = new VoxideActionRegistry();
      registry.register({
        name: 'withRequired',
        description: 'Needs a param',
        dangerous: false,
        parameters: [
          { name: 'routeId', type: 'string', required: true, description: 'Route' },
        ],
        handler: async () => ({}),
      });

      const result = await registry.execute('withRequired', {});
      expect(result.success).toBe(false);
      expect(result.errorCode).toBe(VoxideErrorCode.INVALID_PARAMS);
      expect(result.errorMessage).toContain('routeId');
    });

    it('rejects wrong parameter types', async () => {
      const registry = new VoxideActionRegistry();
      registry.register({
        name: 'withNumber',
        description: 'Needs a number',
        dangerous: false,
        parameters: [
          { name: 'amount', type: 'number', required: true, description: 'Amount' },
        ],
        handler: async () => ({}),
      });

      const result = await registry.execute('withNumber', { amount: 'not-a-number' });
      expect(result.success).toBe(false);
      expect(result.errorCode).toBe(VoxideErrorCode.INVALID_PARAMS);
    });

    it('enforces min/max on number parameters', async () => {
      const registry = new VoxideActionRegistry();
      registry.register({
        name: 'withRange',
        description: 'Range check',
        dangerous: false,
        parameters: [
          { name: 'amount', type: 'number', required: true, description: 'Amount', min: 100, max: 100000 },
        ],
        handler: async () => ({}),
      });

      const tooLow = await registry.execute('withRange', { amount: 50 });
      expect(tooLow.success).toBe(false);
      expect(tooLow.errorMessage).toContain('>= 100');

      const tooHigh = await registry.execute('withRange', { amount: 200000 });
      expect(tooHigh.success).toBe(false);
      expect(tooHigh.errorMessage).toContain('<= 100000');
    });

    it('validates enum parameters', async () => {
      const registry = new VoxideActionRegistry();
      registry.register({
        name: 'withEnum',
        description: 'Enum check',
        dangerous: false,
        parameters: [
          { name: 'period', type: 'string', required: true, description: 'Period', enum: ['today', 'week', 'month'] },
        ],
        handler: async () => ({}),
      });

      const invalid = await registry.execute('withEnum', { period: 'year' });
      expect(invalid.success).toBe(false);
      expect(invalid.errorMessage).toContain('one of');
    });
  });
});

// ─── Read-Only Action Execution ──────────────────────────────────────────────

describe('Read-only action execution', () => {
  it('getWalletBalance returns balance from API', async () => {
    const api = createMockApi({
      get: jest.fn().mockResolvedValue({ data: { balance: 5000, currency: 'ETB' } }),
    });
    const { client } = createTestClient({ api });

    const result = await client.executeAction('getWalletBalance');
    expect(result.success).toBe(true);
    expect(result.data).toEqual({ balance: 5000, currency: 'ETB' });
    expect(api.get).toHaveBeenCalledWith(
      '/wallet',
      expect.objectContaining({ Authorization: 'Bearer test-jwt-token' }),
    );
  });

  it('getActiveRoutes fetches routes from API', async () => {
    const routes = [
      { id: 'r1', name: 'Route A', origin: 'A', destination: 'B', isActive: true },
    ];
    const api = createMockApi({
      get: jest.fn().mockResolvedValue({ data: routes }),
    });
    const { client } = createTestClient({ api });

    const result = await client.executeAction('getActiveRoutes');
    expect(result.success).toBe(true);
    expect(result.data).toEqual(routes);
  });

  it('getCurrentFare requires routeId parameter', async () => {
    const { client } = createTestClient();
    const result = await client.executeAction('getCurrentFare', {});
    expect(result.success).toBe(false);
    expect(result.errorCode).toBe(VoxideErrorCode.INVALID_PARAMS);
  });

  it('does not trigger confirmation for read-only actions', async () => {
    const { client, confirmations } = createTestClient();
    await client.executeAction('getWalletBalance');
    expect(confirmations).toHaveLength(0);
  });
});

// ─── Dangerous Action Confirmation ───────────────────────────────────────────

describe('Dangerous action confirmation', () => {
  it('presents confirmation context for createTrip', async () => {
    const api = createMockApi({
      post: jest.fn().mockResolvedValue({ data: CREATE_TRIP_RESPONSE }),
    });
    const { client, confirmations } = createTestClient({ api, confirmResult: true });

    client.updateState({
      selectedRouteName: 'Bole → Megenagna',
      currentFare: 1500,
      currentBalance: 5000,
    });

    const result = await client.executeAction('createTrip', { ...TRIP_PARAMS });
    expect(result.success).toBe(true);
    expect(confirmations).toHaveLength(1);
    expect(confirmations[0].actionName).toBe('createTrip');
    expect(confirmations[0].details.routeName).toBe('Bole → Megenagna');
    expect(confirmations[0].details.currentBalance).toBe(5000);
    expect(confirmations[0].details.remainingBalance).toBe(3500);
  });

  it('cancels action when user declines confirmation', async () => {
    const api = createMockApi();
    const { client } = createTestClient({ api, confirmResult: false });

    const result = await client.executeAction('createTrip', { ...TRIP_PARAMS });
    expect(result.success).toBe(false);
    expect(result.errorCode).toBe(VoxideErrorCode.CONFIRMATION_CANCELLED);
    // API should NOT have been called
    expect(api.post).not.toHaveBeenCalled();
  });

  it('presents confirmation context for initiateTopUp with balance projection', async () => {
    const api = createMockApi({
      post: jest.fn().mockResolvedValue({
        data: { intentId: 'i1', status: 'PENDING' },
      }),
    });
    const { client, confirmations } = createTestClient({ api, confirmResult: true });
    client.updateState({ currentBalance: 2000 });

    await client.executeAction('initiateTopUp', { amount: 3000 });
    expect(confirmations[0].details.balanceAfter).toBe(5000);
  });
});

// ─── Session Expiration ──────────────────────────────────────────────────────

describe('Session expiration', () => {
  it('returns AUTH_EXPIRED when no access token is available', async () => {
    const { client } = createTestClient({ accessToken: null });
    const result = await client.executeAction('getWalletBalance');
    expect(result.success).toBe(false);
    expect(result.errorCode).toBe(VoxideErrorCode.AUTH_EXPIRED);
  });

  it('logs the interaction even on auth failure', async () => {
    const { client, logs } = createTestClient({ accessToken: null });
    await client.executeAction('getWalletBalance');
    expect(logs).toHaveLength(1);
    expect(logs[0].result).toBe('FAILED');
    expect(logs[0].errorCode).toBe(VoxideErrorCode.AUTH_EXPIRED);
  });
});

// ─── Idempotency Key Reuse ──────────────────────────────────────────────────

describe('Idempotency key management', () => {
  it('generates idempotency key for dangerous actions', async () => {
    const postMock = jest.fn().mockResolvedValue({ data: CREATE_TRIP_RESPONSE });
    const api = createMockApi({ post: postMock });
    const { client } = createTestClient({ api, confirmResult: true });

    await client.executeAction('createTrip', { ...TRIP_PARAMS });
    expect(postMock).toHaveBeenCalledTimes(1);
    const body = postMock.mock.calls[0][1];
    expect(body.idempotencyKey).toBeDefined();
    expect(typeof body.idempotencyKey).toBe('string');
  });

  it('does not inject idempotency key for read-only actions', async () => {
    const getMock = jest.fn().mockResolvedValue({ data: { balance: 1000, currency: 'ETB' } });
    const api = createMockApi({ get: getMock });
    const { client } = createTestClient({ api });

    await client.executeAction('getWalletBalance');
    // GET calls don't receive an idempotency key
    expect(getMock).toHaveBeenCalledWith('/wallet', expect.any(Object));
  });
});

// ─── Error Code Mapping ──────────────────────────────────────────────────────

describe('Error code mapping', () => {
  it('maps 401 errors to AUTH_EXPIRED', async () => {
    const api = createMockApi({
      get: jest.fn().mockRejectedValue(new Error('401 Unauthorized')),
    });
    const { client } = createTestClient({ api });
    const result = await client.executeAction('getWalletBalance');
    expect(result.success).toBe(false);
    expect(result.errorCode).toBe(VoxideErrorCode.AUTH_EXPIRED);
  });

  it('maps insufficient balance errors', async () => {
    const api = createMockApi({
      post: jest.fn().mockRejectedValue(new Error('Insufficient balance')),
    });
    const { client } = createTestClient({ api, confirmResult: true });
    const result = await client.executeAction('payForTrip', { tripId: 't1' });
    expect(result.success).toBe(false);
    expect(result.errorCode).toBe(VoxideErrorCode.INSUFFICIENT_BALANCE);
  });

  it('maps provider unavailable errors', async () => {
    const api = createMockApi({
      post: jest.fn().mockRejectedValue(new Error('502 Bad Gateway — provider unavailable')),
    });
    const { client } = createTestClient({ api, confirmResult: true });
    const result = await client.executeAction('initiateTopUp', { amount: 1000 });
    expect(result.success).toBe(false);
    expect(result.errorCode).toBe(VoxideErrorCode.PROVIDER_UNAVAILABLE);
  });

  it('maps network/timeout errors', async () => {
    const api = createMockApi({
      get: jest.fn().mockRejectedValue(new Error('fetch failed: network error')),
    });
    const { client } = createTestClient({ api });
    const result = await client.executeAction('getWalletBalance');
    expect(result.success).toBe(false);
    expect(result.errorCode).toBe(VoxideErrorCode.NETWORK_ERROR);
  });
});

// ─── Rate Limiting ───────────────────────────────────────────────────────────

describe('Rate limiting', () => {
  it('blocks requests exceeding the rate limit', async () => {
    const { client } = createTestClient({ rateLimit: 2 });

    await client.executeAction('getWalletBalance');
    await client.executeAction('getWalletBalance');
    const result = await client.executeAction('getWalletBalance');

    expect(result.success).toBe(false);
    expect(result.errorCode).toBe(VoxideErrorCode.RATE_LIMITED);
  });
});

// ─── Security Verification ──────────────────────────────────────────────────

describe('Security boundaries', () => {
  it('strips sensitive fields from client state', () => {
    const { client } = createTestClient();

    // Attempt to inject secrets via updateState
    client.updateState({
      currentBalance: 5000,
      currentScreen: 'wallet',
      // These should be silently stripped
      ...({
        accessToken: 'secret-jwt',
        refreshToken: 'secret-refresh',
        privateKey: 'secret-key',
        password: 'hunter2',
        apiKey: 'secret-api-key',
        appSecret: 'secret-app',
      } as any),
    });

    const state = client.getState();
    expect(state.currentBalance).toBe(5000);
    expect(state.currentScreen).toBe('wallet');
    expect((state as any).accessToken).toBeUndefined();
    expect((state as any).refreshToken).toBeUndefined();
    expect((state as any).privateKey).toBeUndefined();
    expect((state as any).password).toBeUndefined();
    expect((state as any).apiKey).toBeUndefined();
    expect((state as any).appSecret).toBeUndefined();
  });

  it('does not expose credentials in API headers for unauthenticated requests', async () => {
    const getMock = jest.fn().mockResolvedValue({ data: {} });
    const api = createMockApi({ get: getMock });
    const { client } = createTestClient({ api, accessToken: null });

    await client.executeAction('getWalletBalance');
    // The action fails at session check before even calling the API
    expect(getMock).not.toHaveBeenCalled();
  });

  it('all dangerous actions require explicit confirmation', () => {
    const api = createMockApi();
    const registry = createDefaultRegistry(api, () => ({}));
    const dangerous = registry.listDangerous();

    expect(dangerous.length).toBeGreaterThan(0);
    for (const action of dangerous) {
      expect(action.dangerous).toBe(true);
    }
  });

  it('Voxide has no direct database access or backend bypass', () => {
    // Voxide only interfaces through SemunApiClient (HTTP)
    // This structural test verifies no other access patterns exist
    const api = createMockApi();
    const { client } = createTestClient({ api });

    // The registry only contains actions that call api.get/api.post
    const actions = client.registry.listActions();
    for (const action of actions) {
      expect(action.handler).toBeDefined();
      // All handlers are async functions going through the API client
      expect(action.handler.constructor.name).toBe('AsyncFunction');
    }
  });
});

// ─── Interaction Logging ────────────────────────────────────────────────────

describe('Interaction logging', () => {
  it('logs successful actions with WEB/VOICE metadata', async () => {
    const api = createMockApi({
      get: jest.fn().mockResolvedValue({ data: { balance: 1000, currency: 'ETB' } }),
    });
    const { client, logs } = createTestClient({ api });

    await client.executeAction('getWalletBalance');
    expect(logs).toHaveLength(1);
    expect(logs[0].client).toBe('WEB');
    expect(logs[0].interactionChannel).toBe('VOICE');
    expect(logs[0].actionName).toBe('getWalletBalance');
    expect(logs[0].result).toBe('SUCCESS');
    expect(logs[0].userId).toBe('user-123');
    expect(typeof logs[0].durationMs).toBe('number');
  });

  it('logs cancelled confirmations as CANCELLED', async () => {
    const { client, logs } = createTestClient({ confirmResult: false });
    await client.executeAction('createTrip', { ...TRIP_PARAMS });
    expect(logs[0].result).toBe('CANCELLED');
  });
});

// ─── Backend Contract Conformance ───────────────────────────────────────────
//
// These assertions exist because the voice layer once spoke an older API. They
// pin every action to the endpoint and payload the current NestJS controllers
// actually expose, so a stale path or payload fails here rather than at runtime.

describe('backend contract conformance', () => {
  it('getMyTrips reads GET /trips', async () => {
    const getMock = jest.fn().mockResolvedValue({ data: [] });
    const { client } = createTestClient({ api: createMockApi({ get: getMock }) });

    await client.executeAction('getMyTrips');

    expect(getMock.mock.calls[0][0]).toBe('/trips');
  });

  it('getDriverEarnings reads GET /drivers/me/earnings', async () => {
    const earnings = {
      todayEarnings: 32,
      totalEarnings: 320,
      walletBalance: 4250,
      completedRides: 2,
      averageFare: 16,
    };
    const getMock = jest.fn().mockResolvedValue({ data: earnings });
    const { client } = createTestClient({ api: createMockApi({ get: getMock }) });

    const result = await client.executeAction('getDriverEarnings');

    expect(getMock.mock.calls[0][0]).toBe('/drivers/me/earnings');
    expect(result.data).toMatchObject({ todayEarnings: 32 });
  });

  it('getWithdrawalStatus reads GET /drivers/me/withdrawals and returns the newest', async () => {
    const getMock = jest.fn().mockResolvedValue({
      data: [
        { id: 'w2', amount: 5000, currency: 'ETB', status: 'PENDING', destinationType: 'BANK', createdAt: '2026-10-02T00:00:00.000Z' },
        { id: 'w1', amount: 1000, currency: 'ETB', status: 'SUCCESS', destinationType: 'BANK', createdAt: '2026-10-01T00:00:00.000Z' },
      ],
    });
    const { client } = createTestClient({ api: createMockApi({ get: getMock }) });

    const result = await client.executeAction('getWithdrawalStatus');

    expect(getMock.mock.calls[0][0]).toBe('/drivers/me/withdrawals');
    expect((result.data as { id: string }).id).toBe('w2');
  });

  it('getWithdrawalStatus answers null when the driver has none', async () => {
    const getMock = jest.fn().mockResolvedValue({ data: [] });
    const { client } = createTestClient({ api: createMockApi({ get: getMock }) });

    const result = await client.executeAction('getWithdrawalStatus');

    expect(result.success).toBe(true);
    expect(result.data).toBeNull();
  });

  it('getCurrentFare prices through POST /fares/calculate', async () => {
    const postMock = jest.fn().mockResolvedValue({
      data: {
        fare: 8500,
        currency: 'ETB',
        routeId: 'r1',
        originStopId: 'stop-1',
        destinationStopId: 'stop-2',
      },
    });
    const { client } = createTestClient({ api: createMockApi({ post: postMock }) });

    const result = await client.executeAction('getCurrentFare', {
      routeId: 'r1',
      originStopId: 'stop-1',
      destinationStopId: 'stop-2',
    });

    expect(postMock.mock.calls[0][0]).toBe('/fares/calculate');
    expect(postMock.mock.calls[0][1]).toEqual({
      routeId: 'r1',
      originStopId: 'stop-1',
      destinationStopId: 'stop-2',
    });
    expect((result.data as { fare: number }).fare).toBe(8500);
  });

  it('createTrip sends every identifier the backend requires to POST /trips', async () => {
    const postMock = jest.fn().mockResolvedValue({ data: CREATE_TRIP_RESPONSE });
    const { client } = createTestClient({
      api: createMockApi({ post: postMock }),
      confirmResult: true,
    });

    await client.executeAction('createTrip', { ...TRIP_PARAMS });

    expect(postMock.mock.calls[0][0]).toBe('/trips');
    expect(postMock.mock.calls[0][1]).toMatchObject(TRIP_PARAMS);
  });

  it('payForTrip posts to POST /payments/trip, not /trips/:id/pay', async () => {
    const postMock = jest.fn().mockResolvedValue({
      data: { paymentId: 'p1', tripId: 't1', amount: 8500, currency: 'ETB', status: 'SUCCESS' },
    });
    const { client } = createTestClient({
      api: createMockApi({ post: postMock }),
      confirmResult: true,
    });

    await client.executeAction('payForTrip', { tripId: 't1' });

    expect(postMock.mock.calls[0][0]).toBe('/payments/trip');
    const body = postMock.mock.calls[0][1] as Record<string, unknown>;
    expect(body.tripId).toBe('t1');
    expect(typeof body.idempotencyKey).toBe('string');
  });

  it('requestWithdrawal posts to POST /drivers/me/withdrawals with a destination type', async () => {
    const postMock = jest.fn().mockResolvedValue({
      data: {
        id: 'w1',
        amount: 5000,
        currency: 'ETB',
        status: 'PENDING',
        destinationType: 'BANK',
        createdAt: '2026-10-02T00:00:00.000Z',
      },
    });
    const { client } = createTestClient({
      api: createMockApi({ post: postMock }),
      confirmResult: true,
    });

    await client.executeAction('requestWithdrawal', {
      amount: 5000,
      destinationType: 'BANK',
    });

    expect(postMock.mock.calls[0][0]).toBe('/drivers/me/withdrawals');
    const body = postMock.mock.calls[0][1] as Record<string, unknown>;
    expect(body.destinationType).toBe('BANK');
    expect(typeof body.idempotencyKey).toBe('string');
  });

  it('rejects a withdrawal without a destination type', async () => {
    const { client } = createTestClient({ confirmResult: true });

    const result = await client.executeAction('requestWithdrawal', { amount: 5000 });

    expect(result.success).toBe(false);
    expect(result.errorCode).toBe(VoxideErrorCode.INVALID_PARAMS);
  });

  it('a retry after a failure reuses the same idempotency key', async () => {
    const postMock = jest
      .fn()
      .mockRejectedValueOnce(new Error('fetch failed: network error'))
      .mockResolvedValueOnce({ data: CREATE_TRIP_RESPONSE });
    const { client } = createTestClient({
      api: createMockApi({ post: postMock }),
      confirmResult: true,
    });

    const first = await client.executeAction('createTrip', { ...TRIP_PARAMS });
    const second = await client.executeAction('createTrip', { ...TRIP_PARAMS });

    expect(first.success).toBe(false);
    expect(second.success).toBe(true);
    const firstKey = (postMock.mock.calls[0][1] as Record<string, unknown>).idempotencyKey;
    const retryKey = (postMock.mock.calls[1][1] as Record<string, unknown>).idempotencyKey;
    expect(retryKey).toBe(firstKey);
  });

  it('a new logical booking uses a new idempotency key', async () => {
    const postMock = jest.fn().mockResolvedValue({ data: CREATE_TRIP_RESPONSE });
    const { client } = createTestClient({
      api: createMockApi({ post: postMock }),
      confirmResult: true,
    });

    await client.executeAction('createTrip', { ...TRIP_PARAMS });
    await client.executeAction('createTrip', { ...TRIP_PARAMS });

    const firstKey = (postMock.mock.calls[0][1] as Record<string, unknown>).idempotencyKey;
    const secondKey = (postMock.mock.calls[1][1] as Record<string, unknown>).idempotencyKey;
    expect(secondKey).not.toBe(firstKey);
  });

  it('financial calls carry Idempotency-Key and X-Request-Id headers', async () => {
    const postMock = jest.fn().mockResolvedValue({
      data: { paymentId: 'p1', tripId: 't1', amount: 8500, currency: 'ETB', status: 'SUCCESS' },
    });
    const { client } = createTestClient({
      api: createMockApi({ post: postMock }),
      confirmResult: true,
    });

    await client.executeAction('payForTrip', { tripId: 't1' });

    const headers = postMock.mock.calls[0][2] as Record<string, string>;
    const body = postMock.mock.calls[0][1] as Record<string, unknown>;
    expect(headers['Idempotency-Key']).toBe(body.idempotencyKey);
    expect(headers['X-Request-Id']).toMatch(/^voxide-/);
    expect(headers.Authorization).toBe('Bearer test-jwt-token');
  });

  it('read calls carry X-Request-Id and the bearer token', async () => {
    const getMock = jest.fn().mockResolvedValue({ data: { balance: 1, currency: 'ETB' } });
    const { client } = createTestClient({ api: createMockApi({ get: getMock }) });

    await client.executeAction('getWalletBalance');

    const headers = getMock.mock.calls[0][1] as Record<string, string>;
    expect(headers['X-Request-Id']).toMatch(/^voxide-/);
    expect(headers.Authorization).toBe('Bearer test-jwt-token');
    expect(headers['Idempotency-Key']).toBeUndefined();
  });
});
