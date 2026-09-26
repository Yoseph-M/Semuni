import 'package:flutter/material.dart';

import '../../../core/widgets/placeholder_screen.dart';
import '../../../navigation/app_routes.dart';
import '../../../repositories/auth_repository.dart';

/// Temporary driver home placeholder (Phase 1-4 only).
///
/// Phase 5 will replace this with the full driver dashboard.
class TempDriverHomeScreen extends StatelessWidget {
  const TempDriverHomeScreen({super.key, required this.authRepository});

  final AuthRepository authRepository;

  @override
  Widget build(BuildContext context) {
    final driver = authRepository.currentDriver;
    return Scaffold(
      appBar: AppBar(
        title: Text('Welcome, ${driver?.firstName ?? 'Driver'}'),
        actions: [
          IconButton(
            icon: const Icon(Icons.logout_rounded),
            onPressed: () async {
              await authRepository.logout();
              if (context.mounted) {
                Navigator.of(context).pushReplacementNamed(AppRoutes.login);
              }
            },
          ),
        ],
      ),
      body: const Center(
        child: PlaceholderScreen(
          title: 'Driver Dashboard',
          icon: Icons.drive_eta_rounded,
          description: 'Phase 5 will build the full driver home screen.\nLogin is working correctly.',
        ),
      ),
    );
  }
}
