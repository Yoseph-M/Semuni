import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:smuni/app/theme/app_colors.dart';
import 'package:smuni/features/driver/screens/driver_notifications_screen.dart';
import 'package:smuni/features/driver/screens/driver_home_screen.dart';
import 'package:smuni/models/app_notification.dart';
import 'package:smuni/repositories/auth_repository.dart';
import 'package:smuni/repositories/notification_repository.dart';
import 'package:smuni/services/mock/mock_driver_notification_service.dart';
import 'package:smuni/services/mock/mock_notification_service.dart'; // For interface

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
        '/driver/transactions': (_) =>
            const Scaffold(body: Text('Transactions')),
        '/driver/withdraw': (_) => const Scaffold(body: Text('Withdraw')),
        '/driver/routes': (_) => const Scaffold(body: Text('Routes')),
        '/driver/notifications': (_) => DriverNotificationsScreen(
          notificationRepository: NotificationRepository(
            notificationService: MockDriverNotificationService(
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
        notificationService: MockDriverNotificationService(
          simulatedDelay: delay,
        ),
      );

  NotificationRepository makeEmptyRepo() =>
      NotificationRepository(notificationService: _EmptyNotificationService());

  NotificationRepository makeErrorRepo() =>
      NotificationRepository(notificationService: _ErrorNotificationService());

  // ---------------------------------------------------------------------------
  // 1. Screen loads
  // ---------------------------------------------------------------------------

  group('DriverNotificationsScreen', () {
    testWidgets('1. screen renders without crashing', (tester) async {
      await tester.pumpWidget(
        wrapScreen(
          DriverNotificationsScreen(notificationRepository: makeRepo()),
        ),
      );
      await tester.pump(); // let initState start
      expect(find.byType(DriverNotificationsScreen), findsOneWidget);
    });

    // -------------------------------------------------------------------------
    // 2. Notifications appear
    // -------------------------------------------------------------------------

    testWidgets('2. mock notifications appear after loading', (tester) async {
      await tester.pumpWidget(
        wrapScreen(
          DriverNotificationsScreen(notificationRepository: makeRepo()),
        ),
      );
      await tester.pumpAndSettle();

      // The default mock service has 5 notifications
      expect(find.text('New route assigned'), findsOneWidget);
      expect(find.text('Daily earnings updated'), findsOneWidget);
      expect(find.text('Withdrawal successful'), findsOneWidget);
      expect(find.text('Transaction recorded'), findsOneWidget);
    });

    // -------------------------------------------------------------------------
    // 3. Notification title and body are shown
    // -------------------------------------------------------------------------

    testWidgets('3. notification title and body are displayed', (tester) async {
      await tester.pumpWidget(
        wrapScreen(
          DriverNotificationsScreen(notificationRepository: makeRepo()),
        ),
      );
      await tester.pumpAndSettle();

      expect(find.text('New route assigned'), findsOneWidget);
      expect(
        find.text('You have been assigned to the Bole → Piazza route.'),
        findsOneWidget,
      );
    });

    // -------------------------------------------------------------------------
    // 4. Unread notification is visually distinct
    // -------------------------------------------------------------------------

    testWidgets('4. unread notification shows dot indicator', (tester) async {
      await tester.pumpWidget(
        wrapScreen(
          DriverNotificationsScreen(notificationRepository: makeRepo()),
        ),
      );
      await tester.pumpAndSettle();

      final coloredBoxes = tester.widgetList<ColoredBox>(
        find.byType(ColoredBox),
      );
      final unreadBoxes = coloredBoxes
          .where((b) => b.color == AppColors.surfaceVariant)
          .toList();
      // Default driver mock has 3 unread notifications
      expect(unreadBoxes.length, greaterThanOrEqualTo(3));
    });

    // -------------------------------------------------------------------------
    // 5. Tapping unread notification marks it as read
    // -------------------------------------------------------------------------

    testWidgets('5. tapping unread marks it as read', (tester) async {
      final repo = makeRepo();

      await tester.pumpWidget(
        wrapScreen(DriverNotificationsScreen(notificationRepository: repo)),
      );
      await tester.pumpAndSettle();

      int unreadBefore() => tester
          .widgetList<ColoredBox>(find.byType(ColoredBox))
          .where((b) => b.color == AppColors.surfaceVariant)
          .length;

      final before = unreadBefore();
      expect(before, greaterThan(0));

      await tester.tap(find.text('New route assigned').first);
      await tester.pumpAndSettle();

      final notifications = await repo.getNotifications();
      final tapped = notifications.firstWhere(
        (n) => n.title == 'New route assigned',
      );
      expect(tapped.isRead, isTrue);
    });

    // -------------------------------------------------------------------------
    // 6. Empty state
    // -------------------------------------------------------------------------

    testWidgets('6. empty state shows "You\'re all caught up"', (tester) async {
      await tester.pumpWidget(
        wrapScreen(
          DriverNotificationsScreen(notificationRepository: makeEmptyRepo()),
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
      await tester.pumpWidget(
        wrapScreen(
          DriverNotificationsScreen(
            notificationRepository: NotificationRepository(
              notificationService: _NeverResolvingNotificationService(),
            ),
          ),
        ),
      );
      await tester.pump();
      expect(find.byType(CircularProgressIndicator), findsOneWidget);
    });

    // -------------------------------------------------------------------------
    // 8. Error state
    // -------------------------------------------------------------------------

    testWidgets('8. error state shown on fetch failure', (tester) async {
      await tester.pumpWidget(
        wrapScreen(
          DriverNotificationsScreen(notificationRepository: makeErrorRepo()),
        ),
      );
      await tester.pumpAndSettle();

      expect(
        find.text('Unable to load notifications. Please try again.'),
        findsOneWidget,
      );
      expect(find.text('Try again'), findsOneWidget);
    });
  });

  // ---------------------------------------------------------------------------
  // 9. Driver Home notification bell opens Notifications screen
  // ---------------------------------------------------------------------------

  group('DriverHomeScreen notification integration', () {
    testWidgets(
      '9. tapping notification bell navigates to DriverNotificationsScreen',
      (tester) async {
        final authRepo = AuthRepository();
        await tester.runAsync(() async {
          await authRepo.loginDriver(username: 'abebe', password: 'password');
        });

        await tester.pumpWidget(
          MaterialApp(
            routes: {
              '/driver/notifications': (_) =>
                  DriverNotificationsScreen(notificationRepository: makeRepo()),
            },
            home: DriverHomeScreen(
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
        expect(find.byType(DriverNotificationsScreen), findsOneWidget);
        expect(find.text('Notifications'), findsOneWidget);
      },
    );

    // -------------------------------------------------------------------------
    // 10. Existing Driver Home still renders correctly
    // -------------------------------------------------------------------------

    testWidgets('10. Driver Home still renders with all sections', (
      tester,
    ) async {
      final authRepo = AuthRepository();
      await tester.runAsync(() async {
        await authRepo.loginDriver(username: 'abebe', password: 'password');
      });

      await tester.pumpWidget(
        wrapScreen(
          DriverHomeScreen(
            authRepository: authRepo,
            notificationRepository: makeRepo(),
          ),
        ),
      );
      await tester.pumpAndSettle(const Duration(seconds: 1));

      expect(find.byType(DriverHomeScreen), findsOneWidget);
      expect(find.text('Driver Dashboard'), findsOneWidget);
      expect(find.text('Available Balance'), findsOneWidget);
      expect(find.text('Recent Transactions'), findsOneWidget);
    });
  });
}

// ---------------------------------------------------------------------------
// Test doubles
// ---------------------------------------------------------------------------

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
