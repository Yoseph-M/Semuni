import 'package:flutter/material.dart';

import '../core/auth/auth_session.dart';
import '../core/network/api_client.dart';
import '../navigation/app_router.dart';
import '../navigation/app_routes.dart';
import '../repositories/auth_repository.dart';
import '../repositories/driver_dashboard_repository.dart';
import '../repositories/driver_discovery_repository.dart';
import '../repositories/driver_route_repository.dart';
import '../repositories/passenger_route_repository.dart';
import '../repositories/passenger_wallet_repository.dart';
import '../repositories/payment_repository.dart';
import '../repositories/trip_repository.dart';
import '../services/api/api_driver_dashboard_service.dart';
import '../services/api/api_driver_discovery_service.dart';
import '../services/api/api_driver_route_service.dart';
import '../services/api/api_passenger_route_service.dart';
import '../services/api/api_passenger_wallet_service.dart';
import '../services/api/api_trip_service.dart';
import '../services/api/payment_service.dart';
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
  late final PassengerWalletRepository _passengerWalletRepository;
  late final PaymentRepository _paymentRepository;
  late final DriverDiscoveryRepository _driverDiscoveryRepository;
  late final AppRouter _router;

  @override
  void initState() {
    super.initState();

    // One session/client pair is shared by every repository.
    _session = AuthSession();
    _apiClient = ApiClient(session: _session);
    _authRepository = AuthRepository(session: _session);

    _tripRepository = TripRepository(
      tripService: ApiTripService(client: _apiClient),
    );
    _driverDashboardRepository = DriverDashboardRepository(
      service: ApiDriverDashboardService(client: _apiClient),
    );
    _driverRouteRepository = DriverRouteRepository(
      service: ApiDriverRouteService(client: _apiClient),
    );
    _passengerRouteRepository = PassengerRouteRepository(
      service: ApiPassengerRouteService(client: _apiClient),
    );
    _passengerWalletRepository = PassengerWalletRepository(
      service: ApiPassengerWalletService(client: _apiClient),
      authRepository: _authRepository,
    );
    _paymentRepository = PaymentRepository(
      service: ApiPaymentService(client: _apiClient),
    );
    _driverDiscoveryRepository = DriverDiscoveryRepository(
      service: ApiDriverDiscoveryService(client: _apiClient),
    );

    _router = AppRouter(
      authRepository: _authRepository,
      tripRepository: _tripRepository,
      driverDashboardRepository: _driverDashboardRepository,
      driverRouteRepository: _driverRouteRepository,
      passengerRouteRepository: _passengerRouteRepository,
      passengerWalletRepository: _passengerWalletRepository,
      paymentRepository: _paymentRepository,
      driverDiscoveryRepository: _driverDiscoveryRepository,
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
