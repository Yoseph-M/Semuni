/// Centralized route name constants for the semuni application.
///
/// All named routes are defined here.
/// Never use string literals for route names inside widgets.
abstract final class AppRoutes {
  // ---------------------------------------------------------------------------
  // Auth
  // ---------------------------------------------------------------------------

  /// Combined passenger/driver login screen (the initial route).
  static const String login = '/login';

  // ---------------------------------------------------------------------------
  // Passenger
  // ---------------------------------------------------------------------------

  static const String passengerHome = '/passenger/home';
  static const String passengerMap = '/passenger/map';
  static const String passengerWallet = '/passenger/wallet';

  static const String passengerTripHistory = '/passenger/trip-history';
  static const String passengerTripDetail = '/passenger/trip-detail';
  static const String passengerNotifications = '/passenger/notifications';
  static const String passengerSettings = '/passenger/settings';
  static const String passengerPayment = '/passenger/payment';

  // ---------------------------------------------------------------------------
  // Driver
  // ---------------------------------------------------------------------------

  static const String driverHome = '/driver/home';
  static const String driverRoutes = '/driver/routes';
  static const String driverTransactions = '/driver/transactions';
  static const String driverWithdraw = '/driver/withdraw';
  static const String driverNotifications = '/driver/notifications';
  static const String driverSettings = '/driver/settings';
}
