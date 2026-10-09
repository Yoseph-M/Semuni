import { Module } from '@nestjs/common';
import { TypeOrmModule } from '@nestjs/typeorm';
import { Withdrawal } from './entities/withdrawal.entity';
import { WithdrawalsService } from './withdrawals.service';
import { WithdrawalsController } from './withdrawals.controller';
import { Wallet } from '../wallets/entities/wallet.entity';
import { WalletsService } from '../wallets/wallets.service';
import { LedgerService } from '../ledger/ledger.service';
import { LedgerEntry } from '../ledger/entities/ledger-entry.entity';
import { PaymentProvidersModule } from '../payments/providers/payment-providers.module';

@Module({
  imports: [
    TypeOrmModule.forFeature([Withdrawal, Wallet, LedgerEntry]),
    PaymentProvidersModule,
  ],
  providers: [WithdrawalsService, WalletsService, LedgerService],
  controllers: [WithdrawalsController],
  exports: [WithdrawalsService],
})
export class WithdrawalsModule {}
