import 'package:flutter/material.dart';

import '../core/widgets/placeholder_screen.dart';
import '../features/auth/screens/login_screen.dart';
import '../features/driver/screens/driver_home_screen.dart';
import '../features/driver/screens/driver_routes_screen.dart';
import '../features/passenger/screens/passenger_home_screen.dart';
import '../repositories/auth_repository.dart';
import '../repositories/driver_dashboard_repository.dart';
import '../repositories/driver_route_repository.dart';
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
  });

  final AuthRepository authRepository;
  final TripRepository? tripRepository;
  final DriverDashboardRepository? driverDashboardRepository;
  final DriverRouteRepository? driverRouteRepository;

  TripRepository get _effectiveTripRepository =>
      tripRepository ?? TripRepository();

  DriverDashboardRepository get _effectiveDriverDashboardRepository =>
      driverDashboardRepository ?? DriverDashboardRepository();

  DriverRouteRepository get _effectiveDriverRouteRepository =>
      driverRouteRepository ?? DriverRouteRepository();

  /// Generates the route for a given [RouteSettings].
  ///
  /// Called by [MaterialApp.onGenerateRoute].
  Route<dynamic>? onGenerateRoute(RouteSettings settings) {
    return MaterialPageRoute<void>(
      settings: settings,
      builder: (context) => _buildScreen(settings.name),
    );
  }

  Widget _buildScreen(String? routeName) {
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
      AppRoutes.passengerMap => const PlaceholderScreen(
        title: 'Map',
        icon: Icons.map_rounded,
        description: 'Discover taxi stations and routes near you.\nComing in a future phase.',
      ),
      AppRoutes.passengerWallet => const PlaceholderScreen(
        title: 'Wallet',
        icon: Icons.account_balance_wallet_rounded,
        description: 'View your wallet, top up, and manage payments.',
      ),
      AppRoutes.passengerBookRide => const PlaceholderScreen(
        title: 'Book Ride',
        icon: Icons.directions_car_rounded,
        description: 'Book a taxi ride to your destination.',
      ),
      AppRoutes.passengerRecentTrips => const PlaceholderScreen(
        title: 'Recent Trips',
        icon: Icons.history_rounded,
        description: 'View your past trips and payment history.',
      ),
      AppRoutes.passengerNotifications => const PlaceholderScreen(
        title: 'Notifications',
        icon: Icons.notifications_rounded,
        description: 'Stay updated with your latest activity.',
      ),
      AppRoutes.passengerSettings => const PlaceholderScreen(
        title: 'Settings',
        icon: Icons.settings_rounded,
        description: 'Manage your account and preferences.',
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
      AppRoutes.driverTransactions => const PlaceholderScreen(
        title: 'Transactions',
        icon: Icons.receipt_long_rounded,
        description: 'View your complete transaction history.',
      ),
      AppRoutes.driverWithdraw => const PlaceholderScreen(
        title: 'Withdraw',
        icon: Icons.account_balance_rounded,
        description: 'Withdraw your available earnings to your bank account.',
      ),
      AppRoutes.driverNotifications => const PlaceholderScreen(
        title: 'Notifications',
        icon: Icons.notifications_rounded,
        description: 'Stay updated with payments and route updates.',
      ),
      AppRoutes.driverSettings => const PlaceholderScreen(
        title: 'Settings',
        icon: Icons.settings_rounded,
        description: 'Manage your driver account and preferences.',
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
