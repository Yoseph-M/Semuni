# Telebirr Integration Guide (H5 C2B Web Checkout)

## 1. Purpose
Telebirr is an external payment provider rail used within semuni to facilitate **passenger wallet top-ups** via the Telebirr H5 C2B (Customer-to-Business) web checkout interface.

> [!IMPORTANT]
> **Telebirr is NOT the system of record for semuni fares, trips, or wallets.**
> - External money entering semuni: `Passenger -> Telebirr -> semuni TopUpIntent -> Wallet Credit -> Ledger Entry`.
> - Internal trip payment: `Passenger Wallet -> semuni Trip Settlement -> Driver Wallet` (governed entirely by semuni's internal ledger, never Telebirr).
> - Payouts/Withdrawals: Telebirr does **NOT** support driver payouts or passenger withdrawals in this architecture.

---

## 2. Architecture
```
┌─────────────┐        ┌────────────────┐        ┌──────────────────┐
│  Passenger  │        │ semuni Backend │        │ Telebirr Gateway │
│  (Flutter)  │        │   (NestJS)     │        │    (External)    │
└──────┬──────┘        └───────┬────────┘        └────────┬─────────┘
       │                       │                          │
       │ 1. Initiate Top-Up    │                          │
       │──────────────────────>│                          │
       │                       │ 2. Acquire Fabric Token  │
       │                       │─────────────────────────>│
       │                       │<─────────────────────────│
       │                       │ 3. payment.preorder (RSA)│
       │                       │─────────────────────────>│
       │                       │<─────────────────────────│
       │ 4. checkoutUrl + ref  │                          │
       │<──────────────────────│                          │
       │                       │                          │
       │ 5. H5 Web Checkout    │                          │
       │─────────────────────────────────────────────────>│
       │                       │                          │
       │                       │ 6. Webhook Notification  │
       │                       │<─────────────────────────│
       │                       │ 7. payment.queryorder    │
       │                       │─────────────────────────>│
       │                       │<─────────────────────────│
       │                       │                          │
       │                       │ 8. Exactly-Once Settle   │
       │                       │    (Ledger + Wallet)     │
       │ 9. Query Status       │                          │
       │──────────────────────>│                          │
       │    (SUCCESS)          │                          │
```

---

## 3. Configuration & Environment Variables

All Telebirr credentials reside strictly in the backend environment. They are never exposed to Flutter, web clients, or logs.

| Variable | Description | Example / Default | Environment |
|---|---|---|---|
| `TELEBIRR_BASE_URL` | Base API access endpoint | `https://telebirr.test/apiaccess/payment/gateway` | All |
| `TELEBIRR_WEB_CHECKOUT_URL` | H5 payment web checkout redirect URL | `https://telebirr.test/payment/web/paygate?` | All |
| `TELEBIRR_FABRIC_APP_ID` | Fabric application identifier | Provided by Ethio Telecom | Prod / Staging |
| `TELEBIRR_APP_SECRET` | Fabric app secret key (token acquisition) | `[REDACTED]` | Backend only |
| `TELEBIRR_MERCHANT_APP_ID` | Telebirr merchant application ID | Provided by Ethio Telecom | Prod / Staging |
| `TELEBIRR_MERCHANT_CODE` | Telebirr merchant short code | Provided by Ethio Telecom | Prod / Staging |
| `TELEBIRR_PRIVATE_KEY` | semuni RSA PKCS#8 private key for signing | `-----BEGIN PRIVATE KEY-----...` | Backend only |
| `TELEBIRR_PUBLIC_KEY` | Telebirr RSA SPKI public key for verification| `-----BEGIN PUBLIC KEY-----...` | Backend only |
| `TELEBIRR_NOTIFY_URL` | Public webhook callback URL | `https://api.semuni.et/api/v1/wallet/webhooks/telebirr` | Prod / Staging |
| `TELEBIRR_REDIRECT_URL`| Redirect URL after checkout completion | `https://app.semuni.et/wallet/checkout-complete` | Prod / Staging |
| `TELEBIRR_HTTP_TIMEOUT_MS` | Network timeout for Telebirr HTTP requests | `5000` | Optional (default: 5000) |
| `TELEBIRR_ORDER_TIMEOUT_MINUTES` | PreOrder validity expiry | `120` | Optional (default: 120) |
| `TELEBIRR_NOTIFY_MAX_AGE_SECONDS`| Maximum allowed age for notification freshness| `300` | Optional (default: 300) |

---

## 4. Security Boundary & Signing Rules

1. **RSA-SHA256 Signatures**:
   - Requests sent to Telebirr (`payment.preorder`, `payment.queryorder`) are canonically sorted across all keys (flattening `biz_content`), formatted into `k1=v1&k2=v2...`, and signed with semuni's RSA private key.
   - Incoming webhooks (`POST /wallet/webhooks/telebirr`) are validated against Telebirr's public key. If the signature is invalid or tampered, the webhook is immediately rejected with HTTP 400.
2. **Notification Freshness**:
   - Webhook timestamps (`notify_time`) older than `TELEBIRR_NOTIFY_MAX_AGE_SECONDS` (5 minutes) or in the future are rejected to prevent replay attacks.
3. **Merchant Isolation**:
   - Webhook payloads must match `merch_code` and `appid`. Payloads destined for other merchants are rejected.
4. **Amount & Currency Validation**:
   - Amounts are handled strictly in integer santim (minor units, 1 ETB = 100 santim). Floating-point conversions are forbidden.
   - Any currency other than `ETB` is rejected.
5. **Secret Boundaries**:
   - No Telebirr private keys, secrets, or raw token headers are logged or transmitted outside the secure backend network boundary.

---

## 5. Request & Failure Flow

### Request Flow
1. Passenger client calls `POST /wallet/top-up/intent` with `{ amount: 10000, provider: "TELEBIRR", idempotencyKey: "uuid" }`.
2. semuni creates `TopUpIntent` in `PENDING` status and calls Telebirr `payment.preorder`.
3. Telebirr returns `prepay_id`. semuni constructs `checkoutUrl` with encrypted query parameters.
4. Passenger navigates to `checkoutUrl` in mobile webview / external browser and completes payment.
5. Telebirr sends signed `POST` webhook to `TELEBIRR_NOTIFY_URL`.
6. semuni validates webhook signature, queries Telebirr `payment.queryorder` to corroborate state directly from the source, updates `TopUpIntent` status to `SUCCESS`, credits user wallet, and writes an immutable double-entry ledger record.

### Failure & Retry Flow
1. **Network Timeout during preOrder**: Intent remains in `PENDING` with retry allowed using the same `idempotencyKey`.
2. **Payment Cancelled / Expired**: `TopUpIntent` transitions to `EXPIRED` once `TELEBIRR_ORDER_TIMEOUT_MINUTES` elapses without payment.
3. **Webhook Dropped / Delayed**:
   - Passenger app polls `GET /wallet/top-up/intent/:id`.
   - Top-up reconciliation cron (`TopUpService.reconcilePending()`) queries Telebirr for all pending intents older than 2 minutes.
   - Alternatively, passenger can provide receipt reference via `links.et` verification.

---

## 6. Reconciliation & Double-Crediting Prevention

- **Idempotent Webhooks**: If a webhook is redelivered or replayed, `TopUpService` verifies that the intent is already `SUCCESS` and returns `code: "0", msg: "success"` immediately without modifying wallet balance or creating ledger entries.
- **Provider Reference Uniqueness**: Each intent has a unique `providerReference` (`merch_order_id`). Wallet credit via `walletsService.topUp(userId, amount, providerReference)` uses transactional database locks and checks for duplicate references before executing credits.

---

## 7. Unsupported Capabilities
- **Withdrawals / Payouts**: Telebirr B2C / disbursement is explicitly not configured or supported in this release. Drivers withdraw earnings via manual banking rails or supported payout gateways.
- **Direct Taxi Trip Settlement**: Passenger taxi fares cannot be directly billed through Telebirr on a per-meter basis; passengers must fund their semuni wallet first.

---

## 8. Observability & Audit Logging

All Telebirr interactions emit structured logs matching Section 54:
```json
{
  "integration": "telebirr",
  "provider": "telebirr",
  "operation": "preOrder | queryOrder | webhook",
  "reference": "SMN1728000000abcdef",
  "requestId": "req-12345",
  "duration": 42,
  "result": "SUCCESS | FAILED",
  "failureCode": "SIGNATURE_VERIFICATION_FAILED"
}
```
Provider secrets, private keys, and authorization tokens are strictly omitted.
