import { IsString, IsNotEmpty, IsUUID, MaxLength } from 'class-validator';
import { ApiProperty } from '@nestjs/swagger';
import { Payment } from '../entities/payment.entity';
import { Currency, PaymentProvider, PaymentRecordStatus } from '../../common/enums';

export class ProcessTripPaymentDto {
  @ApiProperty({ description: 'Trip ID to pay for' })
  @IsUUID()
  @IsNotEmpty()
  tripId: string;

  @ApiProperty({
    description:
      'Client-generated idempotency key to prevent double payments. Keys are scoped to the authenticated passenger: the same key reused for a different trip is an IDEMPOTENCY_CONFLICT.',
  })
  @IsString()
  @IsNotEmpty()
  @MaxLength(128)
  idempotencyKey: string;
}

/**
 * Payment as returned to clients.
 *
 * Deliberately omits `idempotencyKey` (the client already knows its own key, and
 * other users must never see it) and `providerReference` (internal settlement
 * data, surfaced only to reconciliation tooling).
 */
export interface PaymentResponse {
  id: string;
  tripId: string;
  passengerId: string;
  driverId: string;
  routeId?: string;
  amount: number;
  currency: Currency;
  status: PaymentRecordStatus;
  provider: PaymentProvider;
  receiptNumber?: string;
  completedAt?: Date;
  createdAt: Date;
}

export function toPaymentResponse(payment: Payment): PaymentResponse {
  return {
    id: payment.id,
    tripId: payment.tripId,
    passengerId: payment.passengerId,
    driverId: payment.driverId,
    routeId: payment.routeId,
    amount: payment.amount,
    currency: payment.currency,
    status: payment.status,
    provider: payment.provider,
    receiptNumber: payment.receiptNumber,
    completedAt: payment.completedAt,
    createdAt: payment.createdAt,
  };
}
