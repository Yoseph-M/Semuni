import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import 'app/app.dart';

/// SMUNI application entry point.
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

  runApp(const SmuniApp());
}
