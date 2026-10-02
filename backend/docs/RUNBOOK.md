# Semuni backend runbook

## Probes
| Endpoint | Use | Checks |
|---|---|---|
| `GET /api/v1/health/live` | liveness (Docker `HEALTHCHECK`, k8s `livenessProbe`) | process only |
| `GET /api/v1/health/ready` (also `/health`) | readiness / load-balancer | DB ping + no pending migrations |

A failing readiness probe after a deploy usually means `npm run migration:run` was not executed.

## Scheduled jobs
Both jobs are idempotent and safe to run concurrently with the API and with themselves.

| Command (built image) | Suggested schedule | Purpose |
|---|---|---|
| `node dist/wallets/reconcile-top-ups.js` | every 5 min | settle PENDING top-ups via Telebirr queryOrder; expire unpaid ones after `RECONCILE_EXPIRE_AFTER_MINUTES` |
| `node dist/notifications/dispatch-notifications.js` | every 1 min | deliver `notification_outbox` rows (retries with backoff, gives up after 5) |
| `node dist/database/verify-financial-integrity.js --strict` | hourly | ledger/wallet invariants; non-zero exit = page someone |

Reconcile exits non-zero when a provider call failed (Telebirr unreachable); the affected top-ups stay PENDING and are retried next run.

## Telebirr
1. Obtain from Ethio Telecom: fabric app id + app secret, merchant app id, merchant code; generate an RSA key pair and register the public key; obtain Telebirr's public key.
2. Set the `TELEBIRR_*` variables (see `.env.example`) and `PAYMENT_PROVIDER=TELEBIRR`. Production refuses to start if any are missing or not https.
3. Ask Telebirr to whitelist `TELEBIRR_NOTIFY_URL` (`POST /api/v1/wallet/webhooks/telebirr`).
4. Test in the developer testbed first: one top-up end to end, then a replayed notification (must return the same result without a second credit).

Rejected notifications log `Rejected Telebirr notification: <reason>` (signature mismatch, stale notify_time, merchant mismatch). A burst of these is either a key mismatch or an attack; credits are never made from the notification body alone.

**Key rotation:** register the new public key with Telebirr, deploy the new `TELEBIRR_PRIVATE_KEY`, then revoke the old one. When Telebirr rotates theirs, update `TELEBIRR_PUBLIC_KEY`.

Telebirr withdrawals are intentionally disabled (no documented payout API); requests return 501 and do not debit the wallet.

## Logs
Production logs are one JSON object per line (`LOG_FORMAT=json`), with `requestId` (also returned as `X-Request-ID`) and `userId` in the context. Secrets, provider payloads and request bodies are never logged.

## Audit trail
`audit_logs` records every POST/PUT/PATCH/DELETE: actor, role, route pattern, resource id, status code, request id and IP (never bodies). The table is append-only at the database level.

```sql
SELECT "createdAt", "actorUserId", action, "statusCode"
FROM audit_logs WHERE "actorRole" = 'ADMIN' ORDER BY "createdAt" DESC LIMIT 50;
```

## Incidents
- **Wallet/ledger mismatch** (`verify:financial` fails): stop withdrawals, run `npm run verify:financial -- --strict` for the offending wallets, correct with compensating ledger entries only (the ledger rejects UPDATE/DELETE).
- **Top-up paid but not credited**: run reconcile; if the intent is FAILED with "amount does not match", compare with the Telebirr merchant portal before any manual credit.
- **Notifications stuck**: `SELECT status, count(*) FROM notification_outbox GROUP BY 1;` FAILED rows keep `lastError`; reset with `UPDATE notification_outbox SET status='PENDING', attempts=0 WHERE ...`.

## Database roles
The application role must not be a superuser (test cleanup uses `session_replication_role`, which bypasses the append-only triggers).
