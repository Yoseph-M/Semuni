import {
  constants,
  createPrivateKey,
  createPublicKey,
  KeyObject,
  sign,
  verify,
} from 'crypto';

/**
 * Telebirr request/notification signatures.
 *
 * Per the Telebirr developer portal ("Request Signature Process"): every
 * top-level field and every `biz_content` field, except the excluded ones, is
 * sorted by key, joined as `key=value` with `&`, and signed with
 * SHA256withRSAandMGF1 (RSA-PSS, SHA-256). The result is base64 in `sign`, with
 * `sign_type=SHA256WithRSA`.
 */
const EXCLUDED_FIELDS = new Set([
  'sign',
  'sign_type',
  'header',
  'refund_info',
  'openType',
  'raw_request',
  'biz_content',
  'wallet_reference_data',
]);

export const TELEBIRR_SIGN_TYPE = 'SHA256WithRSA';

export function canonicalSignString(payload: Record<string, unknown>): string {
  const fields = new Map<string, string>();
  const collect = (source: Record<string, unknown>) => {
    for (const [key, value] of Object.entries(source)) {
      if (EXCLUDED_FIELDS.has(key) || value === undefined || value === null) {
        continue;
      }
      fields.set(key, String(value));
    }
  };
  collect(payload);
  const biz = payload.biz_content;
  if (biz && typeof biz === 'object') collect(biz as Record<string, unknown>);

  return [...fields.keys()]
    .sort()
    .map((key) => `${key}=${fields.get(key)}`)
    .join('&');
}

export function loadPrivateKey(material: string): KeyObject {
  try {
    return createPrivateKey(toPem(material, 'PRIVATE KEY'));
  } catch (err) {
    throw new Error(`Failed to load Telebirr private key: ${(err as Error).message}`);
  }
}

export function loadPublicKey(material: string): KeyObject {
  try {
    return createPublicKey(toPem(material, 'PUBLIC KEY'));
  } catch (err) {
    throw new Error(`Failed to load Telebirr public key: ${(err as Error).message}`);
  }
}

function toPem(material: string, label: string): string {
  const text = material.replace(/\\n/g, '\n').trim();
  if (text.includes('-----BEGIN')) return text;
  const body = text.replace(/\s+/g, '').match(/.{1,64}/g)?.join('\n') ?? '';
  return `-----BEGIN ${label}-----\n${body}\n-----END ${label}-----\n`;
}

export function signPayload(
  payload: Record<string, unknown>,
  privateKey: KeyObject,
): string {
  return sign('sha256', Buffer.from(canonicalSignString(payload)), {
    key: privateKey,
    padding: constants.RSA_PKCS1_PSS_PADDING,
    saltLength: constants.RSA_PSS_SALTLEN_DIGEST,
  }).toString('base64');
}

export function verifyPayload(
  payload: Record<string, unknown>,
  signature: string,
  publicKey: KeyObject,
): boolean {
  try {
    return verify(
      'sha256',
      Buffer.from(canonicalSignString(payload)),
      {
        key: publicKey,
        padding: constants.RSA_PKCS1_PSS_PADDING,
        saltLength: constants.RSA_PSS_SALTLEN_AUTO,
      },
      Buffer.from(signature, 'base64'),
    );
  } catch {
    return false;
  }
}
