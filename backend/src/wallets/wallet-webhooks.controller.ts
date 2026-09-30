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
import { DomainException } from '../common/domain.exception';
import { ErrorCode } from '../common/error-codes';

/**
 * Payment provider callbacks.
 *
 * Deliberately *not* behind JwtAuthGuard: the caller is the payment provider,
 * not a signed-in user. Authority comes from verifying the reference with the
 * provider inside TopUpService, not from the request itself.
 *
 * The handler is idempotent — providers retry callbacks, and a duplicate must
 * never credit the wallet twice.
 *
 * TODO(production): verify a provider signature / HMAC header here before
 * trusting the payload.
 */
@ApiTags('Wallet')
@Controller('wallet/webhooks')
export class WalletWebhooksController {
  constructor(private readonly topUpService: TopUpService) {}

  @Post(':provider')
  @HttpCode(HttpStatus.OK)
  @ApiOperation({
    summary: 'Payment provider callback for a top-up (unauthenticated, idempotent)',
  })
  @ApiResponse({ status: 200, description: 'Callback accepted' })
  @ApiResponse({ status: 404, description: 'Unknown provider reference' })
  async handle(
    @Param('provider') provider: string,
    @Body() body: { providerReference?: string; status?: string },
  ) {
    if (!body?.providerReference) {
      throw new DomainException(
        'providerReference is required',
        HttpStatus.BAD_REQUEST,
        ErrorCode.VALIDATION_ERROR,
      );
    }

    const { intent, wallet } = await this.topUpService.settleByProviderReference(
      body.providerReference,
    );

    return {
      data: {
        intentId: intent.id,
        status: intent.status,
        balance: wallet.balance,
      },
      meta: { provider },
    };
  }
}
