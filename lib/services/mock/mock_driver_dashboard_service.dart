import '../../models/driver_activity.dart';
import '../../models/driver_transaction.dart';
import '../../models/driver_withdrawal.dart';
import '../api/interfaces.dart';

export '../api/interfaces.dart' show DriverDashboardService;

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
      completedRides: 12,
      totalEarnings: 320.00,
      averageFare: 26.67,
    );
  }

  @override
  Future<List<DriverTransaction>> getRecentTransactions({int limit = 5}) async {
    await Future<void>.delayed(_simulatedDelay);

    final now = DateTime.now();

    final List<DriverTransaction> transactions = [
      DriverTransaction(
        id: 'tx_001',
        description: 'Taxi Fare Payment',
        amount: 35.00,
        type: DriverTransactionType.payment,
        createdAt: DateTime(now.year, now.month, now.day, 10, 42),
        passengerName: 'Yosef M.',
      ),
      DriverTransaction(
        id: 'tx_002',
        description: 'Taxi Fare Payment',
        amount: 40.00,
        type: DriverTransactionType.payment,
        createdAt: DateTime(now.year, now.month, now.day, 9, 15),
        passengerName: 'Passenger',
      ),
      DriverTransaction(
        id: 'tx_003',
        description: 'Wallet Withdrawal',
        amount: 500.00,
        type: DriverTransactionType.withdrawal,
        createdAt: DateTime(now.year, now.month, now.day - 1, 18, 10),
        passengerName: 'CBE Account',
      ),
      DriverTransaction(
        id: 'tx_004',
        description: 'Taxi Fare Payment',
        amount: 25.00,
        type: DriverTransactionType.payment,
        createdAt: DateTime(now.year, now.month, now.day - 1, 15, 30),
        passengerName: 'Passenger',
      ),
      DriverTransaction(
        id: 'tx_005',
        description: 'Taxi Fare Payment',
        amount: 30.00,
        type: DriverTransactionType.payment,
        createdAt: DateTime(now.year, now.month, now.day - 1, 12, 10),
        passengerName: 'Passenger',
      ),
      DriverTransaction(
        id: 'tx_006',
        description: 'Taxi Fare Payment',
        amount: 35.00,
        type: DriverTransactionType.payment,
        createdAt: DateTime(now.year, now.month, now.day - 1, 11, 45),
        passengerName: 'Passenger',
      ),
      DriverTransaction(
        id: 'tx_007',
        description: 'Wallet Withdrawal',
        amount: 1000.00,
        type: DriverTransactionType.withdrawal,
        createdAt: DateTime(now.year, now.month, now.day - 2, 16, 0),
        passengerName: 'Telebirr',
      ),
      DriverTransaction(
        id: 'tx_008',
        description: 'System Adjustment',
        amount: 15.00,
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
