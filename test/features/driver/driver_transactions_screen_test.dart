import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:smuni/core/utils/app_formatters.dart';
import 'package:smuni/features/driver/screens/driver_home_screen.dart';
import 'package:smuni/features/driver/screens/driver_transactions_screen.dart';
import 'package:smuni/models/driver_transaction.dart';
import 'package:smuni/features/driver/widgets/driver_transaction_card.dart';
import 'package:smuni/navigation/app_routes.dart';
import 'package:smuni/repositories/auth_repository.dart';
import 'package:smuni/repositories/driver_dashboard_repository.dart';
import 'package:smuni/services/mock/mock_driver_dashboard_service.dart';
import '../../support/smuni_test_app.dart';

void main() {
  group('DriverTransactionsScreen Widget Tests', () {
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

    Widget buildScreen({
      DriverDashboardRepository? dashboardRepo,
      AuthRepository? authRepo,
    }) {
      final dashboard = dashboardRepo ?? DriverDashboardRepository();
      return MaterialApp(
        routes: {
          AppRoutes.driverHome: (_) =>
              const Scaffold(body: Text('Driver Home')),
          AppRoutes.driverSettings: (_) =>
              const Scaffold(body: Text('Settings')),
        },
        home: DriverTransactionsScreen(repository: dashboard),
      );
    }

    testWidgets('1. DriverTransactionsScreen renders with title and filters', (
      tester,
    ) async {
      await tester.pumpWidget(buildScreen());
      await tester.pump(const Duration(seconds: 1));
      await tester.pump(const Duration(seconds: 1));

      expect(find.byType(DriverTransactionsScreen), findsOneWidget);
      expect(find.text('Transactions'), findsOneWidget);
      expect(find.text('All'), findsWidgets);
      expect(find.text('Earnings'), findsOneWidget);
      expect(find.text('Withdrawals'), findsOneWidget);
    });

    testWidgets('2. Displays transaction data from repository dynamically', (
      tester,
    ) async {
      final service = MockDriverDashboardService();
      final repo = DriverDashboardRepository(service: service);
      List<DriverTransaction> expectedTransactions = [];
      await tester.runAsync(() async {
        expectedTransactions = await service.getRecentTransactions(limit: 50);
      });

      await tester.pumpWidget(buildScreen(dashboardRepo: repo));
      await tester.pump(const Duration(seconds: 1));
      await tester.pump(const Duration(seconds: 1));

      // Check first transaction details
      final firstTx = expectedTransactions.first;
      expect(find.text(firstTx.description), findsWidgets);
      expect(find.text(firstTx.passengerName), findsWidgets);

      final expectedAmount = AppFormatters.formatCurrency(firstTx.amount);
      expect(find.textContaining(expectedAmount), findsWidgets);

      // Verify transaction cards render
      expect(
        find.byType(DriverTransactionCard),
        findsNWidgets(expectedTransactions.length),
      );
    });

    testWidgets('3. Filter chips switch displayed transactions correctly', (
      tester,
    ) async {
      final service = MockDriverDashboardService();
      final repo = DriverDashboardRepository(service: service);
      List<DriverTransaction> expectedTransactions = [];
      await tester.runAsync(() async {
        expectedTransactions = await service.getRecentTransactions(limit: 50);
      });
      final earningsCount = expectedTransactions
          .where((t) => t.isCredit)
          .length;
      final withdrawalsCount = expectedTransactions
          .where((t) => !t.isCredit)
          .length;

      await tester.pumpWidget(buildScreen(dashboardRepo: repo));
      await tester.pump(const Duration(seconds: 1));
      await tester.pump(const Duration(seconds: 1));

      // Tap 'Earnings' filter chip
      await tester.tap(find.text('Earnings'));
      await tester.pump(const Duration(seconds: 1));
      await tester.pump(const Duration(seconds: 1));

      expect(find.byType(DriverTransactionCard), findsNWidgets(earningsCount));

      // Tap 'Withdrawals' filter chip
      await tester.tap(find.text('Withdrawals'));
      await tester.pump(const Duration(seconds: 1));
      await tester.pump(const Duration(seconds: 1));

      expect(
        find.byType(DriverTransactionCard),
        findsNWidgets(withdrawalsCount),
      );

      // Tap 'All' filter chip
      await tester.tap(
        find.text('All').first,
      ); // "All" might be the choice chip text
      await tester.pump(const Duration(seconds: 1));
      await tester.pump(const Duration(seconds: 1));

      expect(
        find.byType(DriverTransactionCard),
        findsNWidgets(expectedTransactions.length),
      );
    });
  });

  group('Driver Transactions — Full App Navigation Flow', () {
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

    Future<void> loginAsDriver(WidgetTester tester) async {
      await tester.pumpWidget(smuniTestApp());
      await tester.pump(const Duration(seconds: 1));
      await tester.pump(const Duration(seconds: 1));

      // Select Driver role
      await tester.tap(find.text('Driver'));
      await tester.pump(const Duration(seconds: 1));
      await tester.pump(const Duration(seconds: 1));

      // Enter credentials
      await tester.enterText(
        find.widgetWithText(TextFormField, 'Username'),
        'abel',
      );
      await tester.enterText(
        find.widgetWithText(TextFormField, 'Password'),
        'password',
      );

      await tester.ensureVisible(find.text('Login'));
      await tester.tap(find.text('Login'));
      await tester.pumpAndSettle(const Duration(seconds: 2));
    }

    testWidgets(
      '4. Tapping Transactions action card on Driver Home opens Driver Transactions',
      (tester) async {
        await loginAsDriver(tester);
        expect(find.byType(DriverHomeScreen), findsOneWidget);

        // Scroll until primary action card is visible
        final scrollable = find.byType(Scrollable).first;
        await tester.scrollUntilVisible(
          find.text('Transactions').first,
          150,
          scrollable: scrollable,
        );

        // Tap the Transactions action card in primary actions
        final transactionsFinders = find.text('Transactions');
        await tester.tap(transactionsFinders.first);
        await tester.pump(const Duration(seconds: 1));
        await tester.pump(const Duration(seconds: 1));

        // Must now be on DriverTransactionsScreen
        expect(find.byType(DriverTransactionsScreen), findsOneWidget);
        expect(find.text('All'), findsWidgets);

        // Back button returns to Driver Home
        // Note: Scaffold AppBar automatically has a Tooltip 'Back' for its leading icon
        await tester.tap(find.byType(BackButton));
        await tester.pump(const Duration(seconds: 1));
        await tester.pump(const Duration(seconds: 1));

        expect(find.byType(DriverHomeScreen), findsOneWidget);
      },
    );

    testWidgets(
      '5. Tapping View all in Recent Transactions opens Driver Transactions',
      (tester) async {
        await loginAsDriver(tester);
        expect(find.byType(DriverHomeScreen), findsOneWidget);

        final scrollable = find.byType(Scrollable).first;
        await tester.scrollUntilVisible(
          find.text('View all'),
          150,
          scrollable: scrollable,
        );

        await tester.tap(find.text('View all'));
        await tester.pump(const Duration(seconds: 1));
        await tester.pump(const Duration(seconds: 1));

        // Must now be on DriverTransactionsScreen
        expect(find.byType(DriverTransactionsScreen), findsOneWidget);
      },
    );

    testWidgets('6. Passenger navigation remains unaffected (regression)', (
      tester,
    ) async {
      await tester.pumpWidget(smuniTestApp());
      await tester.pump(const Duration(seconds: 1));
      await tester.pump(const Duration(seconds: 1));

      // Default role is Passenger
      await tester.enterText(
        find.widgetWithText(TextFormField, 'Username'),
        'yosef',
      );
      await tester.enterText(
        find.widgetWithText(TextFormField, 'Password'),
        'password',
      );

      await tester.ensureVisible(find.text('Login'));
      await tester.tap(find.text('Login'));
      await tester.pumpAndSettle(const Duration(seconds: 2));

      // Must NOT navigate to Driver transactions or Driver home
      expect(find.byType(DriverTransactionsScreen), findsNothing);
      expect(find.byType(DriverHomeScreen), findsNothing);

      // Must be on Passenger Home
      expect(find.text('Wallet Balance'), findsOneWidget);
    });
  });
}
