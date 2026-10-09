# Voxide Voice AI Integration

> Voice interaction layer for semuni. **Web-only** — never included in mobile builds.

## Architecture

```
┌─────────────────────────────────────────────────────┐
│  Flutter Web App                                     │
│                                                      │
│  ┌──────────────┐   dart:js_interop   ┌────────────┐│
│  │ VoiceAssistant│◄──────────────────►│  voxide_   ││
│  │   Widget      │                    │  bridge.js  ││
│  │  (Flutter UI) │                    │             ││
│  └──────┬───────┘                    └─────┬──────┘│
│         │                                   │       │
│         │ VoxideService                     │       │
│         │ (singleton)                       ▼       │
│         │                          ┌──────────────┐ │
│         │                          │voxide.browser│ │
│         │                          │    .js (SDK) │ │
│         │                          └──────┬───────┘ │
│         │                                 │         │
└─────────┼─────────────────────────────────┼─────────┘
          │                                 │
          ▼                                 ▼
   ┌──────────────┐                 ┌──────────────┐
   │  semuni REST  │                 │  Voxide      │
   │  API Backend  │                 │  Cloud API   │
   └──────────────┘                 └──────────────┘
```

## Files

| File | Purpose |
|------|---------|
| `web/voxide.browser.js` | UMD core SDK (copied from `@voxide/react/dist`) |
| `web/voxide_bridge.js` | JS bridge: init, capabilities, state binding |
| `lib/services/voxide_service.dart` | Dart↔JS interop singleton |
| `lib/features/voice/voice_assistant_widget.dart` | Flutter overlay (FAB + chat panel) |
| `lib/app/app.dart` | Root mount point (web-only Stack) |

## Public Key

```
vox_pub_e239d8f56f7369eac57ca72b33ea607c20b251282dfe8399
```

This is a **publishable** key, safe to include in client-side code.

## Registered Capabilities

### Read-only (safe)
| Capability | API Endpoint |
|------------|-------------|
| `getWalletBalance` | `GET /api/v1/wallet` |
| `getRecentTransactions` | `GET /api/v1/wallet/transactions` |
| `getActiveRoutes` | `GET /api/v1/routes?active=true` |
| `getCurrentFare` | `GET /api/v1/fares/:routeId` |
| `getMyTrips` | `GET /api/v1/trips/mine` |
| `getTripDetails` | `GET /api/v1/trips/:tripId` |
| `getDriverEarnings` | `GET /api/v1/drivers/earnings?period=` |
| `getWithdrawalStatus` | `GET /api/v1/withdrawals/latest` |

### Financial (dangerous: true)
All financial capabilities include `idempotencyKey` and require explicit user confirmation before execution.

| Capability | API Endpoint |
|------------|-------------|
| `createTrip` | `POST /api/v1/trips` |
| `payForTrip` | `POST /api/v1/trips/:tripId/pay` |
| `initiateTopUp` | `POST /api/v1/wallet/top-up` |
| `requestWithdrawal` | `POST /api/v1/withdrawals` |

## Security

- **No secrets in JS**: The bridge authenticates via the user's JWT, passed from Dart
- **Token sync**: `VoxideService` syncs the access token on every poll tick and clears it on session expiry
- **Idempotency**: Every financial mutation generates a unique `idempotencyKey` via `crypto.randomUUID()`
- **Confirmation**: All `dangerous: true` capabilities trigger the SDK's built-in confirmation dialog before executing
- **State binding**: Only safe, non-sensitive UI state is exposed via `ai.bindState()`
- **Web-only**: The widget renders `SizedBox.shrink()` on non-web platforms; the JS files are never loaded in native builds

## How It Works

1. `web/index.html` loads `voxide.browser.js` then `voxide_bridge.js`
2. The bridge creates a `VoxideClient`, registers all capabilities, and exposes `window._voxideBridge`
3. Flutter boots, `SmuniApp.build()` wraps `MaterialApp` in a `Stack` with `VoiceAssistantWidget` on top (web only)
4. `VoiceAssistantWidget.initState()` calls `VoxideService.init()`, which calls `window._voxideBridge.init()` via `dart:js_interop`
5. User taps the mic FAB → `VoxideService.connect()` → live voice session
6. User speaks → SDK resolves to a registered capability → JS bridge calls semuni REST API
7. Long-press the FAB → chat panel for text input

## Updating the SDK

```bash
cd backend && npm install @voxide/react@latest
cp node_modules/@voxide/react/dist/voxide.browser.js ../web/voxide.browser.js
```

## Separation of Concerns

The three integrations remain cleanly separated:

- **TELEBIRR**: Payment provider (backend only, secure signing)
- **LINKS.ET**: Receipt/verification service (backend only)  
- **VOXIDE**: Voice interaction layer (web frontend only, calls REST API via user's JWT)
