import '../services/api/interfaces.dart';
import '../models/driver_activity.dart';
import '../models/driver_transaction.dart';
import '../models/driver_withdrawal.dart';

class DriverDashboardRepository {
  DriverDashboardRepository({DriverDashboardService? service})
    : _service = service ?? const _EmptyDriverDashboardService();

  final DriverDashboardService _service;

  Future<DriverActivity> getTodayActivity() => _service.getTodayActivity();

  Future<List<DriverTransaction>> getRecentTransactions({int limit = 5}) =>
      _service.getRecentTransactions(limit: limit);

  /// Requests a withdrawal. The driver's own balance is never adjusted here:
  /// it changes only when the backend reports the new balance.
  Future<DriverWithdrawal> requestWithdrawal({
    required double amountEtb,
    required WithdrawalDestinationType destinationType,
    String? destination,
    String? destinationAccount,
    String? provider,
    required String idempotencyKey,
  }) => _service.requestWithdrawal(
    amountEtb: amountEtb,
    destinationType: destinationType,
    destination: destination,
    destinationAccount: destinationAccount,
    provider: provider,
    idempotencyKey: idempotencyKey,
  );
}

class _EmptyDriverDashboardService implements DriverDashboardService {
  const _EmptyDriverDashboardService();

  @override
  Future<DriverActivity> getTodayActivity() async => const DriverActivity(
    completedRides: 0,
    totalEarnings: 0.0,
    averageFare: 0.0,
  );

  @override
  Future<List<DriverTransaction>> getRecentTransactions({
    int limit = 5,
  }) async => const [];

  @override
  Future<DriverWithdrawal> requestWithdrawal({
    required double amountEtb,
    required WithdrawalDestinationType destinationType,
    String? destination,
    String? destinationAccount,
    String? provider,
    required String idempotencyKey,
  }) async => throw StateError('No driver dashboard service configured');
}
