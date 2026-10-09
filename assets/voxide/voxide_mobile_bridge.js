/**
 * Voxide Bridge — Flutter Mobile ↔ Voxide SDK
 *
 * Loaded inside the hidden WebView (assets/voxide/index.html) after
 * voxide.browser.js (which exposes window.Voxide).
 * Initialises VoxideClient, registers semuni-specific capabilities, and
 * exposes window._voxideBridge, which Dart drives over the `VoxideChannel`
 * JavaScript channel.
 *
 * SECURITY: No backend secrets here. All API calls go through the
 * standard semuni REST API using the user's JWT from Dart.
 *
 * CONTRACT: every endpoint and payload below mirrors the current NestJS
 * controllers. The backend is the source of truth: ids come from route and
 * driver discovery, fares are calculated server-side, and the wallet is only
 * ever credited by the backend.
 */
(function () {
  "use strict";

  // ── Constants ──────────────────────────────────────────────────────────
  var PUBLIC_KEY = "vox_pub_e239d8f56f7369eac57ca72b33ea607c20b251282dfe8399";
  var API_PREFIX = "/api/v1";

  // ── State shared with Dart ─────────────────────────────────────────────
  var _accessToken = null;
  var _apiBaseUrl = "";
  var _appState = {};

  // ── Helpers ────────────────────────────────────────────────────────────

  function uuid() {
    if (typeof crypto !== "undefined" && crypto.randomUUID) {
      return crypto.randomUUID();
    }
    return Date.now() + "-" + Math.random().toString(36).slice(2, 11);
  }

  /** Headers for every call: the session plus a correlation id. */
  function buildHeaders(extra) {
    var headers = {
      Accept: "application/json",
      "X-Request-Id": "voxide-" + uuid(),
    };
    if (_accessToken) headers["Authorization"] = "Bearer " + _accessToken;
    return Object.assign(headers, extra || {});
  }

  /**
   * Turns a non-2xx response into an Error carrying the backend's own code and
   * message — the same failure semantics the Flutter client surfaces, so the
   * voice layer never invents a different story about what went wrong.
   */
  function failure(response) {
    return response
      .json()
      .then(function (body) {
        var raw = body && body.message !== undefined ? body.message : body && body.error;
        var message = Array.isArray(raw)
          ? raw.join(", ")
          : typeof raw === "string" && raw
            ? raw
            : "The request failed (HTTP " + response.status + ").";
        var error = new Error(message);
        error.code = body && body.code ? body.code : null;
        error.status = response.status;
        return error;
      })
      .catch(function () {
        var error = new Error("The request failed (HTTP " + response.status + ").");
        error.status = response.status;
        return error;
      });
  }

  function request(method, path, body, idempotencyKey) {
    var options = {
      method: method,
      headers: buildHeaders(
        idempotencyKey ? { "Idempotency-Key": idempotencyKey } : undefined,
      ),
    };
    if (body !== undefined && body !== null) {
      options.headers["Content-Type"] = "application/json";
      options.body = JSON.stringify(body);
    }

    return fetch(_apiBaseUrl + API_PREFIX + path, options).then(function (r) {
      if (!r.ok) {
        return failure(r).then(function (error) {
          throw error;
        });
      }
      return r.json().then(function (payload) {
        // Unwrap the backend's { data, meta } envelope like ApiClient does.
        return payload && payload.data !== undefined ? payload.data : payload;
      });
    });
  }

  function apiGet(path) {
    return request("GET", path);
  }

  function apiPost(path, body, idempotencyKey) {
    return request("POST", path, body, idempotencyKey);
  }

  /**
   * One idempotency key per *logical* operation, reused until that operation
   * succeeds. A retry after a timeout therefore cannot create a second trip,
   * payment, top-up or withdrawal, while a genuinely new request gets a new key.
   */
  var _pendingKeys = {};

  function stableKey(scope, args) {
    var fingerprint = scope + "|" + JSON.stringify(args || {});
    if (!_pendingKeys[fingerprint]) {
      _pendingKeys[fingerprint] = "voxide-" + uuid();
    }
    return { fingerprint: fingerprint, key: _pendingKeys[fingerprint] };
  }

  /**
   * A financial call: sends the key both as a header (the convention the
   * Flutter client uses) and inside the body (the field the backend validates).
   */
  function financialPost(scope, path, args) {
    var stable = stableKey(scope, args);
    var body = Object.assign({}, args, { idempotencyKey: stable.key });
    return apiPost(path, body, stable.key).then(function (data) {
      delete _pendingKeys[stable.fingerprint];
      return data;
    });
  }

  // ── VoxideClient init ─────────────────────────────────────────────────
  var ai = new Voxide.VoxideClient({ publicKey: PUBLIC_KEY });

  // ── Read-only capabilities ────────────────────────────────────────────
  ai.register({
    getWalletBalance: {
      description:
        "Get the current wallet balance for the logged-in user, in santim (minor units).",
      handler: function () {
        return apiGet("/wallet");
      },
    },

    getRecentTransactions: {
      description: "Get the most recent wallet transactions.",
      handler: function () {
        return apiGet("/wallet/transactions");
      },
    },

    getActiveRoutes: {
      description: "Get all transportation routes.",
      handler: function () {
        return apiGet("/routes");
      },
    },

    getCurrentFare: {
      description:
        "Get the official fare for one segment of a route. The backend prices it; never estimate a fare.",
      params: {
        routeId: { type: "string", required: true, description: "Route ID" },
        originStopId: {
          type: "string",
          required: true,
          description: "Boarding RouteStop ID",
        },
        destinationStopId: {
          type: "string",
          required: true,
          description: "Drop-off RouteStop ID",
        },
      },
      handler: function (args) {
        return apiPost("/fares/calculate", {
          routeId: args.routeId,
          originStopId: args.originStopId,
          destinationStopId: args.destinationStopId,
        });
      },
    },

    getMyTrips: {
      description: "Get trip history for the logged-in user.",
      handler: function () {
        return apiGet("/trips");
      },
    },

    getTripDetails: {
      description: "Get detailed information about a specific trip.",
      params: {
        tripId: { type: "string", required: true, description: "Trip ID" },
      },
      handler: function (args) {
        return apiGet("/trips/" + args.tripId);
      },
    },

    getDriverEarnings: {
      description:
        "Get today's and lifetime earnings for the logged-in driver (ETB).",
      handler: function () {
        return apiGet("/drivers/me/earnings");
      },
    },

    getWithdrawalStatus: {
      description:
        "Get the most recent withdrawal request for the logged-in driver, or null if there is none.",
      handler: function () {
        return apiGet("/drivers/me/withdrawals").then(function (list) {
          return list && list.length ? list[0] : null;
        });
      },
    },
  });

  // ── Dangerous (financial) capabilities ────────────────────────────────
  ai.register({
    createTrip: {
      description:
        "Create a trip booking. This spends money from the wallet, so it requires explicit confirmation. Every identifier must come from route and driver discovery — never invent an id or a fare.",
      dangerous: true,
      params: {
        driverId: {
          type: "string",
          required: true,
          description: "Driver user id from GET /drivers/available",
        },
        routeId: {
          type: "string",
          required: true,
          description: "Route ID being travelled",
        },
        originStopId: {
          type: "string",
          required: true,
          description: "Boarding RouteStop ID",
        },
        destinationStopId: {
          type: "string",
          required: true,
          description: "Drop-off RouteStop ID",
        },
        origin: {
          type: "string",
          required: true,
          description: "Boarding stop name",
        },
        destination: {
          type: "string",
          required: true,
          description: "Drop-off stop name",
        },
      },
      handler: function (args) {
        return financialPost("createTrip", "/trips", {
          driverId: args.driverId,
          routeId: args.routeId,
          originStopId: args.originStopId,
          destinationStopId: args.destinationStopId,
          origin: args.origin,
          destination: args.destination,
        });
      },
    },

    payForTrip: {
      description:
        "Pay for an existing trip from the semuni wallet. Requires explicit confirmation; a retry never charges twice.",
      dangerous: true,
      params: {
        tripId: {
          type: "string",
          required: true,
          description: "Trip ID to pay for",
        },
      },
      handler: function (args) {
        return financialPost("payForTrip", "/payments/trip", {
          tripId: args.tripId,
        });
      },
    },

    initiateTopUp: {
      description:
        "Start a wallet top-up. Returns a pending intent and, when the provider hosts checkout, its URL. The wallet is credited only after the backend verifies the payment.",
      dangerous: true,
      params: {
        amount: {
          type: "number",
          required: true,
          description: "Amount in santim (e.g. 1250 = ETB 12.50)",
        },
        provider: {
          type: "string",
          required: false,
          description: "Payment provider",
          enum: ["MOCK", "TELEBIRR", "CHAPA", "BANK"],
        },
      },
      handler: function (args) {
        var body = { amount: args.amount };
        if (args.provider) body.provider = args.provider;
        return financialPost("initiateTopUp", "/wallet/top-up", body);
      },
    },

    requestWithdrawal: {
      description:
        "Request a withdrawal of driver earnings. Accepted as PENDING; the backend re-checks balance and driver status.",
      dangerous: true,
      params: {
        amount: {
          type: "number",
          required: true,
          description: "Amount to withdraw in santim",
        },
        destinationType: {
          type: "string",
          required: true,
          description: "Where the money goes",
          enum: ["BANK", "MOBILE_MONEY"],
        },
        destination: {
          type: "string",
          required: false,
          description: "Bank or mobile-money provider name",
        },
        destinationAccount: {
          type: "string",
          required: false,
          description: "Account number or mobile reference",
        },
      },
      handler: function (args) {
        var body = {
          amount: args.amount,
          destinationType: args.destinationType,
        };
        if (args.destination) body.destination = args.destination;
        if (args.destinationAccount) body.destinationAccount = args.destinationAccount;
        return financialPost("requestWithdrawal", "/drivers/me/withdrawals", body);
      },
    },
  });

  // ── State binding ─────────────────────────────────────────────────────
  ai.bindState(function () {
    return Object.assign(
      { currentPage: window.location.pathname || "/" },
      _appState
    );
  });

  // ── Bridge API exposed to Dart ────────────────────────────────────────
  window._voxideBridge = {
    /** Called by Dart to set the JWT for API calls. */
    setAccessToken: function (token) {
      _accessToken = token || null;
    },

    /** Called by Dart to set the backend API base URL. */
    setApiBaseUrl: function (url) {
      _apiBaseUrl = (url || "").replace(/\/+$/, "");
    },

    /** Called by Dart to update safe application state. */
    updateState: function (stateJson) {
      try {
        _appState = JSON.parse(stateJson);
      } catch (e) {
        console.warn("[VoxideBridge] Invalid state JSON:", e);
      }
    },

    /** Called by Dart to set user identity. */
    setUser: function (userId, email, role) {
      ai.setUser({ userId: userId, email: email, role: role });
    },

    /** Initialize the SDK (call once after setting token/url). */
    init: function () {
      return ai
        .init()
        .then(function () {
          if (window.VoxideChannel) {
            window.VoxideChannel.postMessage(JSON.stringify({ event: "ready" }));
          }
          return true;
        })
        .catch(function (e) {
          console.error("[VoxideBridge] Init failed:", e);
          return false;
        });
    },

    /** Start a voice session. */
    connect: function () {
      return ai.connect();
    },

    /** End the voice session. */
    disconnect: function () {
      ai.disconnect();
    },

    /** Send a text message. */
    sendText: function (text) {
      return ai.sendText(text);
    },

    /** Interrupt agent speech. */
    interrupt: function () {
      ai.interrupt();
    },

    /** Get current status string. */
    getStatus: function () {
      return ai.getSnapshot().status;
    },

    /** Get messages as JSON string for Dart. */
    getMessages: function () {
      return JSON.stringify(ai.getSnapshot().messages);
    },

    /** Subscribe to status changes — pushes state to Dart via VoxideChannel. */
    onStatusChange: function () {
      return ai.subscribe(function () {
        var snap = ai.getSnapshot();
        if (window.VoxideChannel) {
          window.VoxideChannel.postMessage(
            JSON.stringify({
              event: "state_update",
              status: snap.status,
              messages: snap.messages,
            })
          );
        }
      });
    },

    /** Check if initialized. */
    isReady: function () {
      return ai.isInitialized;
    },

    /** Get the underlying client for advanced use. */
    _client: ai,
  };

  console.log("[VoxideBridge] Voxide bridge ready.");
})();
