import 'package:flutter/material.dart';

import '../navigation/app_router.dart';
import '../navigation/app_routes.dart';
import '../repositories/auth_repository.dart';
import '../repositories/driver_dashboard_repository.dart';
import '../repositories/driver_route_repository.dart';
import '../repositories/trip_repository.dart';
import 'theme/app_theme.dart';

/// SMUNI application root widget.
///
/// Wires together:
/// - The SMUNI Material 3 theme
/// - The centralized app router
/// - The repositories (dependency injection)
///
/// Does NOT contain any business logic or UI components directly.
class SmuniApp extends StatefulWidget {
  const SmuniApp({super.key});

  @override
  State<SmuniApp> createState() => _SmuniAppState();
}

class _SmuniAppState extends State<SmuniApp> {
  // Instantiated here so they live for the lifetime of the application.
  // When a proper DI container or state management package is introduced
  // (e.g., Riverpod), this will be replaced by a provider/container setup.
  late final AuthRepository _authRepository;
  late final TripRepository _tripRepository;
  late final DriverDashboardRepository _driverDashboardRepository;
  late final DriverRouteRepository _driverRouteRepository;
  late final AppRouter _router;

  @override
  void initState() {
    super.initState();
    _authRepository = AuthRepository();
    _tripRepository = TripRepository();
    _driverDashboardRepository = DriverDashboardRepository();
    _driverRouteRepository = DriverRouteRepository();
    _router = AppRouter(
      authRepository: _authRepository,
      tripRepository: _tripRepository,
      driverDashboardRepository: _driverDashboardRepository,
      driverRouteRepository: _driverRouteRepository,
    );
  }

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      title: 'SMUNI',
      debugShowCheckedModeBanner: false,
      theme: AppTheme.light,
      initialRoute: AppRoutes.login,
      onGenerateRoute: _router.onGenerateRoute,
    );
  }
}
