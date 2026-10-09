# Integration Environments: Telebirr, links.et & Voxide

This document details environment configurations across **Development**, **Staging**, and **Production** for semuni's payment, receipt verification, and voice integrations.

> [!CAUTION]
> **Zero Credential Exposure Rule**: Production API keys, private keys, and application secrets must **never** be committed to version control, logged in application logs, or bundled into client applications (Flutter mobile or web browser bundles).

---

## 1. Telebirr Environments (H5 C2B Web Checkout)

| Variable | Development (Local/Mock) | Staging (Ethio Telecom Sandbox) | Production | Secret? |
|---|---|---|---|---|
| `TELEBIRR_BASE_URL` | `https://telebirr.test/apiaccess/payment/gateway` | `https://196.188.120.3:10443/apiaccess/payment/gateway` | `https://app.telebirr.et/apiaccess/payment/gateway` | No |
| `TELEBIRR_WEB_CHECKOUT_URL` | `https://telebirr.test/payment/web/paygate?` | `https://196.188.120.3:10443/payment/web/paygate?` | `https://app.telebirr.et/payment/web/paygate?` | No |
| `TELEBIRR_FABRIC_APP_ID` | `mock-fabric-app` | Assigned sandbox Fabric App ID | Production Fabric App ID | Yes (Backend only) |
| `TELEBIRR_APP_SECRET` | `mock-app-secret` | Sandbox App Secret | Production App Secret | **YES (CRITICAL)** |
| `TELEBIRR_MERCHANT_APP_ID`| `1227484825753601` | Sandbox Merchant App ID | Production Merchant App ID | Yes (Backend only) |
| `TELEBIRR_MERCHANT_CODE` | `101011` | Sandbox Merchant Short Code | Production Merchant Short Code | Yes (Backend only) |
| `TELEBIRR_PRIVATE_KEY` | Development RSA PKCS#8 Key | Sandbox Merchant RSA Private Key | Production Merchant RSA Private Key | **YES (CRITICAL)** |
| `TELEBIRR_PUBLIC_KEY` | Development RSA SPKI Key | Ethio Telecom Sandbox Public Key | Ethio Telecom Production Public Key | Yes (SPKI Public) |
| `TELEBIRR_NOTIFY_URL` | `http://localhost:3000/api/v1/wallet/webhooks/telebirr` | `https://staging-api.semuni.et/api/v1/wallet/webhooks/telebirr` | `https://api.semuni.et/api/v1/wallet/webhooks/telebirr` | No |
| `TELEBIRR_REDIRECT_URL`| `http://localhost:3000/wallet/checkout-complete` | `https://staging-app.semuni.et/wallet/checkout-complete` | `https://app.semuni.et/wallet/checkout-complete` | No |

---

## 2. links.et Environments (Receipt & Provider Verification)

| Variable | Development (Local/Mock) | Staging (Test API) | Production | Secret? |
|---|---|---|---|---|
| `LINKS_ET_BASE_URL` | `http://localhost:3000/mock/links-et` or `https://links.et` | `https://staging.links.et` | `https://links.et` | No |
| `LINKS_ET_API_KEY` | `dev-test-api-key` | Staging API Key | Production API Key | **YES (CRITICAL)** |
| `LINKS_ET_TIMEOUT_MS` | `5000` | `8000` | `8000` | No |
| `LINKS_ET_ENABLED` | `true` | `true` | `true` | No |

---

## 3. Voxide Environments (Browser Client Voice Layer)

| Variable / Setting | Development | Staging | Production | Secret? |
|---|---|---|---|---|
| Runtime Target | Browser (`web/voice/`) | Browser (`web/voice/`) | Browser (`web/voice/`) | N/A |
| API Base URL | `http://localhost:3000/api/v1` | `https://staging-api.semuni.et/api/v1` | `https://api.semuni.et/api/v1` | No |
| Auth Mechanism | User JWT Session | User JWT Session | User JWT Session | Bearer token |
| Rate Limit | 60 actions/min | 30 actions/min | 30 actions/min | No |
| Native Flutter SDK | **None** (Explicitly omitted) | **None** (Explicitly omitted) | **None** (Explicitly omitted) | N/A |
| Backend Secrets in Voice | **None** (Strictly forbidden) | **None** (Strictly forbidden) | **None** (Strictly forbidden) | N/A |

---

## 4. Secret Storage & Rotation Guidelines

1. **Vault & Cloud Secrets Manager**:
   - Store all production values in Google Cloud Secret Manager / AWS Secrets Manager / HashiCorp Vault.
   - Inject them into containerized workloads at deployment time as standard environment variables.
2. **Key Rotation Protocol**:
   - **Telebirr RSA Keys**: Generate key pairs using 2048-bit RSA (`openssl genpkey -algorithm RSA -pkeyopt rsa_keygen_bits:2048 -out private.pem`). Export public key to Ethio Telecom merchant portal.
   - **links.et API Key**: Rotate keys every 90 days or immediately upon suspected compromise via the links.et administrative dashboard.
