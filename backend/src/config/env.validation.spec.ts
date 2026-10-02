import { validateEnv } from './env.validation';

const strongAccess = 'a'.repeat(16) + 'b'.repeat(16) + '1x';
const strongRefresh = 'c'.repeat(16) + 'd'.repeat(16) + '2y';

const production = {
  NODE_ENV: 'production',
  JWT_ACCESS_SECRET: strongAccess,
  JWT_REFRESH_SECRET: strongRefresh,
  DB_HOST: 'db.internal',
  DB_PORT: '5432',
  DB_USERNAME: 'semuni',
  DB_PASSWORD: 'a-real-password',
  DB_DATABASE: 'semuni',
  CORS_ORIGIN: 'https://app.semuni.et',
  PAYMENT_PROVIDER: 'TELEBIRR',
  TELEBIRR_BASE_URL: 'https://superapp.ethiomobilemoney.et:38443/apiaccess/payment/gateway',
  TELEBIRR_WEB_CHECKOUT_URL: 'https://superapp.ethiomobilemoney.et:38443/payment/web/paygate?',
  TELEBIRR_FABRIC_APP_ID: 'fabric-app-id',
  TELEBIRR_APP_SECRET: 'app-secret',
  TELEBIRR_MERCHANT_APP_ID: '1227484825753601',
  TELEBIRR_MERCHANT_CODE: '101011',
  TELEBIRR_PRIVATE_KEY: 'private-key',
  TELEBIRR_PUBLIC_KEY: 'public-key',
  TELEBIRR_NOTIFY_URL: 'https://api.semuni.et/api/v1/wallet/webhooks/telebirr',
};

describe('validateEnv', () => {
  it('requires both JWT secrets in every environment', () => {
    expect(() => validateEnv({ NODE_ENV: 'development' })).toThrow(
      /JWT_ACCESS_SECRET is required[\s\S]*JWT_REFRESH_SECRET is required/,
    );
  });

  it('accepts development defaults outside production', () => {
    const env = {
      NODE_ENV: 'development',
      JWT_ACCESS_SECRET: 'change-me-access',
      JWT_REFRESH_SECRET: 'change-me-access',
      CORS_ORIGIN: '*',
      PAYMENT_PROVIDER: 'MOCK',
    };
    expect(validateEnv(env)).toBe(env);
  });

  it('accepts a safe production configuration', () => {
    expect(validateEnv({ ...production })).toEqual(production);
  });

  it.each([
    ['short secret', { JWT_ACCESS_SECRET: 'short' }, /at least 32/],
    [
      'placeholder secret',
      { JWT_ACCESS_SECRET: 'change-me-access-secret-at-least-32-chars' },
      /placeholder/,
    ],
    ['identical secrets', { JWT_REFRESH_SECRET: strongAccess }, /must differ/],
    ['wildcard CORS', { CORS_ORIGIN: '*' }, /CORS_ORIGIN/],
    ['mock provider', { PAYMENT_PROVIDER: 'MOCK' }, /MOCK is not allowed/],
    ['missing Telebirr credentials', { TELEBIRR_APP_SECRET: undefined }, /TELEBIRR_APP_SECRET is required/],
    ['plain-http Telebirr notify URL', { TELEBIRR_NOTIFY_URL: 'http://api.semuni.et/hook' }, /TELEBIRR_NOTIFY_URL must use https/],
    ['missing provider (defaults to mock)', { PAYMENT_PROVIDER: undefined }, /MOCK/],
    ['missing DB password', { DB_PASSWORD: '' }, /DB_PASSWORD is required/],
    ['dev DB password', { DB_PASSWORD: 'semuni_dev_password' }, /development default/],
  ])('rejects %s in production', (_label, override, message) => {
    expect(() => validateEnv({ ...production, ...override })).toThrow(message);
  });
});
