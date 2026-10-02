import 'package:flutter/material.dart';

import '../core/widgets/placeholder_screen.dart';
import '../features/auth/screens/login_screen.dart';
import '../features/driver/screens/driver_home_screen.dart';
import '../features/driver/screens/driver_routes_screen.dart';
import '../features/driver/screens/driver_settings_screen.dart';
import '../features/driver/screens/driver_transactions_screen.dart';
import '../features/driver/screens/driver_withdraw_screen.dart';

import '../features/passenger/screens/passenger_home_screen.dart';
import '../features/passenger/screens/passenger_map_screen.dart';
import '../features/passenger/screens/passenger_payment_screen.dart';
import '../features/passenger/screens/passenger_settings_screen.dart';
import '../features/passenger/screens/passenger_trip_detail_screen.dart';
import '../features/passenger/screens/passenger_trip_history_screen.dart';
import '../features/passenger/screens/passenger_wallet_screen.dart';
import '../repositories/auth_repository.dart';
import '../models/passenger_route.dart';
import '../models/trip.dart';
import '../repositories/driver_dashboard_repository.dart';
import '../repositories/driver_route_repository.dart';
import '../repositories/passenger_route_repository.dart';
import '../repositories/passenger_wallet_repository.dart';
import '../repositories/trip_repository.dart';
import 'app_routes.dart';

/// SMUNI application router.
///
/// Maps named routes to screen widgets.
/// All route names are defined in [AppRoutes].
///
/// Architecture note:
/// - [AuthRepository], [TripRepository], [DriverDashboardRepository], and
///   [DriverRouteRepository] are passed as dependencies so screens can access
///   repositories without relying on global state.
/// - When state management is introduced (e.g., Riverpod/Bloc), the
///   repository injection approach here will be easy to adapt.
class AppRouter {
  const AppRouter({
    required this.authRepository,
    this.tripRepository,
    this.driverDashboardRepository,
    this.driverRouteRepository,
    this.passengerRouteRepository,
    this.passengerWalletRepository,
  });

  final AuthRepository authRepository;
  final TripRepository? tripRepository;
  final DriverDashboardRepository? driverDashboardRepository;
  final DriverRouteRepository? driverRouteRepository;
  final PassengerRouteRepository? passengerRouteRepository;
  final PassengerWalletRepository? passengerWalletRepository;

  TripRepository get _effectiveTripRepository =>
      tripRepository ?? TripRepository();

  DriverDashboardRepository get _effectiveDriverDashboardRepository =>
      driverDashboardRepository ?? DriverDashboardRepository();

  DriverRouteRepository get _effectiveDriverRouteRepository =>
      driverRouteRepository ?? DriverRouteRepository();

  PassengerRouteRepository get _effectivePassengerRouteRepository =>
      passengerRouteRepository ?? PassengerRouteRepository();

  PassengerWalletRepository get _effectivePassengerWalletRepository =>
      passengerWalletRepository ??
      PassengerWalletRepository(authRepository: authRepository);

  /// Generates the route for a given [RouteSettings].
  ///
  /// Called by [MaterialApp.onGenerateRoute].
  Route<dynamic>? onGenerateRoute(RouteSettings settings) {
    return MaterialPageRoute<void>(
      settings: settings,
      builder: (context) => _buildScreen(settings.name, settings.arguments),
    );
  }

  Widget _buildScreen(String? routeName, [Object? arguments]) {
    return switch (routeName) {
      // -----------------------------------------------------------------------
      // Auth
      // -----------------------------------------------------------------------
      AppRoutes.login => LoginScreen(authRepository: authRepository),

      // -----------------------------------------------------------------------
      // Passenger
      // -----------------------------------------------------------------------
      AppRoutes.passengerHome => PassengerHomeScreen(
        authRepository: authRepository,
        tripRepository: _effectiveTripRepository,
      ),
      AppRoutes.passengerMap => PassengerMapScreen(
        passengerRouteRepository: _effectivePassengerRouteRepository,
      ),
      AppRoutes.passengerWallet => PassengerWalletScreen(
        authRepository: authRepository,
        walletRepository: _effectivePassengerWalletRepository,
      ),
      AppRoutes.passengerPayment => () {
        final route = arguments is PassengerRoute ? arguments : null;

        if (route == null) {
          return const PlaceholderScreen(
            title: 'Payment',
            icon: Icons.payments_outlined,
            description: 'No route selected for payment.',
          );
        }
        return PassengerPaymentScreen(
          route: route,
          authRepository: authRepository,
          walletRepository: _effectivePassengerWalletRepository,
          tripRepository: _effectiveTripRepository,
        );
      }(),
      AppRoutes.passengerTripHistory => PassengerTripHistoryScreen(
        tripRepository: _effectiveTripRepository,
      ),
      AppRoutes.passengerTripDetail => () {
        final trip = arguments is Trip ? arguments : null;
        if (trip == null) {
          return const PlaceholderScreen(
            title: 'Trip Detail',
            icon: Icons.directions_car_rounded,
            description: 'No trip found.',
          );
        }
        return PassengerTripDetailScreen(trip: trip);
      }(),
      AppRoutes.passengerNotifications => const PlaceholderScreen(
        title: 'Notifications',
        icon: Icons.notifications_rounded,
        description: 'Stay updated with your latest activity.',
      ),
      AppRoutes.passengerSettings => PassengerSettingsScreen(
        authRepository: authRepository,
      ),

      // -----------------------------------------------------------------------
      // Driver
      // -----------------------------------------------------------------------
      AppRoutes.driverHome => DriverHomeScreen(
        authRepository: authRepository,
        dashboardRepository: _effectiveDriverDashboardRepository,
      ),
      AppRoutes.driverRoutes => DriverRoutesScreen(
        authRepository: authRepository,
        routeRepository: _effectiveDriverRouteRepository,
      ),
      AppRoutes.driverTransactions => DriverTransactionsScreen(
        repository: _effectiveDriverDashboardRepository,
      ),
      AppRoutes.driverWithdraw => DriverWithdrawScreen(
        authRepository: authRepository,
        dashboardRepository: _effectiveDriverDashboardRepository,
      ),
      AppRoutes.driverNotifications => const PlaceholderScreen(
        title: 'Notifications',
        icon: Icons.notifications_rounded,
        description: 'Stay updated with payments and route updates.',
      ),
      AppRoutes.driverSettings => DriverSettingsScreen(
        authRepository: authRepository,
      ),

      // -----------------------------------------------------------------------
      // Unknown route
      // -----------------------------------------------------------------------
      _ => const PlaceholderScreen(
        title: 'Page Not Found',
        icon: Icons.error_outline_rounded,
        description: 'The page you are looking for does not exist.',
      ),
    };
  }
}
