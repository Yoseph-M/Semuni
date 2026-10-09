import 'dart:js_interop';
import 'dart:js_interop_unsafe';

import 'package:flutter/material.dart';

/// Web layer for the Voxide Voice AI SDK.
///
/// Communicates with the JavaScript `window._voxideBridge` object that is
/// initialised by `voxide_bridge.js` in index.html.
class VoxideService {
  VoxideService._();
  static final VoxideService instance = VoxideService._();

  bool _initialized = false;

  /// Whether the Voxide bridge is available.
  bool get isAvailable => _hasBridge;

  /// Returns the hidden WebView widget (mobile only, empty on web)
  Widget getWebViewWidget() => const SizedBox.shrink();

  // ── Lifecycle ──────────────────────────────────────────────────────────

  void setAccessToken(String? token) {
    if (!isAvailable) return;
    _callVoid('setAccessToken', (token ?? '').toJS);
  }

  void setApiBaseUrl(String url) {
    if (!isAvailable) return;
    _callVoid('setApiBaseUrl', url.toJS);
  }

  void updateState(String stateJson) {
    if (!isAvailable) return;
    _callVoid('updateState', stateJson.toJS);
  }

  void setUser({String? userId, String? email, String? role}) {
    if (!isAvailable) return;
    final bridge = _getBridge();
    if (bridge == null) return;
    final fn = bridge.getProperty('setUser'.toJS) as JSFunction?;
    if (fn == null) return;
    fn.callAsFunction(
      bridge,
      (userId ?? '').toJS,
      (email ?? '').toJS,
      (role ?? '').toJS,
    );
  }

  Future<bool> init() async {
    if (!isAvailable) return false;
    if (_initialized) return true;

    try {
      final bridge = _getBridge();
      if (bridge == null) return false;
      final fn = bridge.getProperty('init'.toJS) as JSFunction?;
      if (fn == null) return false;
      final promise = fn.callAsFunction(bridge) as JSPromise<JSAny?>?;
      if (promise == null) return false;
      final result = await promise.toDart;
      _initialized = result != null && (result as JSBoolean).toDart;
      return _initialized;
    } catch (e) {
      debugPrint('[VoxideService] init failed: $e');
      return false;
    }
  }

  Future<void> connect() async {
    if (!isAvailable || !_initialized) return;
    try {
      final bridge = _getBridge();
      if (bridge == null) return;
      final fn = bridge.getProperty('connect'.toJS) as JSFunction?;
      if (fn == null) return;
      final result = fn.callAsFunction(bridge);
      if (result != null && result.isA<JSPromise>()) {
        await (result as JSPromise<JSAny?>).toDart;
      }
    } catch (e) {
      debugPrint('[VoxideService] connect failed: $e');
    }
  }

  void disconnect() {
    if (!isAvailable) return;
    _callVoid('disconnect', null);
  }

  Future<void> sendText(String text) async {
    if (!isAvailable || !_initialized) return;
    try {
      final bridge = _getBridge();
      if (bridge == null) return;
      final fn = bridge.getProperty('sendText'.toJS) as JSFunction?;
      if (fn == null) return;
      final result = fn.callAsFunction(bridge, text.toJS);
      if (result != null && result.isA<JSPromise>()) {
        await (result as JSPromise<JSAny?>).toDart;
      }
    } catch (e) {
      debugPrint('[VoxideService] sendText failed: $e');
    }
  }

  void interrupt() {
    if (!isAvailable) return;
    _callVoid('interrupt', null);
  }

  String getStatus() {
    if (!isAvailable) return 'idle';
    final bridge = _getBridge();
    if (bridge == null) return 'idle';
    final fn = bridge.getProperty('getStatus'.toJS) as JSFunction?;
    if (fn == null) return 'idle';
    final result = fn.callAsFunction(bridge);
    if (result == null) return 'idle';
    return (result as JSString).toDart;
  }

  String getMessages() {
    if (!isAvailable) return '[]';
    final bridge = _getBridge();
    if (bridge == null) return '[]';
    final fn = bridge.getProperty('getMessages'.toJS) as JSFunction?;
    if (fn == null) return '[]';
    final result = fn.callAsFunction(bridge);
    if (result == null) return '[]';
    return (result as JSString).toDart;
  }

  bool get isReady {
    if (!isAvailable) return false;
    final bridge = _getBridge();
    if (bridge == null) return false;
    final fn = bridge.getProperty('isReady'.toJS) as JSFunction?;
    if (fn == null) return false;
    final result = fn.callAsFunction(bridge);
    if (result == null) return false;
    return (result as JSBoolean).toDart;
  }

  // ── JS interop helpers ─────────────────────────────────────────────────

  bool get _hasBridge {
    return _getBridge() != null;
  }

  JSObject? _getBridge() {
    final prop = globalContext.getProperty('_voxideBridge'.toJS);
    if (prop == null || prop.isUndefinedOrNull) return null;
    return prop as JSObject;
  }

  void _callVoid(String method, JSAny? arg) {
    final bridge = _getBridge();
    if (bridge == null) return;
    final fn = bridge.getProperty(method.toJS) as JSFunction?;
    if (fn == null) return;
    if (arg != null) {
      fn.callAsFunction(bridge, arg);
    } else {
      fn.callAsFunction(bridge);
    }
  }
}
