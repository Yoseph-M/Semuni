import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:smuni/app/theme/app_colors.dart';
import 'package:smuni/features/passenger/screens/passenger_notifications_screen.dart';
import 'package:smuni/features/passenger/screens/passenger_home_screen.dart';
import 'package:smuni/models/app_notification.dart';
import 'package:smuni/repositories/auth_repository.dart';
import 'package:smuni/repositories/notification_repository.dart';
import 'package:smuni/services/mock/mock_notification_service.dart';

void main() {
  // ---------------------------------------------------------------------------
  // Test helpers
  // ---------------------------------------------------------------------------

  setUp(() {
    final binding = TestWidgetsFlutterBinding.ensureInitialized();
    binding.platformDispatcher.implicitView?.physicalSize = const Size(
      1080,
      2400,
    );
    binding.platformDispatcher.implicitView?.devicePixelRatio = 2.75;
  });

  tearDown(() {
    final binding = TestWidgetsFlutterBinding.ensureInitialized();
    binding.platformDispatcher.implicitView?.resetPhysicalSize();
    binding.platformDispatcher.implicitView?.resetDevicePixelRatio();
  });

  Widget wrapScreen(Widget child) {
    return MaterialApp(
      routes: {
        '/passenger/wallet': (_) => const Scaffold(body: Text('Wallet')),
        '/passenger/trip-history': (_) =>
            const Scaffold(body: Text('Trip History')),
        '/passenger/map': (_) => const Scaffold(body: Text('Map')),
        '/passenger/notifications': (_) => PassengerNotificationsScreen(
          notificationRepository: NotificationRepository(
            notificationService: MockNotificationService(
              simulatedDelay: Duration.zero,
            ),
          ),
        ),
      },
      home: child,
    );
  }

  NotificationRepository makeRepo({Duration delay = Duration.zero}) =>
      NotificationRepository(
        notificationService: MockNotificationService(simulatedDelay: delay),
      );

  NotificationRepository makeEmptyRepo() =>
      NotificationRepository(notificationService: _EmptyNotificationService());

  NotificationRepository makeErrorRepo() =>
      NotificationRepository(notificationService: _ErrorNotificationService());

  // ---------------------------------------------------------------------------
  // 1. Screen loads
  // ---------------------------------------------------------------------------

  group('PassengerNotificationsScreen', () {
    testWidgets('1. screen renders without crashing', (tester) async {
      await tester.pumpWidget(
        wrapScreen(
          PassengerNotificationsScreen(notificationRepository: makeRepo()),
        ),
      );
      await tester.pump(); // let initState start
      expect(find.byType(PassengerNotificationsScreen), findsOneWidget);
    });

    // -------------------------------------------------------------------------
    // 2. Notifications appear
    // -------------------------------------------------------------------------

    testWidgets('2. mock notifications appear after loading', (tester) async {
      await tester.pumpWidget(
        wrapScreen(
          PassengerNotificationsScreen(notificationRepository: makeRepo()),
        ),
      );
      await tester.pumpAndSettle();

      // The default mock service has 6 notifications
      expect(find.text('Taxi payment completed'), findsWidgets);
      expect(find.text('Wallet top-up successful'), findsOneWidget);
      expect(find.text('Journey recorded'), findsOneWidget);
      expect(find.text('Welcome to semuni'), findsOneWidget);
    });

    // -------------------------------------------------------------------------
    // 3. Notification title and body are shown
    // -------------------------------------------------------------------------

    testWidgets('3. notification title and body are displayed', (tester) async {
      await tester.pumpWidget(
        wrapScreen(
          PassengerNotificationsScreen(notificationRepository: makeRepo()),
        ),
      );
      await tester.pumpAndSettle();

      expect(find.text('Wallet top-up successful'), findsOneWidget);
      expect(find.textContaining('ETB 500.00'), findsWidgets);
    });

    // -------------------------------------------------------------------------
    // 4. Unread notification is visually distinct
    // -------------------------------------------------------------------------

    testWidgets('4. unread notification shows dot indicator', (tester) async {
      await tester.pumpWidget(
        wrapScreen(
          PassengerNotificationsScreen(notificationRepository: makeRepo()),
        ),
      );
      await tester.pumpAndSettle();

      // Unread dot badges are small green circles — there are unread items
      // We verify via the ColoredBox that unread items have the tinted surface
      final coloredBoxes = tester.widgetList<ColoredBox>(
        find.byType(ColoredBox),
      );
      final unreadBoxes = coloredBoxes
          .where((b) => b.color == AppColors.surfaceVariant)
          .toList();
      // Default mock has 3 unread notifications
      expect(unreadBoxes.length, greaterThanOrEqualTo(3));
    });

    // -------------------------------------------------------------------------
    // 5. Tapping unread notification marks it as read
    // -------------------------------------------------------------------------

    testWidgets('5. tapping unread marks it as read', (tester) async {
      final repo = makeRepo();

      await tester.pumpWidget(
        wrapScreen(PassengerNotificationsScreen(notificationRepository: repo)),
      );
      await tester.pumpAndSettle();

      // Count unread boxes before tap
      int unreadBefore() => tester
          .widgetList<ColoredBox>(find.byType(ColoredBox))
          .where((b) => b.color == AppColors.surfaceVariant)
          .length;

      final before = unreadBefore();
      expect(before, greaterThan(0));

      // Tap the first unread notification (Taxi payment completed)
      await tester.tap(find.text('Taxi payment completed').first);
      await tester.pumpAndSettle();

      // After tapping, we've navigated to Trip History (for paymentReceived)
      // Return isn't relevant here — the repo in-memory state is what matters
      final notifications = await repo.getNotifications();
      final tapped = notifications.firstWhere(
        (n) => n.title == 'Taxi payment completed',
      );
      expect(tapped.isRead, isTrue);
    });

    // -------------------------------------------------------------------------
    // 6. Empty state
    // -------------------------------------------------------------------------

    testWidgets('6. empty state shows "You\'re all caught up"', (tester) async {
      await tester.pumpWidget(
        wrapScreen(
          PassengerNotificationsScreen(notificationRepository: makeEmptyRepo()),
        ),
      );
      await tester.pumpAndSettle();

      expect(find.text("You're all caught up"), findsOneWidget);
      expect(find.byIcon(Icons.notifications_none_rounded), findsOneWidget);
    });

    // -------------------------------------------------------------------------
    // 7. Loading state
    // -------------------------------------------------------------------------

    testWidgets('7. loading indicator shown while fetching', (tester) async {
      // _NeverResolvingNotificationService returns a Future that never
      // completes, so the screen stays in the loading state indefinitely.
      await tester.pumpWidget(
        wrapScreen(
          PassengerNotificationsScreen(
            notificationRepository: NotificationRepository(
              notificationService: _NeverResolvingNotificationService(),
            ),
          ),
        ),
      );
      // Single pump — initState fires and _isLoading = true.
      await tester.pump();
      expect(find.byType(CircularProgressIndicator), findsOneWidget);
    });

    // -------------------------------------------------------------------------
    // 8. Error state
    // -------------------------------------------------------------------------

    testWidgets('8. error state shown on fetch failure', (tester) async {
      await tester.pumpWidget(
        wrapScreen(
          PassengerNotificationsScreen(notificationRepository: makeErrorRepo()),
        ),
      );
      await tester.pumpAndSettle();

      expect(
        find.text('Unable to load notifications. Please try again.'),
        findsOneWidget,
      );
      expect(find.text('Try again'), findsOneWidget);
    });

    // -------------------------------------------------------------------------
    // 9. Mark all as read button appears when there are unread notifications
    // -------------------------------------------------------------------------

    testWidgets('9. "Mark all read" action shown when unread exist', (
      tester,
    ) async {
      await tester.pumpWidget(
        wrapScreen(
          PassengerNotificationsScreen(notificationRepository: makeRepo()),
        ),
      );
      await tester.pumpAndSettle();

      expect(find.text('Mark all read'), findsOneWidget);
    });

    // -------------------------------------------------------------------------
    // 10. App bar title is Notifications
    // -------------------------------------------------------------------------

    testWidgets('10. app bar shows Notifications title', (tester) async {
      await tester.pumpWidget(
        wrapScreen(
          PassengerNotificationsScreen(notificationRepository: makeRepo()),
        ),
      );
      await tester.pump();

      expect(find.text('Notifications'), findsOneWidget);
    });
  });

  // ---------------------------------------------------------------------------
  // 11. Passenger Home notification bell opens Notifications screen
  // ---------------------------------------------------------------------------

  group('PassengerHomeScreen notification integration', () {
    testWidgets(
      '11. tapping notification bell navigates to PassengerNotificationsScreen',
      (tester) async {
        final authRepo = AuthRepository();
        await tester.runAsync(() async {
          await authRepo.loginPassenger(
            username: 'yosef',
            password: 'password',
          );
        });

        await tester.pumpWidget(
          MaterialApp(
            routes: {
              '/passenger/notifications': (_) => PassengerNotificationsScreen(
                notificationRepository: makeRepo(),
              ),
            },
            home: PassengerHomeScreen(
              authRepository: authRepo,
              notificationRepository: makeRepo(),
            ),
          ),
        );
        await tester.pumpAndSettle();

        // Tap the notification bell icon
        await tester.tap(find.byIcon(Icons.notifications_outlined));
        await tester.pumpAndSettle();

        // Now on Notifications screen
        expect(find.byType(PassengerNotificationsScreen), findsOneWidget);
        expect(find.text('Notifications'), findsOneWidget);
      },
    );

    // -------------------------------------------------------------------------
    // 12. Existing Passenger Home still renders correctly
    // -------------------------------------------------------------------------

    testWidgets('12. Passenger Home still renders with all sections', (
      tester,
    ) async {
      final authRepo = AuthRepository();
      await tester.runAsync(() async {
        await authRepo.loginPassenger(username: 'yosef', password: 'password');
      });

      await tester.pumpWidget(
        wrapScreen(
          PassengerHomeScreen(
            authRepository: authRepo,
            notificationRepository: makeRepo(),
          ),
        ),
      );
      await tester.pumpAndSettle(const Duration(seconds: 1));

      expect(find.byType(PassengerHomeScreen), findsOneWidget);
      expect(find.text('Where would you like to go?'), findsOneWidget);
      expect(find.text('Wallet Balance'), findsOneWidget);
      expect(find.text('Recent Trips'), findsOneWidget);
    });
  });
}

// ---------------------------------------------------------------------------
// Test doubles
// ---------------------------------------------------------------------------

/// Returns an empty notification list — for empty state tests.
class _EmptyNotificationService implements NotificationService {
  @override
  bool get isSupported => true;

  @override
  Future<List<AppNotification>> getNotifications() async => [];

  @override
  Future<AppNotification> markAsRead(String id) async =>
      throw UnimplementedError('not used in empty state tests');

  @override
  Future<void> markAllAsRead() async {}
}

/// Always throws — for error state tests.
class _ErrorNotificationService implements NotificationService {
  @override
  bool get isSupported => true;

  @override
  Future<List<AppNotification>> getNotifications() async =>
      throw Exception('simulated network error');

  @override
  Future<AppNotification> markAsRead(String id) async =>
      throw UnimplementedError('not used in error state tests');

  @override
  Future<void> markAllAsRead() async {}
}

/// Never resolves — used to hold the screen in the loading state for testing.
class _NeverResolvingNotificationService implements NotificationService {
  @override
  bool get isSupported => true;

  @override
  Future<List<AppNotification>> getNotifications() =>
      Completer<List<AppNotification>>().future;

  @override
  Future<AppNotification> markAsRead(String id) =>
      throw UnimplementedError('not used in loading state tests');

  @override
  Future<void> markAllAsRead() async {}
}
