import { ConfigService } from '@nestjs/config';
import { Currency } from '../common/enums';
import { LinksEtClient } from './links-et.client';
import {
  LinksEtAuthException,
  LinksEtBadRequestException,
  LinksEtInvalidReceiptException,
  LinksEtNotFoundException,
  LinksEtRateLimitException,
  LinksEtTimeoutException,
  LinksEtUnavailableException,
  LinksEtVerificationMismatchException,
} from './links-et.errors';
import { LinksEtReceiptVerifier } from './links-et.receipt-verifier';

describe('links.et Integration', () => {
  let client: LinksEtClient;
  let verifier: LinksEtReceiptVerifier;
  let fetchMock: jest.Mock;

  const env: Record<string, string> = {
    LINKS_ET_BASE_URL: 'https://links.et',
    LINKS_ET_API_KEY: 'test-links-et-api-key',
    LINKS_ET_TIMEOUT_MS: '2000',
    LINKS_ET_ENABLED: 'true',
  };

  beforeEach(() => {
    fetchMock = jest.fn();
    global.fetch = fetchMock as unknown as typeof fetch;
    const config = { get: (key: string) => env[key] } as unknown as ConfigService;
    client = new LinksEtClient(config);
    verifier = new LinksEtReceiptVerifier(client);
  });

  const jsonResponse = (body: unknown, status = 200, headers: Record<string, string> = {}) =>
    new Response(JSON.stringify(body), {
      status,
      headers: { 'Content-Type': 'application/json', ...headers },
    });

  describe('LinksEtClient', () => {
    it('verifies by reference sending auth headers and sanitized payload', async () => {
      fetchMock.mockResolvedValueOnce(
        jsonResponse({
          success: true,
          status: 'SUCCESS',
          receipt: {
            provider: 'telebirr',
            provider_reference: 'SMN123456789',
            amount: '150.00',
            currency: 'ETB',
            status: 'COMPLETED',
            receipt_id: 'LET_REC_001',
          },
        }),
      );

      const res = await client.verify({ reference: 'SMN123456789' });
      expect(res.success).toBe(true);
      expect(res.status).toBe('SUCCESS');
      expect(fetchMock).toHaveBeenCalledTimes(1);

      const [url, init] = fetchMock.mock.calls[0];
      expect(url).toBe('https://links.et/api/verify');
      expect(init.headers['x-api-key']).toBe('test-links-et-api-key');
      expect(init.headers.Authorization).toBe('Bearer test-links-et-api-key');
      expect(JSON.parse(init.body)).toEqual({
        reference: 'SMN123456789',
      });
    });

    it('verifies by receipt URL', async () => {
      fetchMock.mockResolvedValueOnce(
        jsonResponse({
          success: true,
          status: 'SUCCESS',
          receipt: {
            provider: 'cbe',
            provider_reference: 'FT240123ABC',
            amount: 250,
            currency: 'ETB',
            receipt_id: 'LET_CBE_999',
          },
        }),
      );

      const res = await client.verify({ url: 'https://links.et/r/FT240123ABC' });
      expect(res.status).toBe('SUCCESS');
      const [, init] = fetchMock.mock.calls[0];
      expect(JSON.parse(init.body)).toEqual({
        url: 'https://links.et/r/FT240123ABC',
      });
    });

    it('verifies image payload with mime type', async () => {
      fetchMock.mockResolvedValueOnce(
        jsonResponse({
          success: true,
          status: 'SUCCESS',
          upstream: {
            verified: true,
            status: 'VERIFIED',
            result: {
              receipt: {
                provider: 'telebirr',
                provider_reference: 'SMNIMG888',
                amount: '50.00',
                currency: 'ETB',
                receipt_id: 'LET_IMG_01',
              },
            },
          },
        }),
      );

      const res = await client.verifyImage({
        imageBase64: 'data:image/png;base64,iVBORw0KGgoAAAANSUhEUgAAAAEAAAABCAYAAAAfFcSJ',
        mimeType: 'image/png',
      });
      expect(res.success).toBe(true);
      expect(res.upstream?.verified).toBe(true);
    });

    it('polls when status is QUEUED or PROCESSING until SUCCESS', async () => {
      fetchMock
        .mockResolvedValueOnce(
          jsonResponse({
            success: true,
            status: 'QUEUED',
            poll_url: '/api/jobs/job_123',
          }),
        )
        .mockResolvedValueOnce(
          jsonResponse({
            success: true,
            status: 'PROCESSING',
          }),
        )
        .mockResolvedValueOnce(
          jsonResponse({
            success: true,
            status: 'SUCCESS',
            receipt: {
              provider: 'telebirr',
              provider_reference: 'SMN_POLL_01',
              amount: '75.00',
              currency: 'ETB',
            },
          }),
        );

      const res = await client.verify({ reference: 'SMN_POLL_01' });
      expect(res.status).toBe('SUCCESS');
      expect(fetchMock).toHaveBeenCalledTimes(3);
    });

    it('throws LinksEtBadRequestException on 400 without retrying', async () => {
      fetchMock.mockResolvedValueOnce(
        jsonResponse({ error: 'Malformed request reference' }, 400),
      );

      await expect(client.verify({ reference: 'bad' })).rejects.toThrow(
        LinksEtBadRequestException,
      );
      expect(fetchMock).toHaveBeenCalledTimes(1);
    });

    it('throws LinksEtAuthException on 401 without retrying', async () => {
      fetchMock.mockResolvedValueOnce(
        jsonResponse({ error: 'Invalid API key' }, 401),
      );

      await expect(client.verify({ reference: 'ref' })).rejects.toThrow(
        LinksEtAuthException,
      );
      expect(fetchMock).toHaveBeenCalledTimes(1);
    });

    it('throws LinksEtNotFoundException on 404 without retrying', async () => {
      fetchMock.mockResolvedValueOnce(
        jsonResponse({ error: 'Receipt not found' }, 404),
      );

      await expect(client.verify({ reference: 'missing' })).rejects.toThrow(
        LinksEtNotFoundException,
      );
      expect(fetchMock).toHaveBeenCalledTimes(1);
    });

    it('throws LinksEtRateLimitException on 429 and parses Retry-After header', async () => {
      fetchMock.mockResolvedValueOnce(
        jsonResponse({ error: 'Too many requests' }, 429, { 'Retry-After': '30' }),
      );

      try {
        await client.verify({ reference: 'ref' });
        fail('should have thrown LinksEtRateLimitException');
      } catch (err) {
        expect(err).toBeInstanceOf(LinksEtRateLimitException);
        expect((err as LinksEtRateLimitException).retryAfterSeconds).toBe(30);
      }
      expect(fetchMock).toHaveBeenCalledTimes(1);
    });

    it('retries on 5xx up to 3 times before throwing LinksEtUnavailableException', async () => {
      fetchMock
        .mockResolvedValueOnce(jsonResponse({ error: 'Gateway issue' }, 502))
        .mockResolvedValueOnce(jsonResponse({ error: 'Service unavailable' }, 503))
        .mockResolvedValueOnce(jsonResponse({ error: 'Internal error' }, 500));

      await expect(client.verify({ reference: 'ref' })).rejects.toThrow(
        LinksEtUnavailableException,
      );
      expect(fetchMock).toHaveBeenCalledTimes(3);
    });

    it('handles network timeout and maps to LinksEtTimeoutException', async () => {
      const timeoutErr = new Error('The operation was aborted');
      timeoutErr.name = 'TimeoutError';
      fetchMock.mockRejectedValue(timeoutErr);

      await expect(client.verify({ reference: 'ref' })).rejects.toThrow(
        LinksEtTimeoutException,
      );
    });
  });

  describe('LinksEtReceiptVerifier (Normalization & Policy)', () => {
    it('normalizes verified telebirr receipt into canonical VerifiedExternalPayment', async () => {
      fetchMock.mockResolvedValueOnce(
        jsonResponse({
          success: true,
          status: 'SUCCESS',
          receipt: {
            provider: 'telebirr',
            merch_order_id: 'SMN999000',
            amount: '120.50',
            currency: 'ETB',
            status: 'SUCCESS',
            payer: '251911***123',
            destination: 'SEMUNI_TRANSPORT',
            timestamp: 1755866911000,
            receipt_id: 'REC_LET_777',
            short_url: 'https://links.et/r/777',
          },
        }),
      );

      const verified = await verifier.verify({ reference: 'SMN999000' });
      expect(verified).toMatchObject({
        provider: 'telebirr',
        providerReference: 'SMN999000',
        amountMinor: 12050, // 120.50 ETB -> 12050 santim
        currency: Currency.ETB,
        status: 'SUCCESS',
        payerReference: '251911***123',
        destinationReference: 'SEMUNI_TRANSPORT',
        receiptReference: 'REC_LET_777',
        source: 'links.et',
        resolvedUrl: 'https://links.et/r/777',
      });
      expect(verified.paymentDate).toBeInstanceOf(Date);
      expect(verified.verifiedAt).toBeInstanceOf(Date);
    });

    it('rejects image receipt if upstream verification did not verify the receipt', async () => {
      // Simulates an unverified OCR result: links.et recognized text via OCR, but bank rejected or did not verify
      fetchMock.mockResolvedValueOnce(
        jsonResponse({
          success: false,
          status: 'FAILED',
          detection: {
            ocr_confidence: 0.92,
            detected_provider: 'telebirr',
            raw_text: 'Telebirr payment 500 ETB to Semuni',
          },
          upstream: {
            verified: false,
            status: 'UNVERIFIED',
          },
        }),
      );

      await expect(
        verifier.verifyImage({ imageBase64: 'fake-screenshot-data' }),
      ).rejects.toThrow(LinksEtInvalidReceiptException);
    });

    it('accepts image receipt when upstream bank verification succeeds', async () => {
      fetchMock.mockResolvedValueOnce(
        jsonResponse({
          success: true,
          status: 'SUCCESS',
          upstream: {
            verified: true,
            status: 'VERIFIED',
            result: {
              receipt: {
                provider: 'telebirr',
                provider_reference: 'SMN_UPSTREAM_123',
                total_amount: '45.00',
                currency: 'ETB',
                status: 'PAID',
                receipt_id: 'UPSTREAM_REC_45',
              },
            },
          },
        }),
      );

      const verified = await verifier.verifyImage({ imageBase64: 'valid-img-data' });
      expect(verified.providerReference).toBe('SMN_UPSTREAM_123');
      expect(verified.amountMinor).toBe(4500);
      expect(verified.status).toBe('SUCCESS');
    });

    it('rejects receipt with non-ETB currency', async () => {
      fetchMock.mockResolvedValueOnce(
        jsonResponse({
          success: true,
          status: 'SUCCESS',
          receipt: {
            provider: 'telebirr',
            provider_reference: 'SMN_USD_01',
            amount: '10.00',
            currency: 'USD',
            status: 'SUCCESS',
          },
        }),
      );

      await expect(verifier.verify({ reference: 'SMN_USD_01' })).rejects.toThrow(
        LinksEtVerificationMismatchException,
      );
    });

    it('rejects receipt with missing amount or provider reference', async () => {
      fetchMock.mockResolvedValueOnce(
        jsonResponse({
          success: true,
          status: 'SUCCESS',
          receipt: {
            provider: 'telebirr',
            // Missing provider_reference
            amount: '10.00',
          },
        }),
      );

      await expect(verifier.verify({ reference: 'test' })).rejects.toThrow(
        LinksEtInvalidReceiptException,
      );
    });
  });
});
