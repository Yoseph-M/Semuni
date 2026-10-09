import 'package:flutter/material.dart';

import 'package:smuni/app/app.dart';
import 'package:smuni/services/mock/mock_auth_service.dart';
import 'package:smuni/services/mock/mock_driver_dashboard_service.dart';
import 'package:smuni/services/mock/mock_driver_discovery_service.dart';
import 'package:smuni/services/mock/mock_driver_notification_service.dart';
import 'package:smuni/services/mock/mock_driver_route_service.dart';
import 'package:smuni/services/mock/mock_notification_service.dart';
import 'package:smuni/services/mock/mock_passenger_route_service.dart';
import 'package:smuni/services/mock/mock_passenger_wallet_service.dart';
import 'package:smuni/services/mock/mock_payment_service.dart';
import 'package:smuni/services/mock/mock_trip_service.dart';

/// The application, wired to the shipped mocks, for widget tests.
///
/// Production builds `SmuniApp()` with the real API-backed services; the mocks
/// are selected here and only here, so a full login → home → sub-screen flow can
/// run offline without a backend. The mocks' own default delays are kept, which
/// is what the tests' `pump(Duration)` calls are written against.
Widget smuniTestApp() {
  // One trip service and one wallet service shared by the wallet and payment
  // repositories, so a payment debits the same balance the wallet screen shows.
  final trips = MockTripService();
  final wallet = MockPassengerWalletService();

  return SmuniApp(
    services: SmuniServices(
      authService: MockAuthService(),
      tripService: trips,
      passengerWalletService: wallet,
      paymentService: MockPaymentService(
        tripService: trips,
        walletService: wallet,
      ),
      driverDashboardService: MockDriverDashboardService(),
      driverRouteService: MockDriverRouteService(),
      driverDiscoveryService: MockDriverDiscoveryService(),
      passengerRouteService: MockPassengerRouteService(),
      notificationService: MockNotificationService(),
      driverNotificationService: MockDriverNotificationService(),
    ),
  );
}
