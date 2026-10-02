import '../../core/network/api_client.dart';
import '../../models/driver_activity.dart';
import '../../models/driver_transaction.dart';
import '../../models/driver_withdrawal.dart';
import '../mock/mock_driver_dashboard_service.dart';

/// Driver dashboard and withdrawals against the backend.
///
/// Earnings and transactions are derived by the server from settled payments;
/// a driver cannot post a number into their own ledger. A withdrawal is a
/// request: it is accepted as PENDING and settled asynchronously.
class ApiDriverDashboardService implements DriverDashboardService {
  ApiDriverDashboardService({required this.client});

  final ApiClient client;

  @override
  Future<DriverActivity> getTodayActivity() async {
    final response = await client.get('/drivers/me/earnings');
    final data = response.asMap;

    return DriverActivity(
      completedRides: (data['completedRides'] as num?)?.toInt() ?? 0,
      // The dashboard summary is today's picture; the backend also returns a
      // lifetime total, which this model deliberately does not carry.
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

  /// Requests a withdrawal from the driver's wallet.
  ///
  /// The destination is explicit (`destinationType` + optional account) and the
  /// key must be stable across retries of the same logical request: the backend
  /// resolves it to the original withdrawal rather than creating a second one.
  @override
  Future<DriverWithdrawal> requestWithdrawal({
    required double amountEtb,
    required WithdrawalDestinationType destinationType,
    String? destination,
    String? destinationAccount,
    String? provider,
    required String idempotencyKey,
  }) async {
    final amountMinor = (amountEtb * 100).round();
    if (amountMinor <= 0) {
      throw ArgumentError.value(amountEtb, 'amountEtb', 'must be positive');
    }

    final response = await client.post(
      '/drivers/me/withdrawals',
      idempotencyKey: idempotencyKey,
      body: {
        'amount': amountMinor,
        'destinationType': destinationType.apiValue,
        'destination': ?destination,
        'destinationAccount': ?destinationAccount,
        'provider': ?provider,
        'idempotencyKey': idempotencyKey,
      },
    );

    return _withdrawalFromJson(response.asMap);
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

  static DriverWithdrawal _withdrawalFromJson(Map<String, dynamic> data) {
    return DriverWithdrawal(
      id: _string(data['id']) ?? '',
      amountMinor: (data['amount'] as num?)?.toInt() ?? 0,
      currency: _string(data['currency']) ?? 'ETB',
      status: (_string(data['status']) ?? 'PENDING').toUpperCase(),
      destinationType: switch (_string(data['destinationType'])) {
        'BANK' => WithdrawalDestinationType.bank,
        'MOBILE_MONEY' => WithdrawalDestinationType.mobileMoney,
        _ => null,
      },
      destination: _string(data['destination']),
      createdAt: DateTime.tryParse(_string(data['createdAt']) ?? ''),
    );
  }

  static String? _string(Object? value) =>
      value is String && value.isNotEmpty ? value : null;
}
