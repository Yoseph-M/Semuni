import {
  IsInt,
  IsPositive,
  IsNotEmpty,
  IsEnum,
  IsOptional,
  IsString,
} from 'class-validator';
import { ApiProperty } from '@nestjs/swagger';
import {
  WithdrawalDestinationType,
  PaymentProvider,
} from '../../common/enums';

export class RequestWithdrawalDto {
  @ApiProperty({ description: 'Amount in minor units (santim)' })
  // Integer minor units only: the wallet holds integers, and a fractional
  // withdrawal would be rounded somewhere below, silently changing the amount.
  @IsInt()
  @IsPositive()
  @IsNotEmpty()
  amount: number;

  @ApiProperty({
    enum: WithdrawalDestinationType,
    default: WithdrawalDestinationType.BANK,
  })
  @IsEnum(WithdrawalDestinationType)
  @IsNotEmpty()
  destinationType: WithdrawalDestinationType;

  @ApiProperty({ example: 'Commercial Bank of Ethiopia', required: false })
  @IsOptional()
  @IsString()
  destination?: string;

  @ApiProperty({ example: 'Destination account number / mobile reference', required: false })
  @IsOptional()
  @IsString()
  destinationAccount?: string;

  @ApiProperty({
    enum: PaymentProvider,
    default: PaymentProvider.MOCK,
    required: false,
  })
  @IsOptional()
  @IsEnum(PaymentProvider)
  provider?: PaymentProvider;

  @ApiProperty({
    description:
      'Idempotency key (client-generated unique key) to prevent duplicate withdrawal requests',
    example: 'wd-driver1-20260928-001',
  })
  @IsString()
  @IsNotEmpty()
  idempotencyKey: string;
}
