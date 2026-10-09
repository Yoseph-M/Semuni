import { Injectable, Logger } from '@nestjs/common';
import { Currency } from '../common/enums';
import { majorToMinor } from '../payments/providers/telebirr/telebirr-payment-provider';
import { LinksEtClient } from './links-et.client';
import {
  LinksEtInvalidReceiptException,
  LinksEtVerificationMismatchException,
} from './links-et.errors';
import {
  ExternalPaymentStatus,
  ExternalReceiptVerifier,
  LinksEtReceiptDetails,
  LinksEtVerifyImageRequest,
  LinksEtVerifyRequest,
  LinksEtVerifyResponse,
  VerifiedExternalPayment,
} from './links-et.types';

@Injectable()
export class LinksEtReceiptVerifier implements ExternalReceiptVerifier {
  private readonly logger = new Logger(LinksEtReceiptVerifier.name);

  constructor(private readonly client: LinksEtClient) {}

  /**
   * Verify an external receipt by reference code or URL.
   */
  async verify(payload: LinksEtVerifyRequest): Promise<VerifiedExternalPayment> {
    if (!payload.reference && !payload.url) {
      throw new LinksEtInvalidReceiptException(
        'Either receipt reference or URL must be provided',
      );
    }

    const response = await this.client.verify(payload);
    return this.normalizeResponse(response, payload.url);
  }

  /**
   * Verify an external receipt screenshot image.
   *
   * CRITICAL SECURITY REQUIREMENT (Section 26):
   * Never trust raw OCR text alone without upstream provider verification.
   */
  async verifyImage(payload: LinksEtVerifyImageRequest): Promise<VerifiedExternalPayment> {
    if (!payload.imageBase64 || payload.imageBase64.trim() === '') {
      throw new LinksEtInvalidReceiptException('Image payload cannot be empty');
    }

    const response = await this.client.verifyImage(payload);

    // Ensure upstream verified the receipt with the issuing bank/rail
    const isUpstreamVerified =
      response.upstream?.verified === true ||
      response.upstream?.status === 'VERIFIED' ||
      response.upstream?.status === 'SUCCESS' ||
      (response.success && response.receipt && !response.detection);

    if (!isUpstreamVerified) {
      throw new LinksEtInvalidReceiptException(
        'Receipt screenshot failed upstream verification: unverified OCR detections cannot be trusted for settlement',
      );
    }

    return this.normalizeResponse(response);
  }

  /**
   * Normalizes heterogeneous links.et response objects into Semuni's canonical VerifiedExternalPayment.
   */
  private normalizeResponse(
    response: LinksEtVerifyResponse,
    resolvedUrl?: string,
  ): VerifiedExternalPayment {
    // Prefer upstream.result.receipt if available, then top-level receipt
    const receipt: LinksEtReceiptDetails =
      response.upstream?.result?.receipt ?? response.receipt ?? {};

    const rawProvider = (receipt.provider ?? response.provider ?? '').toLowerCase();
    if (!rawProvider) {
      throw new LinksEtInvalidReceiptException('Receipt missing payment provider identification');
    }

    const resMap = response as Record<string, unknown>;
    const providerReference =
      receipt.provider_reference ??
      receipt.merch_order_id ??
      receipt.trans_id ??
      (typeof resMap.providerReference === 'string' ? resMap.providerReference : undefined);

    if (!providerReference || typeof providerReference !== 'string') {
      throw new LinksEtInvalidReceiptException(
        'Receipt missing canonical provider reference',
      );
    }

    const receiptReference =
      receipt.receipt_id ??
      (typeof resMap.receiptReference === 'string'
        ? resMap.receiptReference
        : typeof resMap.id === 'string'
          ? resMap.id
          : `LET_${providerReference}`);

    const rawAmount = receipt.total_amount ?? receipt.amount ?? resMap.amount;
    const amountMinor = this.parseAmountMinor(rawAmount);
    if (amountMinor === undefined || amountMinor <= 0) {
      throw new LinksEtInvalidReceiptException(
        `Invalid or missing payment amount on receipt: ${rawAmount}`,
      );
    }

    const rawCurrency = (
      receipt.currency ??
      (typeof resMap.currency === 'string' ? resMap.currency : 'ETB')
    ).toUpperCase();
    if (rawCurrency !== 'ETB') {
      throw new LinksEtVerificationMismatchException(
        `Unsupported receipt currency: ${rawCurrency}. Semuni only operates in ETB.`,
      );
    }

    const status = this.normalizeStatus(receipt.status ?? response.status);

    const paymentDate = this.parsePaymentDate(
      receipt.timestamp ??
        receipt.payment_date ??
        (typeof resMap.paymentDate === 'string' ? resMap.paymentDate : undefined),
    );

    const rawMetadata: Record<string, unknown> = {
      provider: rawProvider,
      upstreamStatus: response.upstream?.status,
      receiptId: receiptReference,
    };

    return {
      provider: rawProvider,
      providerReference,
      amountMinor,
      currency: Currency.ETB,
      status,
      payerReference: receipt.payer,
      destinationReference: receipt.destination,
      receiptReference,
      paymentDate,
      source: 'links.et',
      resolvedUrl: receipt.short_url ?? resolvedUrl,
      verifiedAt: new Date(),
      rawMetadata,
    };
  }

  private normalizeStatus(statusRaw?: string): ExternalPaymentStatus {
    const s = (statusRaw ?? '').toUpperCase();
    if (s === 'SUCCESS' || s === 'COMPLETED' || s === 'PAID') {
      return 'SUCCESS';
    }
    if (s === 'FAILED' || s === 'CANCELLED' || s === 'REJECTED') {
      return 'FAILED';
    }
    return 'PENDING';
  }

  private parseAmountMinor(rawAmount: unknown): number | undefined {
    if (rawAmount === undefined || rawAmount === null) return undefined;
    if (typeof rawAmount === 'number') {
      return Math.round(rawAmount * 100);
    }
    if (typeof rawAmount === 'string') {
      const parsed = majorToMinor(rawAmount);
      if (parsed !== undefined) return parsed;
      const num = parseFloat(rawAmount);
      if (!Number.isNaN(num) && Number.isFinite(num)) {
        return Math.round(num * 100);
      }
    }
    return undefined;
  }

  private parsePaymentDate(dateRaw: unknown): Date {
    if (typeof dateRaw === 'number') {
      return new Date(dateRaw > 1e12 ? dateRaw : dateRaw * 1000);
    }
    if (typeof dateRaw === 'string') {
      const parsed = new Date(dateRaw);
      if (!Number.isNaN(parsed.getTime())) return parsed;
    }
    return new Date();
  }
}
