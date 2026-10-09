import '../../models/app_notification.dart';
import 'mock_notification_service.dart';

/// Mock implementation of [NotificationService] for Drivers.
///
/// Provides realistic semuni driver notification records for
/// frontend demonstration. Stores read state in memory for the session.
class MockDriverNotificationService implements NotificationService {
  MockDriverNotificationService({
    this.simulatedDelay = const Duration(milliseconds: 350),
  });

  /// Simulated latency to replicate real-world API behaviour.
  final Duration simulatedDelay;

  /// A stub can answer, so the screens render real (fixture) notifications.
  @override
  bool get isSupported => true;

  late final List<AppNotification> _notifications =
      _buildInitialNotifications();

  static List<AppNotification> _buildInitialNotifications() {
    final now = DateTime.now();
    return [
      AppNotification(
        id: 'd_notif_001',
        title: 'New route assigned',
        body: 'You have been assigned to the Bole → Piazza route.',
        type: NotificationType.routeUpdate,
        createdAt: DateTime(now.year, now.month, now.day, 8, 30),
        isRead: false,
      ),
      AppNotification(
        id: 'd_notif_002',
        title: 'Daily earnings updated',
        body:
            'Your earnings for today\'s completed journeys have been updated.',
        type: NotificationType.paymentReceived,
        createdAt: DateTime(now.year, now.month, now.day, 12, 15),
        isRead: false,
      ),
      AppNotification(
        id: 'd_notif_003',
        title: 'Withdrawal successful',
        body: 'Your withdrawal request has been processed successfully.',
        type: NotificationType.withdrawal,
        createdAt: DateTime(now.year, now.month, now.day - 1, 15, 45),
        isRead: false,
      ),
      AppNotification(
        id: 'd_notif_004',
        title: 'Transaction recorded',
        body: 'A new transaction has been added to your driver account.',
        type: NotificationType.paymentReceived,
        createdAt: DateTime(now.year, now.month, now.day - 1, 11, 20),
        isRead: true,
      ),
      AppNotification(
        id: 'd_notif_005',
        title: 'semuni update',
        body: 'Your driver account information has been updated.',
        type: NotificationType.general,
        createdAt: DateTime(now.year, now.month, now.day - 3, 10, 0),
        isRead: true,
      ),
    ];
  }

  @override
  Future<List<AppNotification>> getNotifications() async {
    if (simulatedDelay > Duration.zero) {
      await Future<void>.delayed(simulatedDelay);
    }
    return List.unmodifiable(_notifications);
  }

  @override
  Future<AppNotification> markAsRead(String id) async {
    if (simulatedDelay > Duration.zero) {
      await Future<void>.delayed(simulatedDelay);
    }
    final index = _notifications.indexWhere((n) => n.id == id);
    if (index == -1) {
      throw ArgumentError('Notification not found: $id');
    }
    final updated = _notifications[index].copyWith(isRead: true);
    _notifications[index] = updated;
    return updated;
  }

  @override
  Future<void> markAllAsRead() async {
    if (simulatedDelay > Duration.zero) {
      await Future<void>.delayed(simulatedDelay);
    }
    for (int i = 0; i < _notifications.length; i++) {
      _notifications[i] = _notifications[i].copyWith(isRead: true);
    }
  }
}
