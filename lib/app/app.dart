import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';

import '../core/auth/auth_session.dart';
import '../core/network/api_config.dart';
import '../navigation/app_router.dart';
import '../navigation/app_routes.dart';
import '../navigation/app_route_observer.dart';
import '../repositories/auth_repository.dart';
import '../repositories/driver_dashboard_repository.dart';
import '../repositories/driver_discovery_repository.dart';
import '../repositories/driver_route_repository.dart';
import '../repositories/passenger_route_repository.dart';
import '../repositories/passenger_wallet_repository.dart';
import '../repositories/notification_repository.dart';
import '../repositories/payment_repository.dart';
import '../repositories/trip_repository.dart';
import '../core/network/api_client.dart';
import '../services/api/api_auth_service.dart';
import '../services/api/api_driver_dashboard_service.dart';
import '../services/api/api_driver_discovery_service.dart';
import '../services/api/api_driver_route_service.dart';
import '../services/api/api_passenger_route_service.dart';
import '../services/api/api_passenger_wallet_service.dart';
import '../services/api/api_trip_service.dart';
import '../services/api/api_notification_service.dart';
import '../services/mock/mock_notification_service.dart';
import '../services/mock/mock_driver_notification_service.dart';
import '../services/api/interfaces.dart';
import '../services/api/payment_service.dart';
import 'startup_screen.dart';
import 'theme/app_theme.dart';

/// Service overrides for [SmuniApp].
///
/// Every field is optional and every default is the real API-backed service, so
/// production wiring cannot accidentally run on a fake. Tests supply mocks here:
/// that is the *only* place mocks are selected, which is what keeps the shipped
/// runtime honest while the widget suite stays offline.
class SmuniServices {
  const SmuniServices({
    this.authService,
    this.tripService,
    this.driverDashboardService,
    this.driverRouteService,
    this.passengerRouteService,
    this.passengerWalletService,
    this.paymentService,
    this.driverDiscoveryService,
    this.notificationService,
    this.driverNotificationService,
  });

  final AuthService? authService;
  final TripService? tripService;
  final DriverDashboardService? driverDashboardService;
  final DriverRouteService? driverRouteService;
  final PassengerRouteService? passengerRouteService;
  final PassengerWalletService? passengerWalletService;
  final PaymentService? paymentService;
  final DriverDiscoveryService? driverDiscoveryService;
  final NotificationService? notificationService;
  final NotificationService? driverNotificationService;
}

class SmuniApp extends StatefulWidget {
  final Widget Function(
    AuthSession session,
    ValueListenable<String?>? currentRoute,
  )?
  voiceAssistantBuilder;

  /// The session to restore at startup.
  ///
  /// Production (`main.dart`) passes a real [AuthSession] so a user who signed
  /// in previously lands straight on their home screen, and an expired session
  /// lands on sign-in instead of briefly showing a signed-in screen it cannot
  /// back up. Tests leave it null: they start from the login screen and must
  /// never touch the platform keystore.
  final AuthSession? authSession;

  /// Service overrides. Null in production: the app then wires the real API
  /// services against [authSession].
  final SmuniServices? services;

  const SmuniApp({
    super.key,
    this.voiceAssistantBuilder,
    this.authSession,
    this.services,
  });

  @override
  State<SmuniApp> createState() => _SmuniAppState();
}

class _SmuniAppState extends State<SmuniApp> {
  late final AuthSession _session;
  late final AuthRepository _authRepository;
  late final TripRepository _tripRepository;
  late final DriverDashboardRepository _driverDashboardRepository;
  late final DriverRouteRepository _driverRouteRepository;
  late final PassengerRouteRepository _passengerRouteRepository;
  late final PassengerWalletRepository _passengerWalletRepository;
  late final PaymentRepository _paymentRepository;
  late final DriverDiscoveryRepository _driverDiscoveryRepository;
  late final AppRouter _router;

  /// True until the persisted session has been resolved. While it is set, the
  /// app shows the startup screen rather than guessing — showing sign-in first
  /// and jumping to a home screen would tell a returning user they were logged
  /// out, which is exactly what this gate prevents.
  bool _restoringSession = false;
  String _initialRoute = AppRoutes.login;

  /// Whether this widget owns [_session] and must dispose it.
  bool _ownsSession = false;

  @override
  void initState() {
    super.initState();

    // One session/client pair is shared by every repository.
    _ownsSession = widget.authSession == null;
    _session = widget.authSession ?? AuthSession();
    final apiClient = ApiClient(session: _session);

    if (kDebugMode) {
      // The single most useful fact when the app "cannot reach the backend":
      // which origin this build actually talks to. Contains no credentials.
      debugPrint(
        '[semuni] API origin: ${ApiConfig.baseUrl}'
        '${ApiConfig.isExplicitlyConfigured ? ' (from SMUNI_API_BASE)' : ' (platform default)'}',
      );
    }

    final overrides = widget.services;

    _authRepository = AuthRepository(
      authService:
          overrides?.authService ??
          ApiAuthService(client: apiClient, session: _session),
      session: _session,
    );

    _tripRepository = TripRepository(
      tripService: overrides?.tripService ?? ApiTripService(client: apiClient),
    );
    _driverDashboardRepository = DriverDashboardRepository(
      service:
          overrides?.driverDashboardService ??
          ApiDriverDashboardService(client: apiClient),
    );
    _driverRouteRepository = DriverRouteRepository(
      service:
          overrides?.driverRouteService ??
          ApiDriverRouteService(client: apiClient),
    );
    _passengerRouteRepository = PassengerRouteRepository(
      service:
          overrides?.passengerRouteService ??
          ApiPassengerRouteService(client: apiClient),
    );
    _passengerWalletRepository = PassengerWalletRepository(
      service:
          overrides?.passengerWalletService ??
          ApiPassengerWalletService(client: apiClient),
      authRepository: _authRepository,
    );
    _paymentRepository = PaymentRepository(
      service:
          overrides?.paymentService ?? ApiPaymentService(client: apiClient),
    );
    _driverDiscoveryRepository = DriverDiscoveryRepository(
      service:
          overrides?.driverDiscoveryService ??
          ApiDriverDiscoveryService(client: apiClient),
    );

    final notification = overrides?.notificationService;
    final driverNotification = overrides?.driverNotificationService;

    _router = AppRouter(
      authRepository: _authRepository,
      tripRepository: _tripRepository,
      driverDashboardRepository: _driverDashboardRepository,
      driverRouteRepository: _driverRouteRepository,
      passengerRouteRepository: _passengerRouteRepository,
      passengerWalletRepository: _passengerWalletRepository,
      paymentRepository: _paymentRepository,
      driverDiscoveryRepository: _driverDiscoveryRepository,
      notificationRepository: NotificationRepository(
        notificationService:
            notification ??
            ApiNotificationService(
              client: apiClient,
              fallbackService: MockNotificationService(),
            ),
      ),
      driverNotificationRepository: NotificationRepository(
        notificationService:
            driverNotification ??
            ApiNotificationService(
              client: apiClient,
              fallbackService: MockDriverNotificationService(),
            ),
      ),
    );

    if (widget.authSession != null) {
      _restoringSession = true;
      _restoreSession();
    }
  }

  /// Resolves the persisted session before the first real screen is shown.
  ///
  /// The repository is the only thing that touches storage and the backend; this
  /// method only turns its answer into a route.
  Future<void> _restoreSession() async {
    AuthResult? restored;
    try {
      restored = await _authRepository.restoreSession();
    } on Object {
      // A keystore or backend failure must never keep the app on the startup
      // screen: the honest fallback is "sign in again".
      restored = null;
    }

    if (!mounted) return;
    setState(() {
      _restoringSession = false;
      _initialRoute = switch (restored) {
        AuthResult(isDriver: true) => AppRoutes.driverHome,
        AuthResult(isPassenger: true) => AppRoutes.passengerHome,
        _ => AppRoutes.login,
      };
    });
  }

  @override
  void dispose() {
    if (_ownsSession) {
      _session.dispose();
    }
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    // Exactly one MaterialApp for the whole lifetime of the app.
    //
    // The gate must NOT swap between a `home:`-based MaterialApp and an
    // `initialRoute`-based one: the navigator element survives that swap and
    // keeps a route whose content was built from the old `home` closure, which
    // then throws `Null check operator used on a null value` on the next
    // rebuild. Instead the navigator is simply not mounted until the answer is
    // known, so it is created once with the final [initialRoute].
    return MaterialApp(
      title: 'semuni',
      debugShowCheckedModeBanner: false,
      theme: AppTheme.light,
      initialRoute: _initialRoute,
      onGenerateRoute: _router.onGenerateRoute,
      navigatorObservers: [appRouteObserver],
      builder: (context, child) {
        // While the persisted session is unresolved the user sees the branded
        // startup screen and no route exists yet.
        if (_restoringSession) {
          return const StartupScreen();
        }

        return Stack(
          children: [
            ?child,
            if (widget.voiceAssistantBuilder != null)
              Positioned.fill(
                child: widget.voiceAssistantBuilder!(
                  _session,
                  appRouteObserver.currentRoute,
                ),
              ),
          ],
        );
      },
    );
  }
}
