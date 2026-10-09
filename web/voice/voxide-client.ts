/**
 * Voxide Client — High-level Voice Action Orchestrator
 *
 * Integrates the VoxideActionRegistry with:
 *  - **State Binding**: Binds safe contextual state (screen, route, fare, balance).
 *    Strictly strips authentication secrets, private keys, and refresh tokens.
 *  - **Confirmation Interceptor**: Dangerous actions generate explicit confirmation
 *    context and halt execution until the user confirms.
 *  - **Action Middleware**: Checks active JWT session, rate limits, and logs
 *    interactions as `{ client: 'WEB', interactionChannel: 'VOICE' }`.
 *  - **Idempotency**: Generates deterministic UUIDs for financial mutations.
 *    On network error/timeout, reconciles with the same key rather than submitting
 *    duplicate requests.
 */
import {
  VoxideActionResult,
  VoxideClientState,
  VoxideConfirmationContext,
  VoxideErrorCode,
  VoxideInteractionLog,
  VoxideMiddlewareContext,
} from './voxide.types';
import { VoxideActionRegistry, SemunApiClient, createDefaultRegistry } from './voxide-action-registry';

// ─── Confirmation Handler ────────────────────────────────────────────────────

/**
 * Callback invoked for dangerous actions. Must present the context to the user
 * and return true if they confirm, false if they cancel.
 */
export type ConfirmationHandler = (context: VoxideConfirmationContext) => Promise<boolean>;

/**
 * Optional callback to receive structured interaction logs.
 */
export type InteractionLogger = (log: VoxideInteractionLog) => void;

// ─── Idempotency Key Generator ───────────────────────────────────────────────

/**
 * Generates a UUID v4 using crypto.randomUUID if available, otherwise falls
 * back to a timestamp+random approach. The key is cached per action+params
 * so a retry after a network error reuses the same key.
 */
function generateIdempotencyKey(): string {
  if (typeof crypto !== 'undefined' && typeof crypto.randomUUID === 'function') {
    return crypto.randomUUID();
  }
  // Fallback for environments without crypto.randomUUID
  return `${Date.now()}-${Math.random().toString(36).slice(2, 11)}`;
}

// ─── Rate Limiter ────────────────────────────────────────────────────────────

class SimpleRateLimiter {
  private readonly timestamps: number[] = [];
  constructor(
    private readonly maxRequests: number,
    private readonly windowMs: number,
  ) {}

  tryAcquire(): boolean {
    const now = Date.now();
    // Prune expired entries
    while (this.timestamps.length > 0 && this.timestamps[0] <= now - this.windowMs) {
      this.timestamps.shift();
    }
    if (this.timestamps.length >= this.maxRequests) {
      return false;
    }
    this.timestamps.push(now);
    return true;
  }
}

// ─── Voxide Client ───────────────────────────────────────────────────────────

export class VoxideClient {
  readonly registry: VoxideActionRegistry;
  private clientState: VoxideClientState = {};
  private readonly rateLimiter: SimpleRateLimiter;
  private readonly pendingIdempotencyKeys = new Map<string, string>();
  private confirmationHandler: ConfirmationHandler;
  private interactionLogger?: InteractionLogger;

  constructor(options: {
    apiClient: SemunApiClient;
    getAccessToken: () => string | null;
    getUserId: () => string | null;
    getUserRole: () => string | null;
    confirmationHandler: ConfirmationHandler;
    interactionLogger?: InteractionLogger;
    /** Max voice actions per minute (default: 30). */
    rateLimit?: number;
  }) {
    const authHeaders = (): Record<string, string> => {
      const token = options.getAccessToken();
      if (!token) return {};
      return { Authorization: `Bearer ${token}` };
    };

    this.registry = createDefaultRegistry(options.apiClient, authHeaders);
    this.confirmationHandler = options.confirmationHandler;
    this.interactionLogger = options.interactionLogger;
    this.rateLimiter = new SimpleRateLimiter(options.rateLimit ?? 30, 60_000);

    this._getAccessToken = options.getAccessToken;
    this._getUserId = options.getUserId;
    this._getUserRole = options.getUserRole;
  }

  private readonly _getAccessToken: () => string | null;
  private readonly _getUserId: () => string | null;
  private readonly _getUserRole: () => string | null;

  // ── State Binding ──────────────────────────────────────────────────────

  /**
   * Update the safe client state. Any authentication secrets, private keys,
   * or refresh tokens present in the input are stripped.
   */
  updateState(state: Partial<VoxideClientState>): void {
    // Strip dangerous fields if they somehow sneak in
    const safe = { ...state } as Record<string, unknown>;
    const dangerousKeys = [
      'accessToken', 'refreshToken', 'token', 'secret', 'privateKey',
      'password', 'apiKey', 'appSecret', 'credentials',
    ];
    for (const key of dangerousKeys) {
      delete safe[key];
    }
    this.clientState = { ...this.clientState, ...safe as Partial<VoxideClientState> };
  }

  getState(): Readonly<VoxideClientState> {
    return { ...this.clientState };
  }

  // ── Action Execution ───────────────────────────────────────────────────

  /**
   * Execute a voice action with full middleware pipeline:
   * 1. Rate limiting
   * 2. Session validation
   * 3. Parameter validation (handled by registry)
   * 4. Confirmation (for dangerous actions)
   * 5. Idempotency key injection (for financial actions)
   * 6. Execution
   * 7. Logging
   */
  async executeAction(
    actionName: string,
    params: Record<string, unknown> = {},
  ): Promise<VoxideActionResult> {
    const startTime = Date.now();

    // 1. Rate limiting
    if (!this.rateLimiter.tryAcquire()) {
      const result: VoxideActionResult = {
        success: false,
        errorCode: VoxideErrorCode.RATE_LIMITED,
        errorMessage: 'Too many voice requests. Please wait a moment.',
      };
      this.logInteraction(actionName, result, startTime);
      return result;
    }

    // 2. Session validation
    const token = this._getAccessToken();
    if (!token) {
      const result: VoxideActionResult = {
        success: false,
        errorCode: VoxideErrorCode.AUTH_EXPIRED,
        errorMessage: 'Your session has expired. Please sign in again.',
      };
      this.logInteraction(actionName, result, startTime);
      return result;
    }

    // 3. Check action exists
    const action = this.registry.get(actionName);
    if (!action) {
      const result: VoxideActionResult = {
        success: false,
        errorCode: VoxideErrorCode.UNKNOWN_ACTION,
        errorMessage: `Unknown voice action: ${actionName}`,
      };
      this.logInteraction(actionName, result, startTime);
      return result;
    }

    // 4. Confirmation for dangerous actions
    if (action.dangerous) {
      const context = this.buildConfirmationContext(actionName, params);
      let confirmed: boolean;
      try {
        confirmed = await this.confirmationHandler(context);
      } catch {
        confirmed = false;
      }
      if (!confirmed) {
        const result: VoxideActionResult = {
          success: false,
          errorCode: VoxideErrorCode.CONFIRMATION_CANCELLED,
          errorMessage: 'Action cancelled by user.',
        };
        this.logInteraction(actionName, result, startTime);
        return result;
      }
    }

    // 5. Idempotency key injection for financial mutations
    if (action.dangerous) {
      const actionKey = `${actionName}:${JSON.stringify(params)}`;
      let idempotencyKey = this.pendingIdempotencyKeys.get(actionKey);
      if (!idempotencyKey) {
        idempotencyKey = generateIdempotencyKey();
        this.pendingIdempotencyKeys.set(actionKey, idempotencyKey);
      }
      params = { ...params, idempotencyKey };
    }

    // 6. Execute
    const result = await this.registry.execute(actionName, params);

    // 7. Clean up idempotency key on success (keep on failure for retry)
    if (result.success && action.dangerous) {
      const actionKey = `${actionName}:${JSON.stringify(
        // Reconstruct without idempotency key for lookup
        Object.fromEntries(
          Object.entries(params).filter(([k]) => k !== 'idempotencyKey'),
        ),
      )}`;
      this.pendingIdempotencyKeys.delete(actionKey);
    }

    // 8. Log
    this.logInteraction(actionName, result, startTime);
    return result;
  }

  // ── Confirmation Context Builder ───────────────────────────────────────

  private buildConfirmationContext(
    actionName: string,
    params: Record<string, unknown>,
  ): VoxideConfirmationContext {
    const details: Record<string, string | number> = {};

    switch (actionName) {
      case 'createTrip':
        details.routeId = String(params.routeId ?? '');
        if (this.clientState.selectedRouteName) {
          details.routeName = this.clientState.selectedRouteName;
        }
        if (this.clientState.currentFare !== undefined) {
          details.fare = this.clientState.currentFare;
        }
        if (this.clientState.currentBalance !== undefined) {
          details.currentBalance = this.clientState.currentBalance;
          if (this.clientState.currentFare !== undefined) {
            details.remainingBalance =
              this.clientState.currentBalance - this.clientState.currentFare;
          }
        }
        return {
          actionName,
          summary: `Book a trip on ${details.routeName ?? details.routeId}?`,
          details,
        };

      case 'payForTrip':
        details.tripId = String(params.tripId ?? '');
        if (this.clientState.activeTrip?.fare !== undefined) {
          details.fare = this.clientState.activeTrip.fare;
        }
        if (this.clientState.currentBalance !== undefined) {
          details.currentBalance = this.clientState.currentBalance;
        }
        return {
          actionName,
          summary: `Pay for trip ${details.tripId}?`,
          details,
        };

      case 'initiateTopUp':
        details.amount = Number(params.amount ?? 0);
        if (this.clientState.currentBalance !== undefined) {
          details.currentBalance = this.clientState.currentBalance;
          details.balanceAfter = this.clientState.currentBalance + details.amount;
        }
        return {
          actionName,
          summary: `Top up wallet with ${details.amount} santim?`,
          details,
        };

      case 'requestWithdrawal':
        details.amount = Number(params.amount ?? 0);
        if (this.clientState.currentBalance !== undefined) {
          details.currentBalance = this.clientState.currentBalance;
          details.balanceAfter = this.clientState.currentBalance - details.amount;
        }
        return {
          actionName,
          summary: `Withdraw ${details.amount} santim?`,
          details,
        };

      default:
        return {
          actionName,
          summary: `Execute ${actionName}?`,
          details: params as Record<string, string | number>,
        };
    }
  }

  // ── Interaction Logging ────────────────────────────────────────────────

  private logInteraction(
    actionName: string,
    result: VoxideActionResult,
    startTime: number,
  ): void {
    if (!this.interactionLogger) return;

    const log: VoxideInteractionLog = {
      client: 'WEB',
      interactionChannel: 'VOICE',
      actionName,
      userId: this._getUserId(),
      timestamp: new Date().toISOString(),
      result: result.success
        ? 'SUCCESS'
        : result.errorCode === VoxideErrorCode.CONFIRMATION_CANCELLED
          ? 'CANCELLED'
          : 'FAILED',
      errorCode: result.errorCode,
      durationMs: Date.now() - startTime,
    };
    this.interactionLogger(log);
  }
}
