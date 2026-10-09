import { Module } from '@nestjs/common';
import { ConfigModule } from '@nestjs/config';
import { LinksEtClient } from './links-et.client';
import { LinksEtReceiptVerifier } from './links-et.receipt-verifier';

@Module({
  imports: [ConfigModule],
  providers: [LinksEtClient, LinksEtReceiptVerifier],
  exports: [LinksEtClient, LinksEtReceiptVerifier],
})
export class LinksEtModule {}
