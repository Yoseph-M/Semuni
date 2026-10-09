import { Injectable, Logger } from '@nestjs/common';
import { ConfigService } from '@nestjs/config';
import {
  LinksEtAuthException,
  LinksEtBadRequestException,
  LinksEtException,
  LinksEtInvalidReceiptException,
  LinksEtNotFoundException,
  LinksEtRateLimitException,
  LinksEtTimeoutException,
  LinksEtUnavailableException,
} from './links-et.errors';
import {
  LinksEtVerifyImageRequest,
  LinksEtVerifyImageResponse,
  LinksEtVerifyRequest,
  LinksEtVerifyResponse,
} from './links-et.types';

export const LINKS_ET_CONFIG_KEYS = [
  'LINKS_ET_BASE_URL',
  'LINKS_ET_API_KEY',
  'LINKS_ET_TIMEOUT_MS',
  'LINKS_ET_ENABLED',
] as const;

interface LinksEtSettings {
  baseUrl: string;
  apiKey: string;
  timeoutMs: number;
  enabled: boolean;
  maxRetries: number;
}

@Injectable()
export class LinksEtClient {
  private readonly logger = new Logger(LinksEtClient.name);
  private cachedSettings?: LinksEtSettings;

  constructor(private readonly configService: ConfigService) {}

  isEnabled(): boolean {
    const raw = this.configService.get('LINKS_ET_ENABLED');
    if (raw === false || raw === 'false') return false;
    return !!this.configService.get('LINKS_ET_API_KEY');
  }

  isConfigured(): boolean {
    return !!this.configService.get('LINKS_ET_API_KEY');
  }

  /**
   * Verify an external payment by reference code or receipt URL.
   */
  async verify(request: LinksEtVerifyRequest): Promise<LinksEtVerifyResponse> {
    const startTime = Date.now();
    const reference = request.reference ?? (request.url ? this.sanitizeUrl(request.url) : 'unknown');

    try {
      const response = await this.post<LinksEtVerifyResponse>(
        '/api/verify',
        {
          reference: request.reference,
          url: request.url,
          idempotency_key: request.idempotencyKey,
        },
        'verify',
      );

      // Handle queued / processing status with polling if supported
      const terminalResponse = await this.pollIfQueued(response, 'verify');

      this.logAudit({
        operation: 'verify',
        reference,
        duration: Date.now() - startTime,
        result: terminalResponse.status === 'SUCCESS' ? 'SUCCESS' : 'FAILED',
        failureCode: terminalResponse.status !== 'SUCCESS' ? terminalResponse.error ?? terminalResponse.status : undefined,
      });

      return terminalResponse;
    } catch (err) {
      this.logAudit({
        operation: 'verify',
        reference,
        duration: Date.now() - startTime,
        result: 'FAILED',
        failureCode: (err as Error).name,
      });
      throw err;
    }
  }

  /**
   * Verify an external payment screenshot / image payload.
   */
  async verifyImage(request: LinksEtVerifyImageRequest): Promise<LinksEtVerifyImageResponse> {
    const startTime = Date.now();
    const reference = `img_${request.imageBase64.slice(0, 16)}...`;

    try {
      const response = await this.post<LinksEtVerifyImageResponse>(
        '/api/verify-image',
        {
          image: request.imageBase64,
          mime_type: request.mimeType ?? 'image/jpeg',
          idempotency_key: request.idempotencyKey,
        },
        'verify-image',
      );

      const terminalResponse = await this.pollIfQueued(response, 'verify-image');

      this.logAudit({
        operation: 'verify-image',
        reference,
        duration: Date.now() - startTime,
        result: terminalResponse.status === 'SUCCESS' ? 'SUCCESS' : 'FAILED',
        failureCode: terminalResponse.status !== 'SUCCESS' ? terminalResponse.error ?? terminalResponse.status : undefined,
      });

      return terminalResponse;
    } catch (err) {
      this.logAudit({
        operation: 'verify-image',
        reference,
        duration: Date.now() - startTime,
        result: 'FAILED',
        failureCode: (err as Error).name,
      });
      throw err;
    }
  }

  private async pollIfQueued<T extends LinksEtVerifyResponse>(
    initial: T,
    _operation: 'verify' | 'verify-image',
  ): Promise<T> {
    if (initial.status !== 'QUEUED' && initial.status !== 'PROCESSING') {
      return initial;
    }

    const raw = initial as unknown as Record<string, unknown>;
    const pollUrl = (raw.poll_url ?? raw.pollUrl) as string | undefined;
    if (!pollUrl) return initial;

    const maxPollAttempts = 5;
    const pollIntervalMs = 500;

    for (let attempt = 1; attempt <= maxPollAttempts; attempt++) {
      await sleep(pollIntervalMs);
      const pollStart = Date.now();
      try {
        const polled = await this.get<T>(pollUrl);
        this.logAudit({
          operation: 'poll',
          reference: pollUrl,
          duration: Date.now() - pollStart,
          result: polled.status === 'SUCCESS' ? 'SUCCESS' : 'PENDING',
        });
        if (polled.status === 'SUCCESS' || polled.status === 'FAILED') {
          return polled;
        }
      } catch (pollErr) {
        this.logAudit({
          operation: 'poll',
          reference: pollUrl,
          duration: Date.now() - pollStart,
          result: 'FAILED',
          failureCode: (pollErr as Error).name,
        });
        break;
      }
    }

    return initial;
  }

  private async post<T>(
    endpoint: string,
    body: Record<string, unknown>,
    _operation: string,
  ): Promise<T> {
    const settings = this.settings();
    const attempts = settings.maxRetries;
    let lastError: Error = new LinksEtUnavailableException('Request failed');

    for (let attempt = 1; attempt <= attempts; attempt++) {
      try {
        const response = await fetch(`${settings.baseUrl}${endpoint}`, {
          method: 'POST',
          headers: {
            'Content-Type': 'application/json',
            'x-api-key': settings.apiKey,
            Authorization: `Bearer ${settings.apiKey}`,
            Accept: 'application/json',
          },
          body: JSON.stringify(body),
          signal: AbortSignal.timeout(settings.timeoutMs),
        });

        if (response.ok) {
          return (await response.json()) as T;
        }

        // Map status codes according to Section 27/28
        const errorJson = (await response.json().catch(() => ({}))) as Record<string, unknown>;
        const errorMessage = (errorJson.message ?? errorJson.error ?? `HTTP ${response.status}`) as string;

        if (response.status === 400) {
          throw new LinksEtBadRequestException(errorMessage);
        }
        if (response.status === 401 || response.status === 403) {
          throw new LinksEtAuthException(errorMessage);
        }
        if (response.status === 404) {
          throw new LinksEtNotFoundException(errorMessage);
        }
        if (response.status === 422) {
          throw new LinksEtInvalidReceiptException(errorMessage);
        }
        if (response.status === 429) {
          const retryAfterHeader = response.headers.get('Retry-After');
          const retryAfter = retryAfterHeader ? Number(retryAfterHeader) : undefined;
          throw new LinksEtRateLimitException(
            errorMessage,
            Number.isFinite(retryAfter) ? retryAfter : undefined,
          );
        }

        // 5xx status codes: retryable
        lastError = new LinksEtUnavailableException(`links.et server error: ${errorMessage}`);
      } catch (err) {
        if (
          err instanceof LinksEtBadRequestException ||
          err instanceof LinksEtAuthException ||
          err instanceof LinksEtNotFoundException ||
          err instanceof LinksEtInvalidReceiptException ||
          err instanceof LinksEtRateLimitException
        ) {
          // Never retry 4xx errors per Section 28
          throw err;
        }

        if ((err as Error).name === 'TimeoutError' || (err as Error).name === 'AbortError') {
          lastError = new LinksEtTimeoutException('links.et request timed out');
        } else if (err instanceof LinksEtException) {
          lastError = err;
        } else {
          lastError = new LinksEtUnavailableException((err as Error).message);
        }
      }

      if (attempt < attempts) {
        await sleep(200 * attempt);
      }
    }

    throw lastError;
  }

  private async get<T>(url: string): Promise<T> {
    const settings = this.settings();
    const fullUrl = url.startsWith('http') ? url : `${settings.baseUrl}${url}`;
    const response = await fetch(fullUrl, {
      method: 'GET',
      headers: {
        'x-api-key': settings.apiKey,
        Authorization: `Bearer ${settings.apiKey}`,
        Accept: 'application/json',
      },
      signal: AbortSignal.timeout(settings.timeoutMs),
    });

    if (!response.ok) {
      throw new LinksEtUnavailableException(`HTTP ${response.status}`);
    }
    return (await response.json()) as T;
  }

  private settings(): LinksEtSettings {
    if (this.cachedSettings) return this.cachedSettings;
    const apiKey = this.configService.get<string>('LINKS_ET_API_KEY');
    if (!apiKey) {
      throw new LinksEtUnavailableException(
        'links.et integration is requested but LINKS_ET_API_KEY is not configured',
      );
    }

    const enabledRaw = this.configService.get('LINKS_ET_ENABLED');
    const enabled = enabledRaw !== false && enabledRaw !== 'false';

    const baseUrl = (this.configService.get<string>('LINKS_ET_BASE_URL') || 'https://links.et').replace(/\/+$/, '');
    const timeoutRaw = Number(this.configService.get('LINKS_ET_TIMEOUT_MS'));
    const timeoutMs = Number.isFinite(timeoutRaw) && timeoutRaw > 0 ? timeoutRaw : 10_000;

    this.cachedSettings = {
      baseUrl,
      apiKey,
      timeoutMs,
      enabled,
      maxRetries: 3,
    };
    return this.cachedSettings;
  }

  private logAudit(entry: {
    operation: 'verify' | 'verify-image' | 'poll';
    reference?: string;
    duration?: number;
    result: 'SUCCESS' | 'FAILED' | 'PENDING';
    failureCode?: string;
  }): void {
    const logPayload = {
      integration: 'links-et',
      provider: 'links.et',
      ...entry,
    };
    if (entry.result === 'FAILED') {
      this.logger.warn(JSON.stringify(logPayload));
    } else {
      this.logger.log(JSON.stringify(logPayload));
    }
  }

  private sanitizeUrl(url: string): string {
    try {
      const parsed = new URL(url);
      return `${parsed.origin}${parsed.pathname}`;
    } catch {
      return 'invalid-url';
    }
  }
}

function sleep(ms: number): Promise<void> {
  return new Promise((resolve) => setTimeout(resolve, ms));
}
