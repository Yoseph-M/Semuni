import { IsInt, IsNotEmpty, IsPositive, IsEnum, IsOptional, IsString } from 'class-validator';
import { ApiProperty } from '@nestjs/swagger';
import { PaymentProvider } from '../../common/enums';

export class TopUpWalletDto {
  @ApiProperty({ description: 'Amount to top-up in minor units (santim)', example: 100000 })
  // Money is integer minor units. A fractional amount is not representable in
  // the ledger, so it is rejected at the edge rather than rounded silently.
  @IsInt()
  @IsPositive()
  @IsNotEmpty()
  amount: number;

  @ApiProperty({
    enum: PaymentProvider,
    description: 'Defaults to the configured PAYMENT_PROVIDER',
    required: false,
  })
  @IsOptional()
  @IsEnum(PaymentProvider)
  provider?: PaymentProvider;

  @ApiProperty({
    description: 'Idempotency key (client-generated unique key) to prevent duplicate top-ups',
    example: 'topup-abc123-xyz',
  })
  @IsString()
  @IsNotEmpty()
  idempotencyKey: string;
}
