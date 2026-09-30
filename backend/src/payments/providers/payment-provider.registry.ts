import { Injectable, HttpStatus } from '@nestjs/common';
import { ConfigService } from '@nestjs/config';
import { PaymentProvider as PaymentProviderName } from '../../common/enums';
import { DomainException } from '../../common/domain.exception';
import { ErrorCode } from '../../common/error-codes';
import { MockPaymentProvider } from './mock-payment-provider';
import { PaymentProviderGateway } from './payment-provider.gateway';

/**
 * Resolves the concrete provider implementation.
 *
 * The wallet core asks for a gateway by name and never branches on the concrete
 * class, so adding Telebirr/Chapa later means registering another implementation
 * here rather than touching payment logic.
 */
@Injectable()
export class PaymentProviderRegistry {
  constructor(
    private readonly configService: ConfigService,
    private readonly mockProvider: MockPaymentProvider,
  ) {}

  get(requested?: PaymentProviderName): PaymentProviderGateway {
    const selected =
      requested ??
      (this.configService.get<string>(
        'PAYMENT_PROVIDER',
        PaymentProviderName.MOCK,
      ) as PaymentProviderName);

    switch (selected) {
      case PaymentProviderName.MOCK:
        return this.mockProvider;
      default:
        // Fail loudly rather than silently degrading to the mock provider,
        // which would create the illusion of a settled payment.
        throw new DomainException(
          `Payment provider ${selected} is not configured yet`,
          HttpStatus.NOT_IMPLEMENTED,
          ErrorCode.PAYMENT_FAILED,
        );
    }
  }
}
