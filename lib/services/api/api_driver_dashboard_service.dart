import '../../core/network/api_client.dart';
import '../../models/driver_activity.dart';
import '../../models/driver_transaction.dart';
import '../mock/mock_driver_dashboard_service.dart';

class ApiDriverDashboardService implements DriverDashboardService {
  ApiDriverDashboardService({required this.client});

  final ApiClient client;

  @override
  Future<DriverActivity> getTodayActivity() async {
    final response = await client.get('/drivers/me/earnings');
    final data = response.asMap;

    return DriverActivity(
      completedRides: (data['completedRides'] as num?)?.toInt() ?? 0,
      totalEarnings: (data['todayEarnings'] as num?)?.toDouble() ?? 0,
      averageFare: (data['averageFare'] as num?)?.toDouble() ?? 0,
    );
  }

  @override
  Future<List<DriverTransaction>> getRecentTransactions({
    int limit = 5,
  }) async {
    final response = await client.get('/drivers/me/transactions');
    return response.asMapList.take(limit).map(_toModel).toList(growable: false);
  }

  @override
  Future<DriverTransaction> submitWithdrawal({
    required String driverId,
    required double amount,
    required String method,
  }) {
    throw StateError(
      'Use the authenticated withdrawal API with destinationType and an idempotency key.',
    );
  }

  static DriverTransaction _toModel(Map<String, dynamic> data) {
    final type = (_string(data['type']) ?? 'adjustment').toLowerCase();

    return DriverTransaction(
      id: _string(data['id']) ?? '',
      description: _string(data['description']) ?? 'Transaction',
      amount: (data['amount'] as num?)?.toDouble() ?? 0,
      type: switch (type) {
        'payment' => DriverTransactionType.payment,
        'withdrawal' => DriverTransactionType.withdrawal,
        _ => DriverTransactionType.adjustment,
      },
      createdAt:
          DateTime.tryParse(_string(data['createdAt']) ?? '') ?? DateTime.now(),
      passengerName: _string(data['passengerName']) ?? 'System',
    );
  }

  static String? _string(Object? value) =>
      value is String && value.isNotEmpty ? value : null;
}
