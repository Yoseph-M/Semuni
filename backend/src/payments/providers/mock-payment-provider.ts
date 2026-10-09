import { HttpStatus, Injectable } from '@nestjs/common';
import { DomainException } from '../../common/domain.exception';
import { ErrorCode } from '../../common/error-codes';
import { PaymentProvider as PaymentProviderName } from '../../common/enums';
import {
  InitiateTopUpParams,
  InitiateWithdrawalParams,
  PaymentProviderGateway,
  ProviderVerification,
  TopUpInitiation,
  WithdrawalInitiation,
} from './payment-provider.gateway';

/**
 * Deterministic, in-process payment provider for development and tests.
 *
 * It holds no credentials and performs no network calls. It always confirms a
 * well-formed reference, which lets the complete
 * initiate -> verify -> credit flow be exercised end to end.
 *
 * Never use this in production.
 */
@Injectable()
export class MockPaymentProvider implements PaymentProviderGateway {
  readonly name = PaymentProviderName.MOCK;

  private static readonly TOP_UP_PREFIX = 'MOCK-TOPUP-';
  private static readonly WITHDRAWAL_PREFIX = 'MOCK-WD-';

  async initiateTopUp(params: InitiateTopUpParams): Promise<TopUpInitiation> {
    // Deriving the reference from the idempotency key makes initiation itself
    // repeatable: the same key always yields the same provider reference.
    return {
      providerReference: `${MockPaymentProvider.TOP_UP_PREFIX}${params.idempotencyKey}`,
    };
  }

  async verifyTransaction(
    providerReference: string,
  ): Promise<ProviderVerification> {
    const recognised =
      providerReference.startsWith(MockPaymentProvider.TOP_UP_PREFIX) ||
      providerReference.startsWith(MockPaymentProvider.WITHDRAWAL_PREFIX);

    return {
      verified: recognised,
      providerReference,
      failureReason: recognised ? undefined : 'Unrecognised mock reference',
    };
  }

  async initiateWithdrawal(
    params: InitiateWithdrawalParams,
  ): Promise<WithdrawalInitiation> {
    return {
      providerReference: `${MockPaymentProvider.WITHDRAWAL_PREFIX}${params.idempotencyKey}`,
    };
  }

  parseWebhook(body: unknown): string {
    const reference = (body as { providerReference?: unknown } | undefined)
      ?.providerReference;
    if (typeof reference !== 'string' || !reference) {
      throw new DomainException(
        'providerReference is required',
        HttpStatus.BAD_REQUEST,
        ErrorCode.VALIDATION_ERROR,
      );
    }
    return reference;
  }
}
