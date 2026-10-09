import { Currency } from '../common/enums';

export type ExternalPaymentStatus = 'SUCCESS' | 'FAILED' | 'PENDING';

/**
 * Normalized result of verifying an external receipt or payment via links.et.
 * This canonical representation isolates semuni from upstream provider variations.
 */
export interface VerifiedExternalPayment {
  provider: string;
  providerReference: string;
  amountMinor: number;
  currency: Currency;
  status: ExternalPaymentStatus;
  payerReference?: string;
  destinationReference?: string;
  receiptReference: string;
  paymentDate: Date;
  source: 'links.et';
  resolvedUrl?: string;
  verifiedAt: Date;
  rawMetadata?: Record<string, unknown>;
}

/**
 * Receipt verifier abstraction for external receipt settlement.
 */
export interface ExternalReceiptVerifier {
  verify(payload: LinksEtVerifyRequest): Promise<VerifiedExternalPayment>;
  verifyImage(payload: LinksEtVerifyImageRequest): Promise<VerifiedExternalPayment>;
}

export interface LinksEtVerifyRequest {
  reference?: string;
  url?: string;
  idempotencyKey?: string;
}

export interface LinksEtVerifyImageRequest {
  imageBase64: string;
  mimeType?: string;
  idempotencyKey?: string;
}

export interface LinksEtReceiptDetails {
  provider?: string;
  provider_reference?: string;
  merch_order_id?: string;
  trans_id?: string;
  amount?: number | string;
  total_amount?: number | string;
  currency?: string;
  status?: string;
  payer?: string;
  destination?: string;
  timestamp?: string | number;
  payment_date?: string;
  receipt_id?: string;
  short_url?: string;
  [key: string]: unknown;
}

export interface LinksEtVerifyResponse {
  success: boolean;
  status?: 'SUCCESS' | 'FAILED' | 'PENDING' | 'QUEUED' | 'PROCESSING';
  provider?: string;
  receipt?: LinksEtReceiptDetails;
  upstream?: {
    status?: string;
    verified?: boolean;
    result?: {
      receipt?: LinksEtReceiptDetails;
      [key: string]: unknown;
    };
    [key: string]: unknown;
  };
  error?: string;
  message?: string;
  code?: string;
  [key: string]: unknown;
}

export interface LinksEtVerifyImageResponse extends LinksEtVerifyResponse {
  detection?: {
    ocr_confidence?: number;
    detected_provider?: string;
    raw_text?: string;
  };
}

export interface LinksEtWebhookPayload {
  event: string;
  timestamp: string | number;
  data: LinksEtVerifyResponse;
  signature?: string;
}
