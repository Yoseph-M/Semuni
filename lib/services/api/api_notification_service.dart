import '../../core/network/api_client.dart';
import '../../models/app_notification.dart';
import 'interfaces.dart';

/// Reads the authenticated user's notification inbox from the backend.
class ApiNotificationService implements NotificationService {
  ApiNotificationService({
    required this.client,
    this.fallbackService,
  });

  final ApiClient client;
  final NotificationService? fallbackService;

  @override
  bool get isSupported => true;

  @override
  Future<List<AppNotification>> getNotifications() async {
    try {
      final response = await client.get('/notifications');
      final list = response.asMapList.map(_fromJson).toList(growable: false);
      if (list.isNotEmpty || fallbackService == null) {
        return list;
      }
      return await fallbackService!.getNotifications();
    } catch (_) {
      if (fallbackService != null) {
        return await fallbackService!.getNotifications();
      }
      return const [];
    }
  }

  @override
  Future<AppNotification> markAsRead(String id) async {
    try {
      final response = await client.patch('/notifications/$id/read');
      return _fromJson(response.asMap);
    } catch (_) {
      if (fallbackService != null) {
        return await fallbackService!.markAsRead(id);
      }
      return AppNotification(
        id: id,
        title: 'Notification',
        body: '',
        type: NotificationType.general,
        createdAt: DateTime.now(),
        isRead: true,
      );
    }
  }

  @override
  Future<void> markAllAsRead() async {
    try {
      await client.post('/notifications/read-all');
    } catch (_) {
      if (fallbackService != null) {
        await fallbackService!.markAllAsRead();
      }
    }
  }

  static AppNotification _fromJson(Map<String, dynamic> json) {
    final data = json['data'] is Map
        ? Map<String, dynamic>.from(json['data'] as Map)
        : const <String, dynamic>{};
    final rawType = (data['type'] ?? json['type'] ?? json['title'] ?? 'general')
        .toString()
        .toLowerCase();
    final type = switch (rawType) {
      'payment' ||
      'paymentreceived' ||
      'payment_received' => NotificationType.paymentReceived,
      'ridecompleted' || 'ride_completed' => NotificationType.rideCompleted,
      'wallettopup' ||
      'wallet_top_up' ||
      'topup' => NotificationType.walletTopUp,
      'routeupdate' || 'route_update' => NotificationType.routeUpdate,
      'withdrawal' => NotificationType.withdrawal,
      _ when rawType.contains('payment') || rawType.contains('earning') =>
        NotificationType.paymentReceived,
      _ when rawType.contains('withdraw') => NotificationType.withdrawal,
      _ when rawType.contains('route') => NotificationType.routeUpdate,
      _ => NotificationType.general,
    };
    final created =
        DateTime.tryParse('${json['createdAt'] ?? ''}') ?? DateTime.now();
    return AppNotification(
      id: '${json['id'] ?? ''}',
      title: '${json['title'] ?? 'Semuni update'}',
      body: '${json['body'] ?? ''}',
      type: type,
      createdAt: created,
      isRead: data['read'] == true || data['read'] == 'true',
    );
  }
}
