import 'dart:async';
import 'dart:convert';

import 'package:http/http.dart' as http;

import '../auth/auth_session.dart';
import 'api_config.dart';
import 'api_exception.dart';

/// A decoded backend envelope: `{ "data": ..., "meta": {...} }`.
///
/// The backend always answers in this shape; unwrapping it here means feature
/// services deal with the domain object, not with envelope bookkeeping.
class ApiResult {
  const ApiResult({required this.data, this.meta = const {}});

  final dynamic data;
  final Map<String, dynamic> meta;

  /// The payload as a map, or an empty map when the endpoint returned nothing.
  Map<String, dynamic> get asMap =>
      data is Map<String, dynamic> ? data as Map<String, dynamic> : const {};

  /// The payload as a list, or an empty list when the endpoint returned nothing.
  List<dynamic> get asList => data is List ? data as List : const [];

  /// Convenience for endpoints whose payload is a list of objects.
  List<Map<String, dynamic>> get asMapList => asList
      .whereType<Map<String, dynamic>>()
      .toList(growable: false);
}

/// The only place in the app that speaks HTTP.
///
/// Responsibilities, in one place so no feature has to remember them:
///
///   * base URL and API prefix from [ApiConfig]
///   * `Authorization: Bearer …` from the shared [AuthSession]
///   * JSON encode/decode and envelope unwrapping
///   * `X-Request-Id` per request, so a failure can be matched to a backend log
///   * timeouts, mapped to a retryable [ApiException]
///   * backend `{ code, message }` errors mapped to [ApiException]
///   * a 401 that clears the session and notifies the app
///
/// Feature services call [get]/[post]/[patch]/[delete] and receive either a
/// decoded result or an [ApiException] — never a raw [http.Response].
class ApiClient {
  ApiClient({
    http.Client? httpClient,
    AuthSession? session,
    String? baseUrl,
    Duration? timeout,
  }) : _http = httpClient ?? http.Client(),
       session = session ?? AuthSession(),
       _baseUrl = baseUrl ?? ApiConfig.baseUrl,
       _timeout = timeout ?? ApiConfig.requestTimeout;

  final http.Client _http;
  final AuthSession session;
  final String _baseUrl;
  final Duration _timeout;

  /// One in-flight refresh at a time. Several requests commonly expire together
  /// (a dashboard fires three calls at once); without this they would each spend
  /// the single-use refresh token, and all but the first would fail.
  Future<bool>? _refreshInFlight;

  static int _requestCounter = 0;

  Uri _uri(String path, Map<String, dynamic>? query) {
    final segment = path.startsWith('/') ? path : '/$path';
    final uri = Uri.parse('$_baseUrl${ApiConfig.apiPrefix}$segment');
    if (query == null || query.isEmpty) return uri;
    final params = <String, String>{
      for (final entry in query.entries)
        if (entry.value != null) entry.key: '${entry.value}',
    };
    return uri.replace(queryParameters: params);
  }

  Map<String, String> _headers({
    required bool authenticated,
    bool hasBody = false,
    String? idempotencyKey,
  }) {
    final headers = <String, String>{
      'Accept': 'application/json',
      'X-Request-Id': _nextRequestId(),
    };
    if (hasBody) headers['Content-Type'] = 'application/json';
    if (idempotencyKey != null) headers['Idempotency-Key'] = idempotencyKey;

    // A missing token on an authenticated call is not sent as an empty header:
    // the backend answers 401, which is the honest outcome.
    final token = session.accessToken;
    if (authenticated && token != null && token.isNotEmpty) {
      headers['Authorization'] = 'Bearer $token';
    }
    return headers;
  }

  static String _nextRequestId() {
    _requestCounter = (_requestCounter + 1) % 1000000;
    final stamp = DateTime.now().microsecondsSinceEpoch.toRadixString(36);
    return 'flutter-$stamp-$_requestCounter';
  }

  Future<ApiResult> get(
    String path, {
    Map<String, dynamic>? query,
    bool authenticated = true,
  }) => _send('GET', path, query: query, authenticated: authenticated);


  Future<ApiResult> post(
    String path, {
    Object? body,
    Map<String, dynamic>? query,
    String? idempotencyKey,
    bool authenticated = true,
  }) => _send(
    'POST',
    path,
    body: body,
    query: query,
    idempotencyKey: idempotencyKey,
    authenticated: authenticated,
  );

  Future<ApiResult> patch(
    String path, {
    Object? body,
    Map<String, dynamic>? query,
    bool authenticated = true,
  }) => _send('PATCH', path, body: body, query: query, authenticated: authenticated);

  Future<ApiResult> delete(
    String path, {
    Map<String, dynamic>? query,
    bool authenticated = true,
  }) => _send('DELETE', path, query: query, authenticated: authenticated);  Future<ApiResult> _send(
    String method,
    String path,{
    Object? body,
    Map<String, dynamic>? query,
    String? idempotencyKey,
    bool authenticated = true,
    bool retryOnUnauthorized = true,
  }) async {
    final uri = _uri(path, query);
    final hasBody = body != null;
    final headers = _headers(
      authenticated: authenticated,
      hasBody: hasBody,
      idempotencyKey: idempotencyKey,
    );
    final encodedBody = hasBody ? json.encode(body) : null;

    late final http.Response response;
    try {
      final future = switch (method) {
        'GET' => _http.get(uri, headers: headers),
        'POST' => _http.post(uri, headers: headers, body: encodedBody),
        'PATCH' => _http.patch(uri, headers: headers, body: encodedBody),
        'DELETE' => _http.delete(uri, headers: headers, body: encodedBody),
        _ => throw ArgumentError('Unsupported method $method'),
      };
      response = await future.timeout(_timeout);
    } on TimeoutException {
      throw ApiException.timeout(_timeout);
    } on ApiException {
      rethrow;
    } on Object catch (error) {
      throw ApiException.network(error);
    }

    final decoded = _decodeBody(response.body);

    if (response.statusCode >= 200 && response.statusCode < 300) {
      return _toResult(decoded);
    }

    final failure = _failureFrom(response.statusCode, decoded);

    // An expired access token is not a dead session: when a refresh token is
    // held, exchange it and replay the request exactly once. Only the refresh
    // call itself is exempt, so a rejected refresh cannot recurse.
    if (authenticated && failure.isAuthExpired && retryOnUnauthorized) {
      final refreshed = await _refreshAccessToken();
      if (refreshed) {
        return _send(
          method,
          path,
          body: body,
          query: query,
          idempotencyKey: idempotencyKey,
          authenticated: authenticated,
          retryOnUnauthorized: false,
        );
      }
    }

    // A dead session must not look alive: clear it and let the app route back
    // to sign-in. When a refresh was attempted, the outcome was already decided
    // inside [_performRefresh] (cleared on rejection, kept on a transient
    // failure). The exception always propagates so the caller can stop.
    if (authenticated && failure.isAuthExpired) {
      if (!retryOnUnauthorized || !session.canRefresh) {
        await session.expire();
      }
    }

    throw failure;
  }

  /// Exchanges the refresh token for a new pair, once for all concurrent
  /// callers. Returns whether the session now holds a fresh access token.
  Future<bool> _refreshAccessToken() {
    if (!session.canRefresh) return Future.value(false);
    return _refreshInFlight ??= _performRefresh().whenComplete(() {
      _refreshInFlight = null;
    });
  }

  Future<bool> _performRefresh() async {
    final refreshToken = session.refreshToken;
    if (refreshToken == null || refreshToken.isEmpty) {
      await session.expire();
      return false;
    }

    try {
      final response = await _send(
        'POST',
        '/auth/refresh',
        body: {'refreshToken': refreshToken},
        authenticated: false,
        retryOnUnauthorized: false,
      );
      final data = response.asMap;
      final accessToken = data['accessToken'] ?? data['access_token'];
      final rotated = data['refreshToken'] ?? data['refresh_token'];

      if (accessToken is! String || accessToken.isEmpty) {
        // A 200 without a token is a protocol failure, not a usable session.
        await session.expire();
        return false;
      }

      await session.updateTokens(
        AuthTokens(
          accessToken: accessToken,
          // The backend rotates on every refresh; keep the current one only if
          // a response ever omits it.
          refreshToken: rotated is String && rotated.isNotEmpty
              ? rotated
              : refreshToken,
        ),
      );
      return true;
    } on ApiException catch (error) {
      // Unreachable backend / server error: the tokens may still be good, so
      // keep them and let the user retry instead of forcing a sign-out.
      if (error.isRetryable) return false;

      // Rejected (spent, revoked, suspended account): the session is over.
      await session.expire();
      return false;
    }
  }

  static dynamic _decodeBody(String body) {
    if (body.isEmpty) return null;
    try {
      return json.decode(body);
    } on FormatException {
      // Not JSON: almost always an HTML error page from a proxy or a wrong
      // base URL. Surfaced as an unexpected failure rather than silently
      // pretending the body was empty.
      return null;
    }
  }

  static ApiResult _toResult(dynamic decoded) {
    if (decoded is Map<String, dynamic>) {
      if (decoded.containsKey('data') || decoded.containsKey('meta')) {
        final meta = decoded['meta'];
        return ApiResult(
          data: decoded['data'],
          meta: meta is Map<String, dynamic> ? meta : const {},
        );
      }
      return ApiResult(data: decoded);
    }
    return ApiResult(data: decoded);
  }

  /// Reads the backend's error envelope: `{ code, message, requestId? }`.
  ///
  /// `message` may be a string or a list (class-validator returns arrays), and
  /// either way it is treated as untrusted display text, never as a branch key.
  static ApiException _failureFrom(int statusCode, dynamic decoded) {
    String? code;
    String? requestId;
    String message = 'The request failed (HTTP $statusCode).';

    if (decoded is Map<String, dynamic>) {
      final rawCode = decoded['code'];
      if (rawCode is String && rawCode.isNotEmpty) code = rawCode;

      final rawRequestId = decoded['requestId'];
      if (rawRequestId is String && rawRequestId.isNotEmpty) {
        requestId = rawRequestId;
      }

      final rawMessage = decoded['message'] ?? decoded['error'];
      if (rawMessage is String && rawMessage.isNotEmpty) {
        message = rawMessage;
      } else if (rawMessage is List && rawMessage.isNotEmpty) {
        message = rawMessage.map((e) => '$e').join(', ');
      }
    }

    return ApiException.fromResponse(
      statusCode: statusCode,
      message: message,
      code: code,
      requestId: requestId,
    );
  }
}
