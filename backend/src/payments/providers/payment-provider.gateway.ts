import { PaymentProvider as PaymentProviderName } from '../../common/enums';

/**
 * Port for external Ethiopian payment providers (Telebirr, Chapa, banks…).
 *
 * Named `PaymentProviderGateway` rather than `PaymentProvider` so it does not
 * collide with the `PaymentProvider` enum that identifies a provider in DTOs
 * and persisted rows.
 *
 * The wallet/payment core must never depend on a concrete provider: it talks to
 * this interface only, and the concrete implementation is selected from the
 * `PAYMENT_PROVIDER` environment variable.
 */

/** A top-up that has been handed to the provider but not yet confirmed. */
export interface TopUpInitiation {
  /** Provider-side handle used later to verify or reconcile the payment. */
  providerReference: string;
  /** Optional URL the client should open to approve the payment. */
  checkoutUrl?: string;
}

/** Result of asking the provider whether money actually moved. */
export interface ProviderVerification {
  verified: boolean;
  providerReference: string;
  /** Amount the provider confirms, in minor units (santim), when known. */
  amountMinor?: number;
  /** The provider has not reached a final state; neither credit nor fail. */
  pending?: boolean;
  failureReason?: string;
}

export interface WithdrawalInitiation {
  providerReference: string;
}

export interface InitiateTopUpParams {
  userId: string;
  amountMinor: number;
  currency: string;
  idempotencyKey: string;
}

export interface InitiateWithdrawalParams {
  userId: string;
  amountMinor: number;
  currency: string;
  destinationType: string;
  destination?: string;
  destinationAccount?: string;
  idempotencyKey: string;
}

export interface PaymentProviderGateway {
  readonly name: PaymentProviderName;

  /** Creates the payment intent on the provider side. Does not move money. */
  initiateTopUp(params: InitiateTopUpParams): Promise<TopUpInitiation>;

  /**
   * Confirms whether the provider actually settled a transaction. Safe to call
   * repeatedly: callbacks may be delivered more than once.
   */
  verifyTransaction(providerReference: string): Promise<ProviderVerification>;

  /** Hands a withdrawal to the provider. Money moves asynchronously. */
  initiateWithdrawal(
    params: InitiateWithdrawalParams,
  ): Promise<WithdrawalInitiation>;

  /**
   * Authenticates a provider callback (signature, freshness, merchant) and
   * returns the provider reference it is about. Throws on anything invalid.
   */
  parseWebhook(body: unknown): string;
}
