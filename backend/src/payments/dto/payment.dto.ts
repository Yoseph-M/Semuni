import { IsString, IsNotEmpty, IsUUID } from 'class-validator';
import { ApiProperty } from '@nestjs/swagger';

export class ProcessTripPaymentDto {
  @ApiProperty({ description: 'Trip ID to pay for' })
  @IsUUID()
  @IsNotEmpty()
  tripId: string;

  @ApiProperty({ description: 'Client-generated idempotency key to prevent double payments' })
  @IsString()
  @IsNotEmpty()
  idempotencyKey: string;
}
