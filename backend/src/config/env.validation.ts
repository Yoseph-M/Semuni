/**
 * Boot-time configuration validation, wired into `ConfigModule.forRoot`.
 *
 * Always: both JWT secrets must exist. In production the process refuses to
 * start with development-grade settings (placeholder or short secrets, open
 * CORS, the mock payment provider, missing database credentials), so an unsafe
 * deployment fails loudly instead of running.
 */

import { TELEBIRR_REQUIRED_ENV } from '../payments/providers/telebirr/telebirr-payment-provider';

const MIN_SECRET_LENGTH = 32;

const PLACEHOLDER_MARKERS = ['change-me', 'change-in-production', 'dev-', 'ci-'];

const REQUIRED_IN_PRODUCTION = [
  'DB_HOST',
  'DB_PORT',
  'DB_USERNAME',
  'DB_PASSWORD',
  'DB_DATABASE',
  'CORS_ORIGIN',
];

export function validateEnv(
  config: Record<string, unknown>,
): Record<string, unknown> {
  const errors: string[] = [];
  const get = (key: string): string | undefined => {
    const value = config[key];
    return value === undefined || value === null || value === ''
      ? undefined
      : String(value);
  };

  const access = get('JWT_ACCESS_SECRET');
  const refresh = get('JWT_REFRESH_SECRET');
  if (!access) errors.push('JWT_ACCESS_SECRET is required');
  if (!refresh) errors.push('JWT_REFRESH_SECRET is required');

  if (get('NODE_ENV') === 'production') {
    for (const key of REQUIRED_IN_PRODUCTION) {
      if (!get(key)) errors.push(`${key} is required in production`);
    }

    for (const [key, value] of [
      ['JWT_ACCESS_SECRET', access],
      ['JWT_REFRESH_SECRET', refresh],
    ] as const) {
      if (!value) continue;
      if (value.length < MIN_SECRET_LENGTH) {
        errors.push(`${key} must be at least ${MIN_SECRET_LENGTH} characters`);
      }
      const lower = value.toLowerCase();
      if (PLACEHOLDER_MARKERS.some((marker) => lower.includes(marker))) {
        errors.push(`${key} looks like a placeholder value`);
      }
    }
    if (access && refresh && access === refresh) {
      errors.push('JWT_ACCESS_SECRET and JWT_REFRESH_SECRET must differ');
    }

    const cors = get('CORS_ORIGIN');
    if (cors && cors.split(',').some((origin) => origin.trim() === '*')) {
      errors.push('CORS_ORIGIN must list explicit origins in production, not *');
    }

    const provider = (get('PAYMENT_PROVIDER') ?? 'MOCK').toUpperCase();
    if (provider === 'MOCK') {
      errors.push('PAYMENT_PROVIDER=MOCK is not allowed in production');
    }
    if (provider === 'TELEBIRR') {
      for (const key of TELEBIRR_REQUIRED_ENV) {
        if (!get(key)) errors.push(`${key} is required when PAYMENT_PROVIDER=TELEBIRR`);
      }
      for (const key of ['TELEBIRR_BASE_URL', 'TELEBIRR_WEB_CHECKOUT_URL', 'TELEBIRR_NOTIFY_URL']) {
        const url = get(key);
        if (url && !url.startsWith('https://')) errors.push(`${key} must use https`);
      }
    }

    if (get('DB_PASSWORD') === 'semuni_dev_password') {
      errors.push('DB_PASSWORD is the development default');
    }
  }

  if (errors.length) {
    throw new Error(
      `Invalid environment configuration:\n  - ${errors.join('\n  - ')}`,
    );
  }
  return config;
}
