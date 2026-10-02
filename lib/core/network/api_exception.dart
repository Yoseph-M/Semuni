/// Machine-readable error codes returned by the Semuni backend.
///
/// Flutter branches on these, never on message text. The list mirrors
/// `backend/src/common/error-codes.ts` — a code that appears there and not here
/// is simply treated as a generic failure, so adding one is a client-side
/// improvement rather than a prerequisite.
class ApiErrorCodes {
  const ApiErrorCodes._();

  // Auth
  static const authInvalidCredentials = 'AUTH_INVALID_CREDENTIALS';
  static const authForbidden = 'AUTH_FORBIDDEN';
  static const authUnauthorized = 'AUTH_UNAUTHORIZED';
  static const authUserSuspended = 'AUTH_USER_SUSPENDED';
  static const authUserInactive = 'AUTH_USER_INACTIVE';
  static const authUserPending = 'AUTH_USER_PENDING';

  // Wallet / money
  static const walletInsufficientBalance = 'WALLET_INSUFFICIENT_BALANCE';
  static const walletNotFound = 'WALLET_NOT_FOUND';
  static const walletFrozen = 'WALLET_FROZEN';
  static const currencyMismatch = 'CURRENCY_MISMATCH';

  // Trip / fare
  static const tripNotFound = 'TRIP_NOT_FOUND';
  static const tripNotOwned = 'TRIP_NOT_OWNED';
  static const tripAlreadyPaid = 'TRIP_ALREADY_PAID';
  static const tripNotPayable = 'TRIP_NOT_PAYABLE';
  static const fareMismatch = 'FARE_MISMATCH';

  // Fare / tariff configuration
  static const tariffNotFound = 'TARIFF_NOT_FOUND';
  static const tariffRuleNotFound = 'TARIFF_RULE_NOT_FOUND';
  static const tariffRuleAmbiguous = 'TARIFF_RULE_AMBIGUOUS';
  static const tariffWindowInvalid = 'TARIFF_WINDOW_INVALID';

  // Route / stops — identity is always a backend UUID
  static const routeNotFound = 'ROUTE_NOT_FOUND';
  static const routeInactive = 'ROUTE_INACTIVE';
  static const stopNotFound = 'STOP_NOT_FOUND';
  static const stopOrderInvalid = 'STOP_ORDER_INVALID';

  // Driver / vehicle
  static const driverNotActive = 'DRIVER_NOT_ACTIVE';
  static const driverNotFound = 'DRIVER_NOT_FOUND';
  static const vehicleNotFound = 'VEHICLE_NOT_FOUND';
  static const vehicleNotActive = 'VEHICLE_NOT_ACTIVE';
  static const vehicleNotOwned = 'VEHICLE_NOT_OWNED';
  static const vehicleTypeMismatch = 'VEHICLE_TYPE_MISMATCH';

  // Payments / withdrawals
  static const paymentAlreadyProcessed = 'PAYMENT_ALREADY_PROCESSED';
  static const paymentFailed = 'PAYMENT_FAILED';
  static const paymentNotFound = 'PAYMENT_NOT_FOUND';
  static const withdrawalInsufficientBalance = 'WITHDRAWAL_INSUFFICIENT_BALANCE';
  static const withdrawalNotFound = 'WITHDRAWAL_NOT_FOUND';

  // General
  static const idempotencyConflict = 'IDEMPOTENCY_CONFLICT';
  static const validationError = 'VALIDATION_ERROR';
  static const internalError = 'INTERNAL_ERROR';
}

/// The kind of failure, coarse enough for the UI to decide what to do.
enum ApiErrorKind {
  /// The request never reached the backend (no route, DNS, connection refused).
  network,

  /// The backend did not answer in time.
  timeout,

  /// 400 — the request was rejected as invalid.
  badRequest,

  /// 401 — the session is missing, expired or invalid.
  unauthorized,

  /// 403 — authenticated, but not allowed.
  forbidden,

  /// 404 — no such resource (or one this caller may not see).
  notFound,

  /// 409 — a business conflict: already paid, key reused, ambiguous tariff.
  conflict,

  /// 429 — throttled.
  rateLimited,

  /// 5xx — the backend failed.
  server,

  /// Anything else, including malformed responses.
  unexpected,
}

/// Every failure the API layer surfaces, in a shape the UI can act on.
///
/// Deliberately not a `String`: the message shown to a user comes from
/// [userMessage], which never contains a stack trace, a URL or a raw status
/// code. Screens that need to branch use [code] or [kind].
class ApiException implements Exception {
  const ApiException({
    required this.kind,
    required this.message,
    this.statusCode,
    this.code,
    this.requestId,
    this.cause,
  });

  /// Wraps a backend error body: `{ code, message, requestId? }`.
  factory ApiException.fromResponse({
    required int statusCode,
    required String message,
    String? code,
    String? requestId,
  }) {
    return ApiException(
      kind: _kindForStatus(statusCode),
      message: message,
      statusCode: statusCode,
      code: code,
      requestId: requestId,
    );
  }

  /// The connection failed before any response arrived.
  factory ApiException.network(Object cause) {
    return ApiException(
      kind: ApiErrorKind.network,
      message: 'Could not reach the Semuni backend.',
      cause: cause,
    );
  }

  factory ApiException.timeout(Duration timeout) {
    return ApiException(
      kind: ApiErrorKind.timeout,
      message: 'The request timed out after ${timeout.inSeconds}s.',
    );
  }

  final ApiErrorKind kind;

  /// Developer-facing description; prefer [userMessage] for anything a person
  /// will read.
  final String message;

  final int? statusCode;

  /// Backend `ErrorCode`, when the response carried one.
  final String? code;

  /// Correlation id the backend logged this failure under.
  final String? requestId;

  final Object? cause;

  /// The session is gone: the app must sign in again rather than retry.
  bool get isAuthExpired => kind == ApiErrorKind.unauthorized;

  /// Worth retrying with the same idempotency key: nothing about the request
  /// was wrong, the attempt just did not land.
  bool get isRetryable =>
      kind == ApiErrorKind.network ||
      kind == ApiErrorKind.timeout ||
      kind == ApiErrorKind.server ||
      kind == ApiErrorKind.rateLimited;

  /// A message that is safe and useful to show a passenger or driver.
  String get userMessage {
    final known = _messagesByCode[code];
    if (known != null) return known;

    switch (kind) {
      case ApiErrorKind.network:
        return 'No connection to Semuni. Check your network and try again.';
      case ApiErrorKind.timeout:
        return 'Semuni took too long to respond. Please try again.';
      case ApiErrorKind.unauthorized:
        return 'Your session has expired. Please sign in again.';
      case ApiErrorKind.forbidden:
        return 'You are not allowed to do that.';
      case ApiErrorKind.rateLimited:
        return 'Too many attempts. Please wait a moment and try again.';
      case ApiErrorKind.server:
        return 'Semuni is having trouble right now. Please try again shortly.';
      case ApiErrorKind.notFound:
      case ApiErrorKind.badRequest:
      case ApiErrorKind.conflict:
      case ApiErrorKind.unexpected:
        return message;
    }
  }

  @override
  String toString() {
    final parts = <String>[
      'ApiException(${kind.name}',
      if (statusCode != null) 'HTTP $statusCode',
      ?code,
      if (requestId != null) 'requestId: $requestId',
      ')',
    ];
    return '$message ${parts.join(' ')}';
  }

  static ApiErrorKind _kindForStatus(int statusCode) {
    switch (statusCode) {
      case 400:
        return ApiErrorKind.badRequest;
      case 401:
        return ApiErrorKind.unauthorized;
      case 403:
        return ApiErrorKind.forbidden;
      case 404:
        return ApiErrorKind.notFound;
      case 409:
        return ApiErrorKind.conflict;
      case 429:
        return ApiErrorKind.rateLimited;
      default:
        return statusCode >= 500
            ? ApiErrorKind.server
            : ApiErrorKind.unexpected;
    }
  }

  /// Only codes whose meaning a user can act on get a bespoke sentence; the
  /// rest fall back to the backend's own message, which is already written for
  /// humans.
  static const Map<String, String> _messagesByCode = {
    ApiErrorCodes.authInvalidCredentials: 'Incorrect username or password.',
    ApiErrorCodes.authUserSuspended:
        'This account is suspended. Contact Semuni support.',
    ApiErrorCodes.authUserPending: 'This account is not active yet.',
    ApiErrorCodes.walletInsufficientBalance:
        'Your wallet balance is too low for this payment. Top up and try again.',
    ApiErrorCodes.withdrawalInsufficientBalance:
        'Your wallet balance is too low for this withdrawal.',
    ApiErrorCodes.walletFrozen:
        'This wallet is frozen. Contact Semuni support.',
    ApiErrorCodes.tripAlreadyPaid: 'This trip has already been paid for.',
    ApiErrorCodes.tripNotPayable: 'This trip can no longer be paid.',
    ApiErrorCodes.paymentAlreadyProcessed:
        'A payment for this trip is already being processed.',
    ApiErrorCodes.idempotencyConflict:
        'This request was already sent with different details. Start a new request.',
    ApiErrorCodes.routeInactive: 'This route is not operating right now.',
    ApiErrorCodes.stopOrderInvalid:
        'Choose a boarding stop before the drop-off stop.',
    ApiErrorCodes.tariffRuleNotFound:
        'No official fare is published for this journey yet.',
    ApiErrorCodes.tariffRuleAmbiguous:
        'The fare for this journey is ambiguous. Please contact Semuni support.',
    ApiErrorCodes.driverNotActive: 'This driver is not active.',
    ApiErrorCodes.vehicleNotActive: 'This vehicle is not available right now.',
    ApiErrorCodes.vehicleTypeMismatch:
        'This vehicle does not serve the selected fare.',
    ApiErrorCodes.fareMismatch:
        'The fare changed. Please review the new price and try again.',
    ApiErrorCodes.validationError:
        'Some of the details you entered are not valid.',
  };
}
