import { IsNumber, IsNotEmpty, IsPositive, IsEnum, IsOptional, IsString } from 'class-validator';
import { ApiProperty } from '@nestjs/swagger';
import { PaymentProvider } from '../../common/enums';

export class TopUpWalletDto {
  @ApiProperty({ description: 'Amount to top-up in minor units (santim)', example: 100000 })
  @IsNumber()
  @IsPositive()
  @IsNotEmpty()
  amount: number;

  @ApiProperty({
    description: 'Payment provider to use for the top-up',
    enum: PaymentProvider,
    default: PaymentProvider.MOCK,
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
