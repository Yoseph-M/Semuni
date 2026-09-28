import '../models/driver_activity.dart';
import '../models/driver_transaction.dart';
import '../services/mock/mock_driver_dashboard_service.dart';

/// Repository for driver dashboard operations.
///
/// Mediates between the presentation layer and the driver service layer.
///
/// Architecture:
/// UI → DriverDashboardRepository → DriverDashboardService (Mock or Real API)
class DriverDashboardRepository {
  DriverDashboardRepository({DriverDashboardService? service})
    : _service = service ?? MockDriverDashboardService();

  final DriverDashboardService _service;

  /// Retrieves today's operational summary for the driver.
  Future<DriverActivity> getTodayActivity() => _service.getTodayActivity();

  /// Retrieves recent transactions (earnings and withdrawals).
  Future<List<DriverTransaction>> getRecentTransactions({int limit = 5}) =>
      _service.getRecentTransactions(limit: limit);

  /// Submits a mock withdrawal request.
  ///
  /// Returns the resulting [DriverTransaction] on success.
  /// Throws a [WithdrawalException] on failure.
  Future<DriverTransaction> submitWithdrawal({
    required String driverId,
    required double amount,
    required String method,
  }) => _service.submitWithdrawal(
    driverId: driverId,
    amount: amount,
    method: method,
  );
}
