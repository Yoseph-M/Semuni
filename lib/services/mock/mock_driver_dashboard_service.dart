import '../../models/driver_activity.dart';
import '../../models/driver_transaction.dart';
import '../../models/driver_withdrawal.dart';

/// Abstract service for fetching driver dashboard metrics and transaction history.
///
/// Architecture:
/// UI → DriverDashboardRepository → DriverDashboardService (Mock or Real API)
abstract interface class DriverDashboardService {
  /// Fetches daily activity metrics for the authenticated driver.
  Future<DriverActivity> getTodayActivity();

  /// Fetches the recent transactions for the authenticated driver.
  Future<List<DriverTransaction>> getRecentTransactions({int limit = 5});

  /// Requests a withdrawal from the driver's wallet.
  ///
  /// There is no generic "method" string in the financial contract: the
  /// destination type, destination and an idempotency key are explicit, and
  /// the backend re-checks the driver's balance and status itself.
  Future<DriverWithdrawal> requestWithdrawal({
    required double amountEtb,
    required WithdrawalDestinationType destinationType,
    String? destination,
    String? destinationAccount,
    String? provider,
    required String idempotencyKey,
  });
}

/// Mock implementation of [DriverDashboardService].
///
/// Supplies generic placeholder activity and transaction records so the
/// dashboard UI has structure without preloading any specific corridor,
/// passenger, or fare data that might be mistaken for production records.
class MockDriverDashboardService implements DriverDashboardService {
  static const Duration _simulatedDelay = Duration(milliseconds: 300);

  @override
  Future<DriverActivity> getTodayActivity() async {
    await Future<void>.delayed(_simulatedDelay);

    return const DriverActivity(
      completedRides: 0,
      totalEarnings: 0.00,
      averageFare: 0.00,
    );
  }

  @override
  Future<List<DriverTransaction>> getRecentTransactions({int limit = 5}) async {
    await Future<void>.delayed(_simulatedDelay);

    final now = DateTime.now();

    final List<DriverTransaction> transactions = [
      DriverTransaction(
        id: 'tx_001',
        description: 'Trip payment',
        amount: 0.00,
        type: DriverTransactionType.payment,
        createdAt: DateTime(now.year, now.month, now.day, 10, 42),
        passengerName: 'Passenger',
      ),
      DriverTransaction(
        id: 'tx_002',
        description: 'Trip payment',
        amount: 0.00,
        type: DriverTransactionType.payment,
        createdAt: DateTime(now.year, now.month, now.day, 9, 15),
        passengerName: 'Passenger',
      ),
      DriverTransaction(
        id: 'tx_003',
        description: 'Wallet Withdrawal',
        amount: 0.00,
        type: DriverTransactionType.withdrawal,
        createdAt: DateTime(now.year, now.month, now.day - 1, 18, 10),
        passengerName: 'Withdrawal destination',
      ),
      DriverTransaction(
        id: 'tx_004',
        description: 'Trip payment',
        amount: 0.00,
        type: DriverTransactionType.payment,
        createdAt: DateTime(now.year, now.month, now.day - 1, 15, 30),
        passengerName: 'Passenger',
      ),
      DriverTransaction(
        id: 'tx_005',
        description: 'Trip payment',
        amount: 0.00,
        type: DriverTransactionType.payment,
        createdAt: DateTime(now.year, now.month, now.day - 1, 12, 10),
        passengerName: 'Passenger',
      ),
      DriverTransaction(
        id: 'tx_006',
        description: 'Trip payment',
        amount: 0.00,
        type: DriverTransactionType.payment,
        createdAt: DateTime(now.year, now.month, now.day - 1, 11, 45),
        passengerName: 'Passenger',
      ),
      DriverTransaction(
        id: 'tx_007',
        description: 'Wallet Withdrawal',
        amount: 0.00,
        type: DriverTransactionType.withdrawal,
        createdAt: DateTime(now.year, now.month, now.day - 2, 16, 0),
        passengerName: 'Withdrawal destination',
      ),
      DriverTransaction(
        id: 'tx_008',
        description: 'System Adjustment',
        amount: 0.00,
        type: DriverTransactionType.adjustment,
        createdAt: DateTime(now.year, now.month, now.day - 2, 10, 0),
        passengerName: 'System',
      ),
    ];

    return transactions.take(limit).toList();
  }

  @override
  Future<DriverWithdrawal> requestWithdrawal({
    required double amountEtb,
    required WithdrawalDestinationType destinationType,
    String? destination,
    String? destinationAccount,
    String? provider,
    required String idempotencyKey,
  }) async {
    await Future<void>.delayed(const Duration(milliseconds: 500));

    // Test-only: accepts the request. It does not model provider settlement,
    // because the real flow is the backend's business.
    return DriverWithdrawal(
      id: 'mock-withdrawal-$idempotencyKey',
      amountMinor: (amountEtb * 100).round(),
      currency: 'ETB',
      status: 'PENDING',
      destinationType: destinationType,
      destination: destination,
      createdAt: DateTime.now(),
    );
  }
}

/// Exception thrown when a withdrawal operation fails.
class WithdrawalException implements Exception {
  const WithdrawalException(this.message);

  final String message;

  @override
  String toString() => 'WithdrawalException: $message';
}
