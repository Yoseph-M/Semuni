# links.et Integration Guide (External Receipt & Payment Verification)

## 1. Purpose
`links.et` is an independent, external payment and receipt verification service. In semuni, it serves as an **authoritative secondary verification rail** to corroborate external bank transfers, Telebirr transactions, CBE Birr receipts, or payment screenshots.

> [!IMPORTANT]
> **links.et is NOT the semuni ledger and NOT a wallet-credit authority by itself.**
> - links.et only verifies whether a receipt or external transaction occurred on the banking/provider network.
> - semuni's backend maintains full sovereignty over the financial state: top-up intents, wallet balances, and ledger entries.
> - A verified receipt will **never** credit a wallet unless it matches a pre-registered semuni `TopUpIntent` (matching amount, currency, and provider reference) and passes replay checks.

---

## 2. Architecture
```
┌──────────────┐          ┌────────────────┐          ┌────────────────┐
│  Passenger   │          │ semuni Backend │          │    links.et    │
│ (App / Web)  │          │   (NestJS)     │          │    Service     │
└──────┬───────┘          └───────┬────────┘          └───────┬────────┘
       │                          │                           │
       │ 1. Submit Receipt URL    │                           │
       │    or Screenshot Base64  │                           │
       │─────────────────────────>│                           │
       │                          │ 2. Validate Intent Status │
       │                          │    (Must be PENDING)      │
       │                          │                           │
       │                          │ 3. POST /api/verify or    │
       │                          │    POST /api/verify-image │
       │                          │    (Header: x-api-key)    │
       │                          │──────────────────────────>│
       │                          │                           │
       │                          │ 4. Upstream Bank Match    │
       │                          │<──────────────────────────│
       │                          │                           │
       │                          │ 5. Normalize into         │
       │                          │    VerifiedExternalPayment│
       │                          │                           │
       │                          │ 6. Guardrail Checks:      │
       │                          │    - amountMinor matches  │
       │                          │    - currency === ETB     │
       │                          │    - providerRef matches  │
       │                          │    - receipt not reused   │
       │                          │                           │
       │                          │ 7. Settle Intent & Credit │
       │                          │    Wallet Exactly Once    │
       │ 8. Settle Result         │                           │
       │<─────────────────────────│                           │
```

---

## 3. Configuration & Environment Variables

| Variable | Description | Default / Example | Environment |
|---|---|---|---|
| `LINKS_ET_BASE_URL` | Base API URL for links.et service | `https://links.et` | All |
| `LINKS_ET_API_KEY` | Secret API key passed via `x-api-key` header | `[REDACTED]` | Backend only |
| `LINKS_ET_TIMEOUT_MS` | Request timeout before throwing Gateway Timeout | `8000` | Optional (default: 8000) |
| `LINKS_ET_ENABLED` | Global toggle for links.et integration | `true` | Optional (default: true) |

> [!CAUTION]
> Under no circumstances must `LINKS_ET_API_KEY` be exposed to Flutter clients, Voxide web runtime, browser local storage, or repository version control.

---

## 4. Verification Capabilities & Endpoints

### 4.1 URL / Reference Verification (`POST /api/verify`)
- Verifies a transaction by its links.et short URL (e.g., `https://links.et/r/FT240123ABC`) or raw provider transaction reference (e.g., `SMN123456789`).
- Handles async processing states (`QUEUED`, `PROCESSING`) by polling the designated polling endpoint up to a bounded retry limit.

### 4.2 Screenshot Verification (`POST /api/verify-image`)
- Accepts a base64-encoded image string with MIME type.
- **Strict Verification Policy**: Unverified OCR text alone is **strictly discarded**. The receipt is only accepted if `upstream.result.receipt` contains cryptographically or bank-verified transaction data confirming genuine payment settlement.

---

## 5. Normalized Model: `VerifiedExternalPayment`
The `LinksEtReceiptVerifier` transforms disparate provider responses into a canonical domain model:
```typescript
export interface VerifiedExternalPayment {
  provider: 'telebirr' | 'cbe' | string;
  providerReference: string;
  amountMinor: number;          // Integer santim (e.g. 200.00 ETB -> 20000)
  currency: Currency;           // Currency.ETB
  status: 'SUCCESS' | 'FAILED' | 'PENDING';
  payerReference?: string;
  destinationReference?: string;
  receiptReference: string;     // Unique identifier for replay protection
  paymentDate: Date;
  source: 'links.et';
  resolvedUrl?: string;
  verifiedAt: Date;
  rawMetadata?: Record<string, unknown>;
}
```

---

## 6. Security Boundaries & Guardrails

1. **Replay Protection**:
   - `TopUpIntent.receiptReference` is indexed and enforced with a unique database constraint.
   - When a receipt is presented, the system checks whether `receiptReference` has already been recorded on a settled intent. Reused receipts are rejected with `PAYMENT_ALREADY_PROCESSED` (HTTP 409).
2. **Intent Ownership & Status**:
   - The user presenting the receipt must own the `TopUpIntent`.
   - The intent must be in `PENDING` status. `SUCCESS`, `EXPIRED`, or `FAILED` intents cannot be settled.
3. **Amount & Currency Strictness**:
   - The verified receipt's `amountMinor` must exactly match the intent's `amountMinor`.
   - The currency must be `ETB`.
4. **Provider Reference Consistency**:
   - If the intent already has a recorded `providerReference`, the receipt's provider reference must match.

---

## 7. Error Handling & Retry Policies

- **Client Errors (4xx)**: `400 Bad Request`, `401 Unauthorized`, `404 Not Found`, and `422 Unprocessable Entity` are treated as fatal business errors and are **never retried**.
- **Rate Limiting (429)**: Throws `LinksEtRateLimitException` and parses the `Retry-After` header to avoid cascading denial-of-service.
- **Server Errors (5xx)**: Retried up to 3 times with exponential backoff (200ms, 400ms, 600ms).
- **Timeouts**: Handled with `AbortSignal` and mapped cleanly to `LinksEtTimeoutException` (HTTP 504).

---

## 8. Observability & Audit Logging

Structured logging conforming to Section 54:
```json
{
  "integration": "links-et",
  "provider": "links.et",
  "operation": "verify | verify-image | poll",
  "reference": "FT240123ABC",
  "duration": 182,
  "result": "SUCCESS | FAILED",
  "failureCode": "LinksEtInvalidReceiptException"
}
```
API keys, image payloads, and customer personal details are sanitized and never logged.
