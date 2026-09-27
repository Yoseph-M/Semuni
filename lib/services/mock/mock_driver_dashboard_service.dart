import '../../models/driver_activity.dart';
import '../../models/driver_transaction.dart';

/// Abstract service for fetching driver dashboard metrics and transaction history.
///
/// Architecture:
/// UI → DriverDashboardRepository → DriverDashboardService (Mock or Real API)
abstract interface class DriverDashboardService {
  /// Fetches daily activity metrics for the authenticated driver.
  Future<DriverActivity> getTodayActivity();

  /// Fetches the recent transactions for the authenticated driver.
  Future<List<DriverTransaction>> getRecentTransactions({int limit = 5});
}

/// Mock implementation of [DriverDashboardService].
///
/// Supplies realistic Ethiopian taxi driver statistics and financial transactions.
class MockDriverDashboardService implements DriverDashboardService {
  static const Duration _simulatedDelay = Duration(milliseconds: 300);

  @override
  Future<DriverActivity> getTodayActivity() async {
    await Future<void>.delayed(_simulatedDelay);

    return const DriverActivity(
      completedRides: 12,
      totalEarnings: 1850.00,
      averageFare: 154.17,
    );
  }

  @override
  Future<List<DriverTransaction>> getRecentTransactions({int limit = 5}) async {
    await Future<void>.delayed(_simulatedDelay);

    final now = DateTime.now();

    final List<DriverTransaction> transactions = [
      DriverTransaction(
        id: 'tx_001',
        description: 'Taxi Ride',
        amount: 85.00,
        type: DriverTransactionType.payment,
        createdAt: DateTime(now.year, now.month, now.day, 8, 42),
        passengerName: 'Yosef M.',
      ),
      DriverTransaction(
        id: 'tx_002',
        description: 'Taxi Ride',
        amount: 70.00,
        type: DriverTransactionType.payment,
        createdAt: DateTime(now.year, now.month, now.day, 7, 25),
        passengerName: 'Sara T.',
      ),
      DriverTransaction(
        id: 'tx_003',
        description: 'Wallet Withdrawal',
        amount: 500.00,
        type: DriverTransactionType.withdrawal,
        createdAt: DateTime(now.year, now.month, now.day - 1, 18, 10),
        passengerName: 'Commercial Bank of Ethiopia',
      ),
      DriverTransaction(
        id: 'tx_004',
        description: 'Taxi Ride',
        amount: 120.00,
        type: DriverTransactionType.payment,
        createdAt: DateTime(now.year, now.month, now.day - 1, 15, 30),
        passengerName: 'Almaz B.',
      ),
    ];

    return transactions.take(limit).toList();
  }
}
