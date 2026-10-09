import 'dart:async';
import 'dart:convert';

import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';

import '../../app/theme/app_colors.dart';
import '../../core/auth/auth_session.dart';
import '../../core/network/api_config.dart';
import '../../navigation/app_routes.dart';
import '../../services/voxide_service.dart';

/// Floating voice assistant widget powered by Voxide.
///
/// Renders a microphone FAB that starts/stops voice sessions.
/// Uses a hidden WebView on mobile to run the Voxide JS SDK.
///
/// Mount this ONCE at the root of the widget tree (inside [SmuniApp]),
/// not inside any page that unmounts on navigation.
class VoiceAssistantWidget extends StatefulWidget {
  final AuthSession session;
  final ValueListenable<String?>? currentRoute;

  const VoiceAssistantWidget({
    super.key,
    required this.session,
    this.currentRoute,
  });

  @override
  State<VoiceAssistantWidget> createState() => _VoiceAssistantWidgetState();
}

class _VoiceAssistantWidgetState extends State<VoiceAssistantWidget>
    with SingleTickerProviderStateMixin {
  final _voxide = VoxideService.instance;
  String _status = 'idle';
  bool _isInitialized = false;
  bool _showChat = false;
  final _textController = TextEditingController();
  List<Map<String, dynamic>> _messages = [];
  Timer? _statusPoller;
  late AnimationController _pulseController;
  StreamSubscription<void>? _sessionSub;

  @override
  void initState() {
    super.initState();

    _pulseController = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 1200),
    );

    _initVoxide();
  }

  Future<void> _initVoxide() async {
    if (!_voxide.isAvailable) return;

    // Configure the bridge with backend URL and auth token.
    _voxide.setApiBaseUrl(ApiConfig.baseUrl);
    _syncToken();

    // Listen to session expiry to clear the token.
    _sessionSub = widget.session.onSessionExpired.listen((_) {
      _voxide.setAccessToken(null);
    });

    // Initialize the SDK.
    final success = await _voxide.init();
    if (mounted) {
      setState(() => _isInitialized = success);
    }

    // Poll status changes (simpler than setting up JS→Dart callbacks).
    _statusPoller = Timer.periodic(const Duration(milliseconds: 200), (_) {
      if (!mounted) return;
      _syncToken(); // keep token in sync each tick
      final newStatus = _voxide.getStatus();
      if (newStatus != _status) {
        setState(() => _status = newStatus);
        _updatePulse();
      }
      if (_showChat && newStatus != 'idle') {
        _refreshMessages();
      }
    });
  }

  void _syncToken() {
    _voxide.setAccessToken(widget.session.accessToken);
  }

  void _updatePulse() {
    if (_status == 'listening' || _status == 'connecting') {
      _pulseController.repeat(reverse: true);
    } else {
      _pulseController.stop();
      _pulseController.reset();
    }
  }

  void _refreshMessages() {
    try {
      final json = _voxide.getMessages();
      final list = jsonDecode(json) as List;
      if (mounted) {
        setState(() {
          _messages = list.cast<Map<String, dynamic>>();
        });
      }
    } catch (_) {}
  }

  Future<void> _toggleVoice() async {
    if (!_isInitialized) {
      await _initVoxide();
    }
    if (_status == 'idle' || _status == 'error' || _status == 'armed') {
      await _voxide.connect();
    } else {
      _voxide.disconnect();
    }
  }

  Future<void> _sendText() async {
    final text = _textController.text.trim();
    if (text.isEmpty) return;
    _textController.clear();
    await _voxide.sendText(text);
  }

  void _toggleChat() {
    setState(() => _showChat = !_showChat);
    if (_showChat) _refreshMessages();
  }

  @override
  void dispose() {
    _statusPoller?.cancel();
    _sessionSub?.cancel();
    _textController.dispose();
    _pulseController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final routeListenable = widget.currentRoute;

    Widget buildAssistant({required bool shouldShow}) {
      return Stack(
        children: [
          // Hidden WebView for JS execution (mobile only, no-op on web)
          Offstage(
            offstage: true,
            child: SizedBox(
              width: 1,
              height: 1,
              child: _voxide.getWebViewWidget(),
            ),
          ),
          if (shouldShow) ...[
            // Chat panel
            if (_showChat)
              Positioned(right: 16, bottom: 80, child: _buildChatPanel()),
            // Always show FAB in bottom right corner
            Positioned(right: 16, bottom: 16, child: _buildFab()),
          ],
        ],
      );
    }

    if (routeListenable == null) {
      final isAuth = widget.session.isAuthenticated;
      return buildAssistant(shouldShow: isAuth);
    }

    return ValueListenableBuilder<String?>(
      valueListenable: routeListenable,
      builder: (context, route, _) {
        final isLogin = route == AppRoutes.login;
        final isAuth = widget.session.isAuthenticated;
        return buildAssistant(shouldShow: !isLogin && isAuth);
      },
    );
  }

  Widget _buildFab() {
    final isActive = _status != 'idle' && _status != 'error';
    final color = _statusColor;

    return Column(
      mainAxisSize: MainAxisSize.min,
      children: [
        if (isActive)
          Container(
            margin: const EdgeInsets.only(bottom: 8),
            padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 4),
            decoration: BoxDecoration(
              color: color.withValues(alpha: 0.9),
              borderRadius: BorderRadius.circular(16),
            ),
            child: Text(
              _statusLabel,
              style: const TextStyle(
                color: Colors.white,
                fontSize: 11,
                fontWeight: FontWeight.w600,
              ),
            ),
          ),
        GestureDetector(
          onTap: _toggleVoice,
          onLongPress: _toggleChat,
          child: AnimatedBuilder(
            animation: _pulseController,
            builder: (context, child) {
              final scale = 1.0 + (_pulseController.value * 0.1);
              return Transform.scale(
                scale: isActive ? scale : 1.0,
                child: Container(
                  width: 56,
                  height: 56,
                  decoration: BoxDecoration(
                    shape: BoxShape.circle,
                    color: color,
                    boxShadow: [
                      BoxShadow(
                        color: color.withValues(alpha: 0.35),
                        blurRadius: isActive ? 16 : 8,
                        spreadRadius: isActive ? 2 : 0,
                      ),
                    ],
                  ),
                  child: Icon(_statusIcon, color: Colors.white, size: 24),
                ),
              );
            },
          ),
        ),
      ],
    );
  }

  Widget _buildChatPanel() {
    return Material(
      elevation: 8,
      borderRadius: BorderRadius.circular(16),
      child: Container(
        width: 320,
        height: 420,
        decoration: BoxDecoration(
          color: Theme.of(context).scaffoldBackgroundColor,
          borderRadius: BorderRadius.circular(16),
          border: Border.all(color: AppColors.border),
        ),
        child: Column(
          children: [
            // Header
            Container(
              padding: const EdgeInsets.all(16),
              decoration: const BoxDecoration(
                color: AppColors.primary,
                borderRadius: BorderRadius.vertical(top: Radius.circular(16)),
              ),
              child: Row(
                children: [
                  const Icon(Icons.assistant, color: Colors.white, size: 20),
                  const SizedBox(width: 8),
                  const Expanded(
                    child: Text(
                      'semuni Assistant',
                      style: TextStyle(
                        color: Colors.white,
                        fontWeight: FontWeight.bold,
                        fontSize: 14,
                      ),
                    ),
                  ),
                  GestureDetector(
                    onTap: _toggleChat,
                    child: const Icon(
                      Icons.close,
                      color: Colors.white,
                      size: 20,
                    ),
                  ),
                ],
              ),
            ),
            // Messages
            Expanded(
              child: _messages.isEmpty
                  ? const Center(
                      child: Padding(
                        padding: EdgeInsets.all(24),
                        child: Text(
                          'Tap the mic to start talking,\nor type a message below.',
                          textAlign: TextAlign.center,
                          style: TextStyle(color: Colors.grey),
                        ),
                      ),
                    )
                  : ListView.builder(
                      reverse: true,
                      padding: const EdgeInsets.all(12),
                      itemCount: _messages.length,
                      itemBuilder: (context, index) {
                        final msg = _messages[_messages.length - 1 - index];
                        final isUser = msg['role'] == 'user';
                        return Align(
                          alignment: isUser
                              ? Alignment.centerRight
                              : Alignment.centerLeft,
                          child: Container(
                            margin: const EdgeInsets.only(bottom: 8),
                            padding: const EdgeInsets.symmetric(
                              horizontal: 12,
                              vertical: 8,
                            ),
                            constraints: const BoxConstraints(maxWidth: 240),
                            decoration: BoxDecoration(
                              color: isUser
                                  ? AppColors.primary
                                  : Colors.grey.shade200,
                              borderRadius: BorderRadius.circular(12),
                            ),
                            child: Text(
                              msg['text']?.toString() ?? '',
                              style: TextStyle(
                                color: isUser ? Colors.white : Colors.black87,
                                fontSize: 13,
                              ),
                            ),
                          ),
                        );
                      },
                    ),
            ),
            // Text input
            Container(
              padding: const EdgeInsets.all(8),
              decoration: BoxDecoration(
                border: Border(top: BorderSide(color: AppColors.border)),
              ),
              child: Row(
                children: [
                  Expanded(
                    child: TextField(
                      controller: _textController,
                      decoration: const InputDecoration(
                        hintText: 'Type a message...',
                        border: InputBorder.none,
                        contentPadding: EdgeInsets.symmetric(horizontal: 12),
                        isDense: true,
                      ),
                      style: const TextStyle(fontSize: 13),
                      onSubmitted: (_) => _sendText(),
                    ),
                  ),
                  IconButton(
                    icon: const Icon(
                      Icons.send,
                      color: AppColors.primary,
                      size: 20,
                    ),
                    onPressed: _sendText,
                  ),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }

  Color get _statusColor {
    switch (_status) {
      case 'connecting':
        return AppColors.warning;
      case 'listening':
        return AppColors.primaryLight;
      case 'thinking':
      case 'executing':
        return AppColors.primaryDark;
      case 'speaking':
        return AppColors.primary;
      case 'armed':
        return AppColors.primaryLight;
      case 'error':
        return AppColors.error;
      default:
        return AppColors.primary;
    }
  }

  String get _statusLabel {
    switch (_status) {
      case 'connecting':
        return 'Connecting...';
      case 'listening':
        return 'Listening';
      case 'thinking':
        return 'Thinking...';
      case 'speaking':
        return 'Speaking';
      case 'executing':
        return 'Working...';
      case 'armed':
        return 'Ready';
      default:
        return '';
    }
  }

  IconData get _statusIcon {
    switch (_status) {
      case 'listening':
        return Icons.mic;
      case 'thinking':
      case 'executing':
        return Icons.hourglass_top;
      case 'speaking':
        return Icons.volume_up;
      case 'error':
        return Icons.mic_off;
      default:
        return Icons.mic_none;
    }
  }
}
