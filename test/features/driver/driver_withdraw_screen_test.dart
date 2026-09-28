import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:smuni/core/utils/app_formatters.dart';
import 'package:smuni/features/driver/screens/driver_home_screen.dart';
import 'package:smuni/features/driver/screens/driver_withdraw_screen.dart';
import 'package:smuni/app/app.dart';
import 'package:smuni/repositories/auth_repository.dart';
import 'package:smuni/repositories/driver_dashboard_repository.dart';
import 'package:smuni/services/mock/mock_auth_service.dart';

// ---------------------------------------------------------------------------
// Helpers
// ---------------------------------------------------------------------------

/// Builds a [DriverWithdrawScreen] with an already-logged-in driver.
Widget buildWithdrawScreen({
  AuthRepository? authRepo,
  DriverDashboardRepository? dashboardRepo,
}) {
  final auth = authRepo ?? _loggedInDriverRepo();
  return MaterialApp(
    home: DriverWithdrawScreen(
      authRepository: auth,
      dashboardRepository: dashboardRepo,
    ),
  );
}

AuthRepository _loggedInDriverRepo() {
  final repo = AuthRepository(authService: MockAuthService());
  // Drive a synchronous-style login by pre-loading the mock driver.
  // We use runAsync in tests that need real async; here we just need the
  // driver set on the repo. Because MockAuthService is the source of truth,
  // we login via the real method in setUp.
  return repo;
}

Future<AuthRepository> loggedInDriverRepoAsync() async {
  final repo = AuthRepository(authService: MockAuthService());
  await repo.loginDriver(username: 'abel', password: 'password');
  return repo;
}

// ---------------------------------------------------------------------------
// Tests
// ---------------------------------------------------------------------------

void main() {
  group('DriverWithdrawScreen — Unit / Widget Tests', () {
    late AuthRepository authRepo;

    setUp(() async {
      authRepo = await loggedInDriverRepoAsync();
    });

    // ── 1. Screen renders ───────────────────────────────────────────────────
    testWidgets('1. Withdraw screen renders with title and balance', (
      tester,
    ) async {
      await tester.pumpWidget(buildWithdrawScreen(authRepo: authRepo));
      await tester.pump(const Duration(seconds: 1));

      expect(find.text('Withdraw'), findsWidgets); // AppBar title
      expect(find.text('Available Balance'), findsOneWidget);
      expect(find.text('Withdrawal Amount'), findsOneWidget);
      expect(find.text('Withdrawal Method'), findsOneWidget);
      expect(find.byKey(const Key('withdraw_amount_field')), findsOneWidget);
      expect(find.byKey(const Key('withdraw_continue_btn')), findsOneWidget);
    });

    // ── 2. Balance from authenticated driver ────────────────────────────────
    testWidgets('2. Displays live available balance from AuthRepository', (
      tester,
    ) async {
      await tester.pumpWidget(buildWithdrawScreen(authRepo: authRepo));
      await tester.pump(const Duration(seconds: 1));

      final balance = authRepo.currentDriver!.accountBalance;
      final formatted = AppFormatters.formatCurrency(balance);
      expect(find.textContaining(formatted), findsOneWidget);
    });

    // ── 3. Empty amount rejected ────────────────────────────────────────────
    testWidgets('3. Empty amount is rejected with validation error', (
      tester,
    ) async {
      await tester.pumpWidget(buildWithdrawScreen(authRepo: authRepo));
      await tester.pump(const Duration(seconds: 1));

      await tester.tap(find.byKey(const Key('withdraw_continue_btn')));
      await tester.pump(const Duration(milliseconds: 300));

      expect(find.text('Please enter an amount.'), findsOneWidget);
    });

    // ── 4. Zero amount rejected ─────────────────────────────────────────────
    testWidgets('4. Zero amount is rejected with validation error', (
      tester,
    ) async {
      await tester.pumpWidget(buildWithdrawScreen(authRepo: authRepo));
      await tester.pump(const Duration(seconds: 1));

      await tester.enterText(
        find.byKey(const Key('withdraw_amount_field')),
        '0',
      );
      await tester.tap(find.byKey(const Key('withdraw_continue_btn')));
      await tester.pump(const Duration(milliseconds: 300));

      expect(find.text('Amount must be greater than zero.'), findsOneWidget);
    });

    // ── 5. Negative amount rejected ─────────────────────────────────────────
    // Note: the input formatter restricts non-numeric chars, but a user can
    // still type "0" which is caught by the > 0 check above.
    // We verify the formatter rejects minus by checking the field stays clean.
    testWidgets(
      '5. Non-numeric / invalid input is filtered by input formatter',
      (tester) async {
        await tester.pumpWidget(buildWithdrawScreen(authRepo: authRepo));
        await tester.pump(const Duration(seconds: 1));

        await tester.enterText(
          find.byKey(const Key('withdraw_amount_field')),
          '-500',
        );
        await tester.pump(const Duration(milliseconds: 100));

        // The FilteringTextInputFormatter strips the minus sign.
        final field = tester.widget<TextFormField>(
          find.byKey(const Key('withdraw_amount_field')),
        );
        final controller = field.controller;
        expect(controller?.text.contains('-'), isFalse);
      },
    );

    // ── 6. Amount > balance rejected ────────────────────────────────────────
    testWidgets('6. Amount exceeding balance is rejected', (tester) async {
      await tester.pumpWidget(buildWithdrawScreen(authRepo: authRepo));
      await tester.pump(const Duration(seconds: 1));

      final balance = authRepo.currentDriver!.accountBalance;
      final excessive = (balance + 1000).toStringAsFixed(2);

      await tester.enterText(
        find.byKey(const Key('withdraw_amount_field')),
        excessive,
      );
      await tester.tap(find.byKey(const Key('withdraw_continue_btn')));
      await tester.pump(const Duration(milliseconds: 300));

      expect(find.textContaining('Insufficient balance'), findsOneWidget);
    });

    // ── 7. Valid amount proceeds to confirmation ────────────────────────────
    testWidgets('7. Valid amount advances to confirmation screen', (
      tester,
    ) async {
      await tester.pumpWidget(buildWithdrawScreen(authRepo: authRepo));
      await tester.pump(const Duration(seconds: 1));

      await tester.enterText(
        find.byKey(const Key('withdraw_amount_field')),
        '500',
      );
      await tester.tap(find.byKey(const Key('withdraw_continue_btn')));
      await tester.pump(const Duration(milliseconds: 300));

      // No validation errors
      expect(find.text('Please enter an amount.'), findsNothing);
      // Confirmation phase should show
      expect(find.text('Review your withdrawal'), findsOneWidget);
      expect(find.byKey(const Key('withdraw_confirm_btn')), findsOneWidget);
    });

    // ── 8. Withdrawal methods render ────────────────────────────────────────
    testWidgets('8. Both withdrawal methods are displayed', (tester) async {
      await tester.pumpWidget(buildWithdrawScreen(authRepo: authRepo));
      await tester.pump(const Duration(seconds: 1));

      expect(find.text('Telebirr'), findsOneWidget);
      expect(find.text('Commercial Bank of Ethiopia'), findsOneWidget);
    });

    // ── 9. Method selection changes UI ──────────────────────────────────────
    testWidgets('9. Selecting a different method updates the selection', (
      tester,
    ) async {
      await tester.pumpWidget(buildWithdrawScreen(authRepo: authRepo));
      await tester.pump(const Duration(seconds: 1));

      await tester.tap(find.text('Commercial Bank of Ethiopia'));
      await tester.pump(const Duration(milliseconds: 300));

      // The CBE row should now show a check icon (Icons.check_circle_rounded)
      expect(find.byIcon(Icons.check_circle_rounded), findsOneWidget);
    });

    // ── 10. Confirmation summary shows correct values ───────────────────────
    testWidgets('10. Confirmation screen shows correct amount and method', (
      tester,
    ) async {
      await tester.pumpWidget(buildWithdrawScreen(authRepo: authRepo));
      await tester.pump(const Duration(seconds: 1));

      await tester.enterText(
        find.byKey(const Key('withdraw_amount_field')),
        '750',
      );
      await tester.tap(find.byKey(const Key('withdraw_continue_btn')));
      await tester.pump(const Duration(milliseconds: 300));

      final formatted = AppFormatters.formatCurrency(750);
      expect(find.textContaining(formatted), findsWidgets);
      expect(find.text('Telebirr'), findsOneWidget);
      expect(find.text('Review your withdrawal'), findsOneWidget);
    });

    // ── 11. Successful mock withdrawal shows success state ──────────────────
    testWidgets('11. Confirming withdrawal shows success state', (
      tester,
    ) async {
      await tester.pumpWidget(buildWithdrawScreen(authRepo: authRepo));
      await tester.pump(const Duration(seconds: 1));

      await tester.enterText(
        find.byKey(const Key('withdraw_amount_field')),
        '200',
      );
      await tester.tap(find.byKey(const Key('withdraw_continue_btn')));
      await tester.pump(const Duration(milliseconds: 300));

      // Tap Confirm Withdrawal
      await tester.tap(find.byKey(const Key('withdraw_confirm_btn')));
      await tester.pumpAndSettle(const Duration(seconds: 2));

      expect(find.text('Withdrawal Submitted'), findsOneWidget);
      expect(find.byKey(const Key('withdraw_done_btn')), findsOneWidget);
    });

    // ── 12. Back from confirmation returns to form ──────────────────────────
    testWidgets('12. Go back from confirmation returns to form', (
      tester,
    ) async {
      await tester.pumpWidget(buildWithdrawScreen(authRepo: authRepo));
      await tester.pump(const Duration(seconds: 1));

      await tester.enterText(
        find.byKey(const Key('withdraw_amount_field')),
        '300',
      );
      await tester.tap(find.byKey(const Key('withdraw_continue_btn')));
      await tester.pump(const Duration(milliseconds: 300));

      expect(find.text('Review your withdrawal'), findsOneWidget);

      await tester.tap(find.text('Go back and edit'));
      await tester.pump(const Duration(milliseconds: 300));

      expect(find.byKey(const Key('withdraw_amount_field')), findsOneWidget);
    });
  });

  // ─── Full App Navigation Flow ─────────────────────────────────────────────

  group('Driver Withdraw — Full App Navigation Flow', () {
    setUp(() {
      final binding = TestWidgetsFlutterBinding.ensureInitialized();
      binding.platformDispatcher.implicitView?.physicalSize = const Size(
        1080,
        2400,
      );
      binding.platformDispatcher.implicitView?.devicePixelRatio = 2.75;
    });

    Future<void> loginAsDriver(WidgetTester tester) async {
      await tester.pumpWidget(const SmuniApp());
      await tester.pumpAndSettle();

      await tester.tap(find.text('Driver'));
      await tester.pumpAndSettle();

      final usernameField = find.byType(TextFormField).first;
      final passwordField = find.byType(TextFormField).last;
      final loginButton = find.text('Login');

      await tester.enterText(usernameField, 'abel');
      await tester.enterText(passwordField, 'password');
      await tester.tap(loginButton);
      await tester.pumpAndSettle(const Duration(seconds: 2));
    }

    // ── 13. Withdraw primary action opens Withdraw screen ──────────────────
    testWidgets(
      '13. Tapping Withdraw action card on Driver Home opens Withdraw screen',
      (tester) async {
        await loginAsDriver(tester);

        final scrollable = find.byType(SingleChildScrollView).first;
        await tester.drag(scrollable, const Offset(0, -500));
        await tester.pumpAndSettle();

        final withdrawCard = find.text('Withdraw').last; // Primary action card
        // Tap the Withdraw action card
        await tester.tap(withdrawCard);
        await tester.pumpAndSettle();

        expect(find.byType(DriverWithdrawScreen), findsOneWidget);

        // Back returns to Driver Home
        if (find.byType(BackButton).evaluate().isNotEmpty) {
          await tester.tap(find.byType(BackButton));
          await tester.pumpAndSettle();
        } else if (find
            .byIcon(Icons.arrow_back_rounded)
            .evaluate()
            .isNotEmpty) {
          await tester.tap(find.byIcon(Icons.arrow_back_rounded));
          await tester.pumpAndSettle();
        }
        expect(find.byType(DriverHomeScreen), findsOneWidget);
      },
    );

    // ── 14. Balance card Withdraw button opens Withdraw screen ─────────────
    testWidgets(
      '14. Tapping Withdraw in Available Balance card opens Withdraw screen',
      (tester) async {
        await loginAsDriver(tester);

        // The balance card Withdraw button is the first 'Withdraw' visible
        final withdrawFinders = find.text('Withdraw');
        await tester.tap(withdrawFinders.first);
        await tester.pumpAndSettle();

        expect(find.byType(DriverWithdrawScreen), findsOneWidget);
      },
    );

    // ── 15. Transactions still works (regression) ──────────────────────────
    testWidgets('15. Driver Transactions still works after Phase 8', (
      tester,
    ) async {
      await loginAsDriver(tester);

      final scrollable = find.byType(SingleChildScrollView).first;
      await tester.drag(scrollable, const Offset(0, -500));
      await tester.pumpAndSettle();

      final transactionsCard = find.text('Transactions').first;
      await tester.tap(transactionsCard);
      await tester.pumpAndSettle();

      expect(find.text('Transactions'), findsWidgets);
    });

    // ── 16. Routes still works (regression) ───────────────────────────────
    testWidgets('16. Driver Routes still works after Phase 8', (tester) async {
      await loginAsDriver(tester);

      final scrollable = find.byType(SingleChildScrollView).first;
      await tester.drag(scrollable, const Offset(0, -500));
      await tester.pumpAndSettle();

      final routesCard = find.text('Routes').first;
      await tester.tap(routesCard);
      await tester.pumpAndSettle();

      expect(find.textContaining('Routes'), findsWidgets);
    });

    // ── 17. Passenger regression ───────────────────────────────────────────
    testWidgets('17. Passenger login still works (regression)', (tester) async {
      await tester.pumpWidget(const SmuniApp());
      await tester.pumpAndSettle();

      final usernameField = find.byType(TextFormField).first;
      final passwordField = find.byType(TextFormField).last;
      final loginButton = find.text('Login');

      await tester.enterText(usernameField, 'yosef');
      await tester.enterText(passwordField, 'password');
      await tester.tap(loginButton);
      await tester.pumpAndSettle(const Duration(seconds: 2));

      expect(find.textContaining('Yosef'), findsWidgets);
    });
  });
}
