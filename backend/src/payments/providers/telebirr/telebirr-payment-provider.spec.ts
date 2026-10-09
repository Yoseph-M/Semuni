import { generateKeyPairSync, KeyObject } from 'crypto';
import { ConfigService } from '@nestjs/config';
import {
  majorToMinor,
  minorToMajor,
  TelebirrPaymentProvider,
} from './telebirr-payment-provider';
import {
  canonicalSignString,
  loadPrivateKey,
  loadPublicKey,
  signPayload,
  verifyPayload,
} from './telebirr-signature';
import { ErrorCode } from '../../../common/error-codes';

/**
 * Contract tests against the request/response shapes published on
 * developer.ethiotelecom.et (H5 C2B Web Payment). No network: fetch is stubbed.
 */
const pem = (key: KeyObject, type: 'pkcs8' | 'spki') =>
  key.export({ format: 'pem', type }).toString();

const merchant = generateKeyPairSync('rsa', { modulusLength: 2048 });
const telebirr = generateKeyPairSync('rsa', { modulusLength: 2048 });

const env: Record<string, string> = {
  TELEBIRR_BASE_URL: 'https://telebirr.test/apiaccess/payment/gateway',
  TELEBIRR_WEB_CHECKOUT_URL: 'https://telebirr.test/payment/web/paygate?',
  TELEBIRR_FABRIC_APP_ID: 'fabric-app',
  TELEBIRR_APP_SECRET: 'app-secret',
  TELEBIRR_MERCHANT_APP_ID: '1227484825753601',
  TELEBIRR_MERCHANT_CODE: '101011',
  TELEBIRR_PRIVATE_KEY: pem(merchant.privateKey, 'pkcs8'),
  TELEBIRR_PUBLIC_KEY: pem(telebirr.publicKey, 'spki'),
  TELEBIRR_NOTIFY_URL: 'https://api.semuni.test/api/v1/wallet/webhooks/telebirr',
};

const TOKEN_RESPONSE = {
  effectiveDate: '20221101132422',
  expirationDate: '20221101142422',
  token: 'Bearer 94cc42be4412696d754508c06ca1db20',
};

const PREORDER_RESPONSE = {
  result: 'SUCCESS',
  code: '0',
  msg: 'success',
  nonce_str: '97fe4ae0c0604854a749fbf2cc1cc712',
  sign: 'Eo4Bvwx9...',
  sign_type: 'SHA256WithRSA',
  biz_content: {
    merch_order_id: 'set-per-test',
    prepay_id: '080075a4e3213924de2b3b84ad3cac0a6a6001',
  },
};

const queryResponse = (merchOrderId: string, status: string, amount = '12.50') => ({
  result: 'SUCCESS',
  code: '0',
  msg: 'success',
  sign_type: 'SHA256WithRSA',
  biz_content: {
    merch_order_id: merchOrderId,
    order_status: status,
    payment_order_id: '11801107AD19191408215009',
    trans_time: '2025-10-13 19:19:38',
    trans_currency: 'ETB',
    total_amount: amount,
    trans_id: 'CJD7GBOXIP',
  },
});

function jsonResponse(body: unknown, status = 200): Response {
  return new Response(JSON.stringify(body), {
    status,
    headers: { 'Content-Type': 'application/json' },
  });
}

describe('TelebirrPaymentProvider', () => {
  let provider: TelebirrPaymentProvider;
  let fetchMock: jest.Mock;
  const calls: Array<{ url: string; headers: Record<string, string>; body: any }> = [];

  beforeEach(() => {
    calls.length = 0;
    const config = { get: (key: string) => env[key] } as unknown as ConfigService;
    provider = new TelebirrPaymentProvider(config);
    fetchMock = jest.fn();
    global.fetch = fetchMock as unknown as typeof fetch;
  });

  const route = (handlers: Record<string, () => Response>) =>
    fetchMock.mockImplementation(async (url: string, init: RequestInit) => {
      calls.push({
        url,
        headers: init.headers as Record<string, string>,
        body: JSON.parse(init.body as string),
      });
      const path = Object.keys(handlers).find((p) => url.endsWith(p));
      if (!path) throw new Error(`unexpected ${url}`);
      return handlers[path]();
    });

  describe('amount conversion', () => {
    it('converts santim to a two-decimal string and back without floats', () => {
      expect(minorToMajor(1250)).toBe('12.50');
      expect(minorToMajor(5)).toBe('0.05');
      expect(majorToMinor('12.50')).toBe(1250);
      expect(majorToMinor('12.5')).toBe(1250);
      expect(majorToMinor('1260')).toBe(126000);
      expect(majorToMinor('1.234')).toBeUndefined();
    });
  });

  describe('signature', () => {
    it('builds the documented canonical string (sorted, biz_content flattened)', () => {
      const str = canonicalSignString({
        timestamp: '1755866911',
        nonce_str: 'H5QN4M6EAB2TXXVFK8SVV0RW6UFASICS',
        method: 'payment.preorder',
        version: '1.0',
        biz_content: {
          notify_url: 'https://www.google.com',
          appid: '1227484825753601',
          merch_code: '101011',
          merch_order_id: '1755866910890',
          trade_type: 'Checkout',
          title: 'diamond_1.5',
          total_amount: '1.5',
          trans_currency: 'ETB',
          timeout_express: '120m',
        },
        sign: 'ignored',
        sign_type: 'ignored',
      });
      // Exact example from the Telebirr "Request Signature Process" page.
      expect(str).toBe(
        'appid=1227484825753601&merch_code=101011&merch_order_id=1755866910890&method=payment.preorder&nonce_str=H5QN4M6EAB2TXXVFK8SVV0RW6UFASICS&notify_url=https://www.google.com&timeout_express=120m&timestamp=1755866911&title=diamond_1.5&total_amount=1.5&trade_type=Checkout&trans_currency=ETB&version=1.0',
      );
    });

    it('signs with RSA-PSS SHA-256 and rejects tampering', () => {
      const payload = { a: '1', b: '2' };
      const sig = signPayload(payload, merchant.privateKey);
      expect(verifyPayload(payload, sig, merchant.publicKey)).toBe(true);
      expect(verifyPayload({ a: '1', b: '3' }, sig, merchant.publicKey)).toBe(false);
      expect(verifyPayload(payload, sig, telebirr.publicKey)).toBe(false);
    });
  });

  describe('initiateTopUp', () => {
    it('applies a fabric token, signs preOrder, and returns a signed checkout URL', async () => {
      route({
        '/payment/v1/token': () => jsonResponse(TOKEN_RESPONSE),
        '/payment/v1/merchant/preOrder': () => jsonResponse(PREORDER_RESPONSE),
      });

      const result = await provider.initiateTopUp({
        userId: 'user-1',
        amountMinor: 1250,
        currency: 'ETB',
        idempotencyKey: 'key-1',
      });

      expect(result.providerReference).toMatch(/^SMN[0-9a-f]{40}$/);
      expect(result.checkoutUrl).toMatch(
        /^https:\/\/telebirr\.test\/payment\/web\/paygate\?appid=1227484825753601&merch_code=101011&nonce_str=\w+&prepay_id=080075a4e3213924de2b3b84ad3cac0a6a6001&timestamp=\d+&sign=.+&sign_type=SHA256WithRSA&version=1\.0&trade_type=Checkout$/,
      );

      const [token, preOrder] = calls;
      expect(token.headers['X-APP-Key']).toBe('fabric-app');
      expect(token.body).toEqual({ appSecret: 'app-secret' });
      expect(preOrder.headers.Authorization).toBe(TOKEN_RESPONSE.token);
      expect(preOrder.body.method).toBe('payment.preorder');
      expect(preOrder.body.biz_content).toMatchObject({
        merch_order_id: result.providerReference,
        total_amount: '12.50',
        trans_currency: 'ETB',
        trade_type: 'Checkout',
        notify_url: env.TELEBIRR_NOTIFY_URL,
      });
      expect(
        verifyPayload(preOrder.body, preOrder.body.sign, merchant.publicKey),
      ).toBe(true);
    });

    it('derives the same order id from the same user + idempotency key', async () => {
      route({
        '/payment/v1/token': () => jsonResponse(TOKEN_RESPONSE),
        '/payment/v1/merchant/preOrder': () => jsonResponse(PREORDER_RESPONSE),
      });
      const params = { userId: 'u', amountMinor: 100, currency: 'ETB', idempotencyKey: 'k' };
      const a = await provider.initiateTopUp(params);
      const b = await provider.initiateTopUp(params);
      const c = await provider.initiateTopUp({ ...params, userId: 'other' });
      expect(a.providerReference).toBe(b.providerReference);
      expect(c.providerReference).not.toBe(a.providerReference);
      // The fabric token is cached between calls.
      expect(calls.filter((x) => x.url.endsWith('/token'))).toHaveLength(1);
    });

    it('does not retry preOrder and maps failures to PAYMENT_PROVIDER_UNAVAILABLE', async () => {
      route({
        '/payment/v1/token': () => jsonResponse(TOKEN_RESPONSE),
        '/payment/v1/merchant/preOrder': () => jsonResponse({ errorCode: 'x', errorMsg: 'secret detail' }, 503),
      });
      await expect(
        provider.initiateTopUp({ userId: 'u', amountMinor: 100, currency: 'ETB', idempotencyKey: 'k' }),
      ).rejects.toMatchObject({ code: ErrorCode.PAYMENT_PROVIDER_UNAVAILABLE });
      expect(calls.filter((x) => x.url.endsWith('/preOrder'))).toHaveLength(1);
    });

    it('rejects a business failure (result=FAIL)', async () => {
      route({
        '/payment/v1/token': () => jsonResponse(TOKEN_RESPONSE),
        '/payment/v1/merchant/preOrder': () => jsonResponse({ result: 'FAIL', code: '1001', msg: 'verify sign failed' }),
      });
      await expect(
        provider.initiateTopUp({ userId: 'u', amountMinor: 100, currency: 'ETB', idempotencyKey: 'k' }),
      ).rejects.toMatchObject({ code: ErrorCode.PAYMENT_PROVIDER_UNAVAILABLE });
    });
  });

  describe('verifyTransaction', () => {
    it.each([
      ['PAY_SUCCESS', { verified: true, amountMinor: 1250 }],
      ['WAIT_PAY', { verified: false, pending: true }],
      ['PAYING', { verified: false, pending: true }],
      ['PAY_FAILED', { verified: false, failureReason: 'Telebirr order status PAY_FAILED' }],
      ['ORDER_CLOSED', { verified: false, failureReason: 'Telebirr order status ORDER_CLOSED' }],
    ])('maps %s', async (status, expected) => {
      route({
        '/payment/v1/token': () => jsonResponse(TOKEN_RESPONSE),
        '/payment/v1/merchant/queryOrder': () => jsonResponse(queryResponse('SMN1', status)),
      });
      await expect(provider.verifyTransaction('SMN1')).resolves.toMatchObject(expected);
    });

    it('retries queryOrder on 5xx (read-only, safe to repeat)', async () => {
      let n = 0;
      route({
        '/payment/v1/token': () => jsonResponse(TOKEN_RESPONSE),
        '/payment/v1/merchant/queryOrder': () =>
          ++n < 2 ? jsonResponse({}, 502) : jsonResponse(queryResponse('SMN1', 'PAY_SUCCESS')),
      });
      await expect(provider.verifyTransaction('SMN1')).resolves.toMatchObject({ verified: true });
      expect(n).toBe(2);
    });

    it('refuses a response about a different order', async () => {
      route({
        '/payment/v1/token': () => jsonResponse(TOKEN_RESPONSE),
        '/payment/v1/merchant/queryOrder': () => jsonResponse(queryResponse('OTHER', 'PAY_SUCCESS')),
      });
      await expect(provider.verifyTransaction('SMN1')).rejects.toMatchObject({
        code: ErrorCode.PAYMENT_PROVIDER_UNAVAILABLE,
      });
    });
  });

  describe('parseWebhook', () => {
    const notification = (overrides: Record<string, string> = {}) => {
      const body: Record<string, string> = {
        notify_url: env.TELEBIRR_NOTIFY_URL,
        appid: env.TELEBIRR_MERCHANT_APP_ID,
        notify_time: String(Date.now()),
        merch_code: env.TELEBIRR_MERCHANT_CODE,
        merch_order_id: 'SMNabc',
        payment_order_id: '00801104C911443200001002',
        total_amount: '10.00',
        trans_id: '49485948475845',
        trans_currency: 'ETB',
        trade_status: 'Completed',
        trans_end_time: String(Date.now()),
        ...overrides,
      };
      body.sign = signPayload(body, telebirr.privateKey);
      body.sign_type = 'SHA256WithRSA';
      return body;
    };

    it('accepts a correctly signed, fresh notification', () => {
      expect(provider.parseWebhook(notification())).toBe('SMNabc');
    });

    it('accepts notify_time in seconds as documented', () => {
      const body = notification({ notify_time: String(Math.floor(Date.now() / 1000)) });
      expect(provider.parseWebhook(body)).toBe('SMNabc');
    });

    it.each([
      ['a tampered amount', (b: Record<string, string>) => ({ ...b, total_amount: '9999.00' })],
      ['a tampered appid', (b: Record<string, string>) => ({ ...b, appid: 'wrong-appid' })],
      ['a tampered merch_order_id', (b: Record<string, string>) => ({ ...b, merch_order_id: 'SMNtampered' })],
      ['a tampered trade_status', (b: Record<string, string>) => ({ ...b, trade_status: 'Failed' })],
      ['a tampered trans_currency', (b: Record<string, string>) => ({ ...b, trans_currency: 'USD' })],
      ['a missing signature', (b: Record<string, string>) => ({ ...b, sign: '' })],
      ['a wrong sign_type', (b: Record<string, string>) => ({ ...b, sign_type: 'MD5' })],
      ['a signature by another key', (b: Record<string, string>) => ({
        ...b,
        sign: signPayload(b, merchant.privateKey),
      })],
    ])('rejects %s', (_label, mutate) => {
      expect(() => provider.parseWebhook(mutate(notification()))).toThrow(
        expect.objectContaining({ code: ErrorCode.WEBHOOK_SIGNATURE_INVALID }),
      );
    });

    it('rejects a replayed (stale) notification', () => {
      const body = notification({ notify_time: String(Date.now() - 2 * 3600 * 1000) });
      expect(() => provider.parseWebhook(body)).toThrow(
        expect.objectContaining({ code: ErrorCode.WEBHOOK_SIGNATURE_INVALID }),
      );
    });

    it('rejects a notification with invalid non-numeric notify_time', () => {
      const body = notification({ notify_time: 'not-a-number' });
      expect(() => provider.parseWebhook(body)).toThrow(
        expect.objectContaining({ code: ErrorCode.WEBHOOK_SIGNATURE_INVALID }),
      );
    });

    it('rejects a notification for another merchant', () => {
      const body = notification({ merch_code: '999999' });
      expect(() => provider.parseWebhook(body)).toThrow(
        expect.objectContaining({ code: ErrorCode.WEBHOOK_SIGNATURE_INVALID }),
      );
    });
  });

  describe('key loading and security', () => {
    it('throws descriptive error on malformed private key', () => {
      expect(() => loadPrivateKey('invalid-key-data')).toThrow(
        /Failed to load Telebirr private key/,
      );
    });

    it('throws descriptive error on malformed public key', () => {
      expect(() => loadPublicKey('invalid-key-data')).toThrow(
        /Failed to load Telebirr public key/,
      );
    });
  });

  describe('currency and token expiration edge cases', () => {
    it('rejects non-ETB currency in initiateTopUp', async () => {
      await expect(
        provider.initiateTopUp({
          userId: 'u1',
          amountMinor: 1000,
          currency: 'USD' as any,
          idempotencyKey: 'k1',
        }),
      ).rejects.toMatchObject({ code: ErrorCode.VALIDATION_ERROR });
    });

    it('returns verified: false when queryOrder returns non-ETB currency', async () => {
      route({
        '/payment/v1/token': () => jsonResponse(TOKEN_RESPONSE),
        '/payment/v1/merchant/queryOrder': () => {
          const resp = queryResponse('SMN1', 'PAY_SUCCESS');
          resp.biz_content.trans_currency = 'USD';
          return jsonResponse(resp);
        },
      });
      const result = await provider.verifyTransaction('SMN1');
      expect(result.verified).toBe(false);
      expect(result.failureReason).toContain('Unexpected currency');
    });

    it('refreshes expired fabric token on subsequent calls', async () => {
      let tokenCallCount = 0;
      route({
        '/payment/v1/token': () => {
          tokenCallCount++;
          return jsonResponse({
            effectiveDate: '20221101132422',
            // Token that expires immediately (ttl < 2 minutes falls back to 50min, but let's test re-fetch if token state is invalidated)
            expirationDate: '20221101132430',
            token: `Bearer token-${tokenCallCount}`,
          });
        },
        '/payment/v1/merchant/queryOrder': () => jsonResponse(queryResponse('SMN1', 'PAY_SUCCESS')),
      });

      await provider.verifyTransaction('SMN1');
      expect(tokenCallCount).toBe(1);

      // Force token expiration on internal state to test refresh
      (provider as any).token.expiresAt = Date.now() - 1000;

      await provider.verifyTransaction('SMN1');
      expect(tokenCallCount).toBe(2);
    });
  });

  it('refuses withdrawals (no documented Telebirr payout API)', () => {
    expect(() => provider.initiateWithdrawal()).toThrow(
      expect.objectContaining({ code: ErrorCode.PAYMENT_PROVIDER_UNAVAILABLE }),
    );
  });

  it('reports unconfigured instead of falling back', async () => {
    const empty = new TelebirrPaymentProvider({ get: () => undefined } as unknown as ConfigService);
    expect(empty.isConfigured()).toBe(false);
    await expect(empty.verifyTransaction('x')).rejects.toMatchObject({
      code: ErrorCode.PAYMENT_PROVIDER_UNAVAILABLE,
    });
  });
});
