import { HttpStatus, Injectable, Logger } from '@nestjs/common';
import { ConfigService } from '@nestjs/config';
import { createHash, KeyObject, randomBytes } from 'crypto';
import { PaymentProvider as PaymentProviderName } from '../../../common/enums';
import { DomainException } from '../../../common/domain.exception';
import { ErrorCode } from '../../../common/error-codes';
import {
  InitiateTopUpParams,
  PaymentProviderGateway,
  ProviderVerification,
  TopUpInitiation,
  WithdrawalInitiation,
} from '../payment-provider.gateway';
import {
  loadPrivateKey,
  loadPublicKey,
  signPayload,
  TELEBIRR_SIGN_TYPE,
  verifyPayload,
} from './telebirr-signature';

/**
 * Telebirr H5 C2B Web Checkout adapter (developer.ethiotelecom.et):
 *
 *   applyFabricToken  POST /payment/v1/token
 *   preOrder          POST /payment/v1/merchant/preOrder   -> prepay_id
 *   checkout URL      webCheckoutUrl + signed rawRequest
 *   notify            signed POST to notify_url (parseWebhook)
 *   queryOrder        POST /payment/v1/merchant/queryOrder (verifyTransaction)
 *
 * The provider reference is our `merch_order_id`, derived from the user and the
 * idempotency key so a retried initiation maps to the same Telebirr order.
 * Only token and queryOrder (read-only) are retried; preOrder is not.
 */

interface TelebirrSettings {
  baseUrl: string;
  webCheckoutUrl: string;
  fabricAppId: string;
  appSecret: string;
  merchantAppId: string;
  merchantCode: string;
  privateKey: KeyObject;
  telebirrPublicKey: KeyObject;
  notifyUrl: string;
  redirectUrl?: string;
  timeoutMs: number;
  orderTimeoutMinutes: number;
  notifyMaxAgeSeconds: number;
}

interface TelebirrResponse {
  result?: string;
  code?: string;
  msg?: string;
  errorCode?: string;
  errorMsg?: string;
  biz_content?: Record<string, string | undefined>;
}

export const TELEBIRR_REQUIRED_ENV = [
  'TELEBIRR_BASE_URL',
  'TELEBIRR_WEB_CHECKOUT_URL',
  'TELEBIRR_FABRIC_APP_ID',
  'TELEBIRR_APP_SECRET',
  'TELEBIRR_MERCHANT_APP_ID',
  'TELEBIRR_MERCHANT_CODE',
  'TELEBIRR_PRIVATE_KEY',
  'TELEBIRR_PUBLIC_KEY',
  'TELEBIRR_NOTIFY_URL',
] as const;

const SUCCESS_STATUSES = new Set(['PAY_SUCCESS', 'COMPLETED']);
const FAILED_STATUSES = new Set([
  'PAY_FAILED',
  'ORDER_CLOSED',
  'FAILURE',
  'EXPIRED',
  'REFUND_SUCCESS',
  'REFUNDING',
  'ACCEPTED',
]);

/** "12.5" / "12.50" / "12" -> santim, without floating point. */
export function majorToMinor(value: string): number | undefined {
  const match = /^(\d+)(?:\.(\d{1,2}))?$/.exec(value.trim());
  if (!match) return undefined;
  return Number(match[1]) * 100 + Number((match[2] ?? '').padEnd(2, '0'));
}

export function minorToMajor(amountMinor: number): string {
  return `${Math.floor(amountMinor / 100)}.${String(amountMinor % 100).padStart(2, '0')}`;
}

@Injectable()
export class TelebirrPaymentProvider implements PaymentProviderGateway {
  readonly name = PaymentProviderName.TELEBIRR;
  private readonly logger = new Logger(TelebirrPaymentProvider.name);
  private cachedSettings?: TelebirrSettings;
  private token?: { value: string; expiresAt: number };

  constructor(private readonly configService: ConfigService) {}

  isConfigured(): boolean {
    return TELEBIRR_REQUIRED_ENV.every((key) => !!this.configService.get(key));
  }

  async initiateTopUp(params: InitiateTopUpParams): Promise<TopUpInitiation> {
    const settings = this.settings();
    if (params.currency !== 'ETB') {
      throw new DomainException(
        'Telebirr only supports ETB',
        HttpStatus.BAD_REQUEST,
        ErrorCode.VALIDATION_ERROR,
      );
    }

    const merchOrderId = this.merchOrderId(params.userId, params.idempotencyKey);
    const biz: Record<string, string> = {
      notify_url: settings.notifyUrl,
      appid: settings.merchantAppId,
      merch_code: settings.merchantCode,
      merch_order_id: merchOrderId,
      trade_type: 'Checkout',
      title: 'SemuniWalletTopUp',
      total_amount: minorToMajor(params.amountMinor),
      trans_currency: 'ETB',
      timeout_express: `${settings.orderTimeoutMinutes}m`,
      business_type: 'BuyGoods',
    };
    if (settings.redirectUrl) biz.redirect_url = settings.redirectUrl;

    const response = await this.signedCall(
      '/payment/v1/merchant/preOrder',
      'payment.preorder',
      biz,
      { retry: false },
    );
    const prepayId = response.biz_content?.prepay_id;
    if (!prepayId) {
      throw this.unavailable('preOrder returned no prepay_id');
    }

    return {
      providerReference: merchOrderId,
      checkoutUrl: this.checkoutUrl(prepayId),
    };
  }

  async verifyTransaction(
    providerReference: string,
  ): Promise<ProviderVerification> {
    const settings = this.settings();
    const response = await this.signedCall(
      '/payment/v1/merchant/queryOrder',
      'payment.queryorder',
      {
        appid: settings.merchantAppId,
        merch_code: settings.merchantCode,
        merch_order_id: providerReference,
      },
      { retry: true },
    );

    const biz = response.biz_content ?? {};
    if (biz.merch_order_id && biz.merch_order_id !== providerReference) {
      throw this.unavailable('queryOrder returned a different order');
    }
    const status = (biz.order_status ?? biz.trade_status ?? '').toUpperCase();

    if (SUCCESS_STATUSES.has(status)) {
      if ((biz.trans_currency ?? 'ETB') !== 'ETB') {
        return {
          verified: false,
          providerReference,
          failureReason: 'Unexpected currency from Telebirr',
        };
      }
      return {
        verified: true,
        providerReference,
        amountMinor: biz.total_amount ? majorToMinor(biz.total_amount) : undefined,
      };
    }
    if (FAILED_STATUSES.has(status)) {
      return {
        verified: false,
        providerReference,
        failureReason: `Telebirr order status ${status}`,
      };
    }
    // WAIT_PAY, PAYING, unknown: money may still move, so neither credit nor fail.
    return { verified: false, pending: true, providerReference };
  }

  initiateWithdrawal(): Promise<WithdrawalInitiation> {
    // Telebirr's public portal documents C2B checkout and mandate deductions
    // (customer -> merchant) only; there is no documented merchant -> customer
    // payout API. Refuse rather than guess, so no wallet is debited.
    throw new DomainException(
      'Telebirr withdrawals are not available yet',
      HttpStatus.NOT_IMPLEMENTED,
      ErrorCode.PAYMENT_PROVIDER_UNAVAILABLE,
    );
  }

  /**
   * Validates a Telebirr payment notification and returns our order id.
   * The notification only triggers settlement; the credit itself still waits
   * for queryOrder to confirm the payment and amount.
   */
  parseWebhook(body: unknown): string {
    const settings = this.settings();
    const payload = (body ?? {}) as Record<string, unknown>;
    const reject = (reason: string): never => {
      this.logger.warn(`Rejected Telebirr notification: ${reason}`);
      throw new DomainException(
        'Invalid payment notification',
        HttpStatus.UNAUTHORIZED,
        ErrorCode.WEBHOOK_SIGNATURE_INVALID,
      );
    };

    const signature = payload.sign;
    if (typeof signature !== 'string' || !signature) return reject('missing sign');
    if (payload.sign_type !== TELEBIRR_SIGN_TYPE) return reject('unexpected sign_type');
    if (!verifyPayload(payload, signature, settings.telebirrPublicKey)) {
      return reject('signature mismatch');
    }

    const notifyTime = Number(payload.notify_time);
    if (!Number.isFinite(notifyTime) || notifyTime <= 0) return reject('missing notify_time');
    // Documented as seconds, sent as milliseconds in the portal's sample.
    const notifiedAtMs = notifyTime > 1e12 ? notifyTime : notifyTime * 1000;
    if (Math.abs(Date.now() - notifiedAtMs) > settings.notifyMaxAgeSeconds * 1000) {
      return reject('stale notify_time');
    }

    if (payload.appid !== undefined && payload.appid !== settings.merchantAppId) {
      return reject('appid mismatch');
    }
    if (payload.merch_code !== undefined && payload.merch_code !== settings.merchantCode) {
      return reject('merch_code mismatch');
    }
    const merchOrderId = payload.merch_order_id;
    if (typeof merchOrderId !== 'string' || !merchOrderId) {
      return reject('missing merch_order_id');
    }
    return merchOrderId;
  }

  private merchOrderId(userId: string, idempotencyKey: string): string {
    const digest = createHash('sha256')
      .update(`${userId}:${idempotencyKey}`)
      .digest('hex')
      .slice(0, 40);
    return `SMN${digest}`;
  }

  private checkoutUrl(prepayId: string): string {
    const settings = this.settings();
    const map = {
      appid: settings.merchantAppId,
      merch_code: settings.merchantCode,
      nonce_str: this.nonce(),
      prepay_id: prepayId,
      timestamp: this.timestamp(),
    };
    const sign = signPayload(map, settings.privateKey);
    const rawRequest = [
      `appid=${map.appid}`,
      `merch_code=${map.merch_code}`,
      `nonce_str=${map.nonce_str}`,
      `prepay_id=${map.prepay_id}`,
      `timestamp=${map.timestamp}`,
      `sign=${encodeURIComponent(sign)}`,
      `sign_type=${TELEBIRR_SIGN_TYPE}`,
    ].join('&');
    return `${settings.webCheckoutUrl}${rawRequest}&version=1.0&trade_type=Checkout`;
  }

  private async signedCall(
    path: string,
    method: string,
    biz: Record<string, string>,
    options: { retry: boolean },
  ): Promise<TelebirrResponse> {
    const settings = this.settings();
    const body: Record<string, unknown> = {
      timestamp: this.timestamp(),
      nonce_str: this.nonce(),
      method,
      version: '1.0',
      biz_content: biz,
    };
    body.sign = signPayload(body, settings.privateKey);
    body.sign_type = TELEBIRR_SIGN_TYPE;

    const token = await this.fabricToken();
    const response = await this.post(
      path,
      body,
      { 'X-APP-Key': settings.fabricAppId, Authorization: token },
      options.retry,
    );
    if (response.result !== 'SUCCESS' || response.code !== '0') {
      throw this.unavailable(
        `${method} failed (code=${response.code ?? response.errorCode ?? 'n/a'})`,
      );
    }
    return response;
  }

  private async fabricToken(): Promise<string> {
    if (this.token && this.token.expiresAt > Date.now()) return this.token.value;
    const settings = this.settings();
    const response = (await this.post(
      '/payment/v1/token',
      { appSecret: settings.appSecret },
      { 'X-APP-Key': settings.fabricAppId },
      true,
    )) as TelebirrResponse & {
      token?: string;
      effectiveDate?: string;
      expirationDate?: string;
    };
    if (!response.token) throw this.unavailable('applyFabricToken returned no token');

    const lifetimeMs =
      parseCompactDate(response.expirationDate) - parseCompactDate(response.effectiveDate);
    const ttl = Number.isFinite(lifetimeMs) && lifetimeMs > 120_000 ? lifetimeMs : 50 * 60_000;
    this.token = { value: response.token, expiresAt: Date.now() + ttl - 60_000 };
    return response.token;
  }

  private async post(
    path: string,
    body: unknown,
    headers: Record<string, string>,
    retry: boolean,
  ): Promise<TelebirrResponse> {
    const settings = this.settings();
    const attempts = retry ? 3 : 1;
    let lastError = 'unknown error';
    for (let attempt = 1; attempt <= attempts; attempt += 1) {
      try {
        const res = await fetch(`${settings.baseUrl}${path}`, {
          method: 'POST',
          headers: { 'Content-Type': 'application/json', ...headers },
          body: JSON.stringify(body),
          signal: AbortSignal.timeout(settings.timeoutMs),
        });
        const json = (await res.json().catch(() => ({}))) as TelebirrResponse;
        if (res.ok) return json;
        lastError = `HTTP ${res.status}${json.errorCode ? ` ${json.errorCode}` : ''}`;
        if (res.status < 500) break;
      } catch (err) {
        lastError = (err as Error).name;
      }
      if (attempt < attempts) await sleep(250 * attempt);
    }
    throw this.unavailable(`${path}: ${lastError}`);
  }

  private unavailable(detail: string): DomainException {
    this.logger.error(`Telebirr call failed: ${detail}`);
    return new DomainException(
      'Telebirr is unavailable, please try again',
      HttpStatus.BAD_GATEWAY,
      ErrorCode.PAYMENT_PROVIDER_UNAVAILABLE,
    );
  }

  private settings(): TelebirrSettings {
    if (this.cachedSettings) return this.cachedSettings;
    if (!this.isConfigured()) {
      throw new DomainException(
        'Payment provider TELEBIRR is not configured',
        HttpStatus.NOT_IMPLEMENTED,
        ErrorCode.PAYMENT_PROVIDER_UNAVAILABLE,
      );
    }
    const get = (key: string) => this.configService.get<string>(key) as string;
    const num = (key: string, fallback: number) => {
      const value = Number(this.configService.get(key));
      return Number.isFinite(value) && value > 0 ? value : fallback;
    };
    this.cachedSettings = {
      baseUrl: get('TELEBIRR_BASE_URL').replace(/\/+$/, ''),
      webCheckoutUrl: get('TELEBIRR_WEB_CHECKOUT_URL'),
      fabricAppId: get('TELEBIRR_FABRIC_APP_ID'),
      appSecret: get('TELEBIRR_APP_SECRET'),
      merchantAppId: get('TELEBIRR_MERCHANT_APP_ID'),
      merchantCode: get('TELEBIRR_MERCHANT_CODE'),
      privateKey: loadPrivateKey(get('TELEBIRR_PRIVATE_KEY')),
      telebirrPublicKey: loadPublicKey(get('TELEBIRR_PUBLIC_KEY')),
      notifyUrl: get('TELEBIRR_NOTIFY_URL'),
      redirectUrl: this.configService.get<string>('TELEBIRR_REDIRECT_URL') || undefined,
      timeoutMs: num('TELEBIRR_HTTP_TIMEOUT_MS', 10_000),
      orderTimeoutMinutes: Math.min(num('TELEBIRR_ORDER_TIMEOUT_MINUTES', 120), 120),
      notifyMaxAgeSeconds: num('TELEBIRR_NOTIFY_MAX_AGE_SECONDS', 3600),
    };
    return this.cachedSettings;
  }

  private timestamp(): string {
    return String(Math.floor(Date.now() / 1000));
  }

  private nonce(): string {
    return randomBytes(16).toString('hex').toUpperCase();
  }
}

/** yyyyMMddHHmmss -> epoch ms (only differences are used, so the zone cancels). */
function parseCompactDate(value?: string): number {
  const m = /^(\d{4})(\d{2})(\d{2})(\d{2})(\d{2})(\d{2})$/.exec(value ?? '');
  if (!m) return NaN;
  return Date.UTC(+m[1], +m[2] - 1, +m[3], +m[4], +m[5], +m[6]);
}

function sleep(ms: number): Promise<void> {
  return new Promise((resolve) => setTimeout(resolve, ms));
}
