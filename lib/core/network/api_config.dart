import 'package:flutter/foundation.dart';

/// Where the Flutter client finds the NestJS backend.
///
/// The base URL is configuration, never a literal inside a feature: every
/// request goes through [ApiClient], which reads it from here.
///
/// Override at build/run time:
///
///   flutter run --dart-define=SMUNI_API_BASE=http://192.168.1.20:3000
///
/// The defaults differ per platform because "localhost" means different things:
///
///   * Android emulator — `10.0.2.2` is the host machine as seen from inside
///     the emulator; `127.0.0.1` would be the emulator itself.
///   * iOS simulator, desktop and web — `127.0.0.1` is the host machine.
///   * Physical device — neither works: pass your machine's LAN address (and
///     make sure the backend listens on `0.0.0.0`, not just loopback).
class ApiConfig {
  const ApiConfig._();

  /// Every backend route lives under this prefix.
  static const String apiPrefix = '/api/v1';

  /// Applied to a single request. Long enough for a slow mobile network, short
  /// enough that a hung call surfaces as a retryable error instead of a spinner
  /// that never resolves.
  static const Duration requestTimeout = Duration(seconds: 15);

  static const String _override = String.fromEnvironment('SMUNI_API_BASE');

  /// The configured backend origin, e.g. `http://10.0.2.2:3000`.
  static String get baseUrl {
    if (_override.isNotEmpty) {
      return _withoutTrailingSlash(_override);
    }
    if (!kIsWeb && defaultTargetPlatform == TargetPlatform.android) {
      return 'http://10.0.2.2:3000';
    }
    return 'http://127.0.0.1:3000';
  }

  /// True when the address came from `--dart-define` rather than a default, so
  /// the UI can say "point this build at your backend" instead of guessing.
  static bool get isExplicitlyConfigured => _override.isNotEmpty;

  static String _withoutTrailingSlash(String value) {
    var result = value.trim();
    while (result.endsWith('/')) {
      result = result.substring(0, result.length - 1);
    }
    return result;
  }
}
