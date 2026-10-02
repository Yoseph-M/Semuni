import {
  Controller,
  Get,
  Post,
  Body,
  Param,
  UseGuards,
  ParseUUIDPipe,
} from '@nestjs/common';
import {
  ApiTags,
  ApiOperation,
  ApiBearerAuth,
  ApiResponse,
} from '@nestjs/swagger';
import { WalletsService } from './wallets.service';
import { TopUpService } from './top-up.service';
import { TopUpWalletDto } from './dto/wallet.dto';
import { JwtAuthGuard } from '../auth/guards/jwt-auth.guard';
import { RolesGuard } from '../auth/guards/roles.guard';
import { CurrentUser } from '../auth/decorators/current-user.decorator';
import { User } from '../users/entities/user.entity';

@ApiTags('Wallet')
@Controller('wallet')
@ApiBearerAuth('access-token')
@UseGuards(JwtAuthGuard, RolesGuard)
export class WalletsController {
  constructor(
    private readonly walletsService: WalletsService,
    private readonly topUpService: TopUpService,
  ) {}

  @Get()
  @ApiOperation({ summary: 'Get current user wallet with balance' })
  async getWallet(@CurrentUser() user: User) {
    const wallet = await this.walletsService.getWalletByUserId(user.id);
    return {
      data: {
        id: wallet.id,
        balance: wallet.balance,
        currency: wallet.currency,
        status: wallet.status,
      },
      meta: {},
    };
  }

  @Get('transactions')
  @ApiOperation({
    summary: 'Get wallet transaction history (ledger entries) for current user',
  })
  async getTransactions(@CurrentUser() user: User) {
    const entries = await this.walletsService.getWalletTransactions(user.id);
    return { data: entries, meta: {} };
  }

  @Post('top-up')
  @ApiOperation({
    summary:
      'Initiate a wallet top-up (idempotent). Returns a PENDING intent — the balance is only credited once the provider confirms it.',
  })
  @ApiResponse({
    status: 201,
    description: 'Top-up intent created; awaiting provider confirmation',
  })
  async initiateTopUp(
    @CurrentUser() user: User,
    @Body() dto: TopUpWalletDto,
  ) {
    const intent = await this.topUpService.initiate(user.id, dto);
    return {
      data: {
        intentId: intent.id,
        amount: intent.amountMinor,
        currency: intent.currency,
        provider: intent.provider,
        status: intent.status,
        providerReference: intent.providerReference,
        checkoutUrl: intent.checkoutUrl,
      },
      meta: {
        message:
          'Top-up initiated. The wallet is credited once the payment provider confirms.',
      },
    };
  }

  @Post('top-up/:intentId/confirm')
  @ApiOperation({
    summary:
      'Confirm a top-up after paying the provider. Verifies with the provider, then credits the wallet exactly once (idempotent).',
  })
  async confirmTopUp(
    @CurrentUser() user: User,
    @Param('intentId', ParseUUIDPipe) intentId: string,
  ) {
    const { intent, wallet } = await this.topUpService.confirm(
      user.id,
      intentId,
    );
    return {
      data: {
        intentId: intent.id,
        status: intent.status,
        balance: wallet.balance,
        currency: wallet.currency,
      },
      meta: { message: 'Wallet topped up successfully' },
    };
  }

  @Get('top-ups')
  @ApiOperation({ summary: 'List my top-up intents' })
  async listTopUps(@CurrentUser() user: User) {
    const intents = await this.topUpService.listMine(user.id);
    return { data: intents, meta: {} };
  }
}
