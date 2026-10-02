import '../models/driver_activity.dart';
import '../models/driver_transaction.dart';
import '../services/mock/mock_driver_dashboard_service.dart';

class DriverDashboardRepository {
  DriverDashboardRepository({DriverDashboardService? service})
      : _service = service ?? MockDriverDashboardService();

  final DriverDashboardService _service;

  Future<DriverActivity> getTodayActivity() => _service.getTodayActivity();

  Future<List<DriverTransaction>> getRecentTransactions({int limit = 5}) =>
      _service.getRecentTransactions(limit: limit);

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
