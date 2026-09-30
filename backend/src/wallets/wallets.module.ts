import { Module } from '@nestjs/common';
import { TypeOrmModule } from '@nestjs/typeorm';
import { Wallet } from './entities/wallet.entity';
import { TopUpIntent } from './entities/top-up-intent.entity';
import { WalletsService } from './wallets.service';
import { TopUpService } from './top-up.service';
import { WalletsController } from './wallets.controller';
import { WalletWebhooksController } from './wallet-webhooks.controller';
import { LedgerEntry } from '../ledger/entities/ledger-entry.entity';
import { LedgerService } from '../ledger/ledger.service';
import { PaymentProvidersModule } from '../payments/providers/payment-providers.module';
import { CustomLogger } from '../common/logger/custom.logger';

@Module({
  imports: [
    TypeOrmModule.forFeature([Wallet, LedgerEntry, TopUpIntent]),
    PaymentProvidersModule,
  ],
  providers: [WalletsService, LedgerService, TopUpService, CustomLogger],
  controllers: [WalletsController, WalletWebhooksController],
  exports: [WalletsService, TopUpService, TypeOrmModule],
})
export class WalletsModule {}
