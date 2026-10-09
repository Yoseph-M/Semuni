import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import 'app/app.dart';
import 'core/auth/auth_session.dart';

import 'features/voice/voice_assistant_widget.dart';

/// semuni application entry point.
///
/// Keeps this file minimal — all configuration lives in [SmuniApp].
void main() {
  WidgetsFlutterBinding.ensureInitialized();

  // Lock the app to portrait orientation.
  // Most mobile transportation/wallet apps work best in portrait.
  SystemChrome.setPreferredOrientations([
    DeviceOrientation.portraitUp,
    DeviceOrientation.portraitDown,
  ]);

  runApp(
    SmuniApp(
      // Supplying the session opts the app into startup restoration: a user who
      // signed in previously is taken straight to their home screen, and an
      // expired session goes to sign-in. Without it the app starts at login.
      authSession: AuthSession(),
      voiceAssistantBuilder: (session, currentRoute) =>
          VoiceAssistantWidget(session: session, currentRoute: currentRoute),
    ),
  );
}
