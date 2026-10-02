import 'package:flutter/material.dart';

import '../core/auth/auth_session.dart';
import '../core/network/api_client.dart';
import '../navigation/app_router.dart';
import '../navigation/app_routes.dart';
import '../repositories/auth_repository.dart';
import '../repositories/driver_dashboard_repository.dart';
import '../repositories/driver_route_repository.dart';
import '../repositories/passenger_route_repository.dart';
import '../repositories/trip_repository.dart';
import 'theme/app_theme.dart';

class SmuniApp extends StatefulWidget {
  const SmuniApp({super.key});

  @override
  State<SmuniApp> createState() => _SmuniAppState();
}

class _SmuniAppState extends State<SmuniApp> {
  late final AuthSession _session;
  late final ApiClient _apiClient;
  late final AuthRepository _authRepository;
  late final TripRepository _tripRepository;
  late final DriverDashboardRepository _driverDashboardRepository;
  late final DriverRouteRepository _driverRouteRepository;
  late final PassengerRouteRepository _passengerRouteRepository;
  late final AppRouter _router;

  @override
  void initState() {
    super.initState();

    _session = AuthSession();
    _apiClient = ApiClient(session: _session);
    _authRepository = AuthRepository(session: _session);

    _tripRepository = TripRepository(
      tripService: null,
    );
    _driverDashboardRepository = DriverDashboardRepository();
    _driverRouteRepository = DriverRouteRepository();
    _passengerRouteRepository = PassengerRouteRepository();

    _router = AppRouter(
      authRepository: _authRepository,
      tripRepository: _tripRepository,
      driverDashboardRepository: _driverDashboardRepository,
      driverRouteRepository: _driverRouteRepository,
      passengerRouteRepository: _passengerRouteRepository,
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
