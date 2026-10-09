import 'dart:convert';

import 'package:flutter/material.dart';
import 'package:webview_flutter/webview_flutter.dart';

/// Mobile layer for the Voxide Voice AI SDK using a hidden WebView.
///
/// Communicates with the JavaScript `window._voxideBridge` object that is
/// initialised by `voxide_mobile_bridge.js` inside the WebView.
class VoxideService {
  VoxideService._() {
    _initController();
  }
  static final VoxideService instance = VoxideService._();

  late final WebViewController _controller;

  bool _isReady = false;
  String _status = 'idle';
  String _messages = '[]';

  // Expose these for the UI
  String getStatus() => _status;
  String getMessages() => _messages;
  bool get isReady => _isReady;

  bool get isAvailable => true; // Always available on mobile via WebView

  /// Returns the hidden WebView widget (mobile only, empty on web)
  Widget getWebViewWidget() => WebViewWidget(controller: _controller);

  void _initController() {
    _controller = WebViewController()
      ..setJavaScriptMode(JavaScriptMode.unrestricted)
      ..addJavaScriptChannel(
        'VoxideChannel',
        onMessageReceived: (JavaScriptMessage message) {
          try {
            final data = jsonDecode(message.message) as Map<String, dynamic>;
            if (data['event'] == 'ready') {
              _isReady = true;
            } else if (data['event'] == 'state_update') {
              _status = data['status'] as String? ?? 'idle';
              if (data['messages'] != null) {
                _messages = jsonEncode(data['messages']);
              }
            }
          } catch (e) {
            debugPrint('[VoxideService] parse error from WebView: $e');
          }
        },
      )
      ..loadFlutterAsset('assets/voxide/index.html').then((_) {
        // Once HTML is loaded, bind the onStatusChange to start pushing state
        Future.delayed(const Duration(milliseconds: 100), () {
          _callVoid('onStatusChange', null);
        });
      });
  }

  // ── Lifecycle ──────────────────────────────────────────────────────────

  void setAccessToken(String? token) {
    _callVoid('setAccessToken', "'${token ?? ''}'");
  }

  void setApiBaseUrl(String url) {
    _callVoid('setApiBaseUrl', "'$url'");
  }

  void updateState(String stateJson) {
    // Stringify the JSON string again so it's a valid JS string literal
    final escaped = jsonEncode(stateJson);
    _callVoid('updateState', escaped);
  }

  void setUser({String? userId, String? email, String? role}) {
    _callVoid(
      'setUser',
      "'${userId ?? ''}', '${email ?? ''}', '${role ?? ''}'",
    );
  }

  Future<bool> init() async {
    try {
      await _controller.runJavaScript('window._voxideBridge.init()');
      // Bridge will postMessage { event: "ready" } when done
      return true;
    } catch (e) {
      debugPrint('[VoxideService] init failed: $e');
      return false;
    }
  }

  Future<void> connect() async {
    try {
      await _controller.runJavaScript('window._voxideBridge.connect()');
    } catch (e) {
      debugPrint('[VoxideService] connect failed: $e');
    }
  }

  void disconnect() {
    _callVoid('disconnect', null);
  }

  Future<void> sendText(String text) async {
    try {
      final escaped = jsonEncode(text);
      await _controller.runJavaScript(
        'window._voxideBridge.sendText($escaped)',
      );
    } catch (e) {
      debugPrint('[VoxideService] sendText failed: $e');
    }
  }

  void interrupt() {
    _callVoid('interrupt', null);
  }

  // ── Helpers ────────────────────────────────────────────────────────────

  void _callVoid(String method, String? args) {
    try {
      final call = args != null
          ? 'window._voxideBridge.$method($args)'
          : 'window._voxideBridge.$method()';
      _controller.runJavaScript(call);
    } catch (e) {
      debugPrint('[VoxideService] _callVoid failed: $e');
    }
  }
}
