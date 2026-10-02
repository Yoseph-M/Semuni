import {
  Controller,
  Post,
  Param,
  Body,
  HttpCode,
  HttpStatus,
} from '@nestjs/common';
import { ApiTags, ApiOperation, ApiResponse } from '@nestjs/swagger';
import { TopUpService } from './top-up.service';
import { PaymentProviderRegistry } from '../payments/providers/payment-provider.registry';
import { PaymentProvider } from '../common/enums';
import { DomainException } from '../common/domain.exception';
import { ErrorCode } from '../common/error-codes';

/**
 * Payment provider callbacks.
 *
 * Not behind JwtAuthGuard: the caller is the provider. Each gateway
 * authenticates its own callback (Telebirr: RSA signature, notify_time window,
 * merchant ids) before anything happens, and settlement still re-verifies the
 * payment with the provider, so a forged or replayed callback cannot credit a
 * wallet. Settlement is idempotent: provider retries credit at most once.
 */
@ApiTags('Wallet')
@Controller('wallet/webhooks')
export class WalletWebhooksController {
  constructor(
    private readonly topUpService: TopUpService,
    private readonly providerRegistry: PaymentProviderRegistry,
  ) {}

  @Post(':provider')
  @HttpCode(HttpStatus.OK)
  @ApiOperation({
    summary: 'Payment provider callback for a top-up (provider-authenticated, idempotent)',
  })
  @ApiResponse({ status: 200, description: 'Callback accepted' })
  @ApiResponse({ status: 401, description: 'Callback failed authentication' })
  @ApiResponse({ status: 404, description: 'Unknown provider or reference' })
  async handle(@Param('provider') provider: string, @Body() body: unknown) {
    const name = provider.toUpperCase() as PaymentProvider;
    if (!Object.values(PaymentProvider).includes(name)) {
      throw new DomainException(
        'Unknown payment provider',
        HttpStatus.NOT_FOUND,
        ErrorCode.PAYMENT_NOT_FOUND,
      );
    }

    const gateway = this.providerRegistry.get(name);
    const providerReference = gateway.parseWebhook(body);
    const { intent, wallet } = await this.topUpService.settleByProviderReference(
      providerReference,
      name,
    );

    return {
      data: {
        intentId: intent.id,
        status: intent.status,
        balance: wallet.balance,
      },
      meta: { provider: name },
    };
  }
}
