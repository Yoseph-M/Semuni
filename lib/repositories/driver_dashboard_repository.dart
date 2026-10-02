import '../models/driver_activity.dart';
import '../models/driver_transaction.dart';
import '../models/driver_withdrawal.dart';
import '../services/mock/mock_driver_dashboard_service.dart';

class DriverDashboardRepository {
  DriverDashboardRepository({DriverDashboardService? service})
      : _service = service ?? MockDriverDashboardService();

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
