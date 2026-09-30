import { Module } from '@nestjs/common';
import { MockPaymentProvider } from './mock-payment-provider';
import { PaymentProviderRegistry } from './payment-provider.registry';

/**
 * Owns the payment provider implementations.
 *
 * Exports only the registry, so consumers depend on the abstraction rather than
 * on a concrete provider.
 */
@Module({
  providers: [MockPaymentProvider, PaymentProviderRegistry],
  exports: [PaymentProviderRegistry],
})
export class PaymentProvidersModule {}
