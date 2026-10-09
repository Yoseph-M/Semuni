import { Injectable, HttpStatus } from '@nestjs/common';
import { ConfigService } from '@nestjs/config';
import { PaymentProvider as PaymentProviderName } from '../../common/enums';
import { DomainException } from '../../common/domain.exception';
import { ErrorCode } from '../../common/error-codes';
import { MockPaymentProvider } from './mock-payment-provider';
import { PaymentProviderGateway } from './payment-provider.gateway';
import { TelebirrPaymentProvider } from './telebirr/telebirr-payment-provider';

/**
 * Resolves the concrete provider implementation.
 *
 * The wallet core asks for a gateway by name and never branches on the concrete
 * class. A provider a client asks for explicitly gets the same checks as the
 * configured default, so a request body cannot pick the mock in production.
 */
@Injectable()
export class PaymentProviderRegistry {
  constructor(
    private readonly configService: ConfigService,
    private readonly mockProvider: MockPaymentProvider,
    private readonly telebirrProvider: TelebirrPaymentProvider,
  ) {}

  /** The provider used when a request does not name one. */
  defaultProvider(): PaymentProviderName {
    return (this.configService.get<string>('PAYMENT_PROVIDER') ??
      PaymentProviderName.MOCK).toUpperCase() as PaymentProviderName;
  }

  get(requested?: PaymentProviderName): PaymentProviderGateway {
    const selected = requested ?? this.defaultProvider();

    switch (selected) {
      case PaymentProviderName.MOCK:
        if (this.configService.get<string>('NODE_ENV') === 'production') {
          throw this.notAvailable(selected);
        }
        return this.mockProvider;
      case PaymentProviderName.TELEBIRR:
        return this.telebirrProvider;
      default:
        // Fail loudly rather than silently degrading to the mock provider,
        // which would create the illusion of a settled payment.
        throw this.notAvailable(selected);
    }
  }

  private notAvailable(provider: string): DomainException {
    return new DomainException(
      `Payment provider ${provider} is not available`,
      HttpStatus.NOT_IMPLEMENTED,
      ErrorCode.PAYMENT_PROVIDER_UNAVAILABLE,
    );
  }
}
