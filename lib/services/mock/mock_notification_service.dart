import '../../models/app_notification.dart';
import '../api/interfaces.dart';

export '../api/interfaces.dart' show NotificationService;

/// Mock implementation of [NotificationService].
///
/// Provides realistic semuni passenger notification records for
/// frontend demonstration. Stores read state in memory for the session.
class MockNotificationService implements NotificationService {
  MockNotificationService({
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
        id: 'notif_001',
        title: 'Taxi payment completed',
        body:
            'Your ETB 85.00 taxi payment for the Bole → Piazza journey '
            'was processed successfully.',
        type: NotificationType.paymentReceived,
        createdAt: DateTime(now.year, now.month, now.day, 9, 14),
        isRead: false,
      ),
      AppNotification(
        id: 'notif_002',
        title: 'Journey recorded',
        body:
            'Your recent Bole → Piazza taxi journey has been added to '
            'your trip history.',
        type: NotificationType.rideCompleted,
        createdAt: DateTime(now.year, now.month, now.day, 9, 13),
        isRead: false,
      ),
      AppNotification(
        id: 'notif_003',
        title: 'Wallet top-up successful',
        body:
            'ETB 500.00 has been added to your semuni wallet. '
            'Your new balance is ETB 1,250.00.',
        type: NotificationType.walletTopUp,
        createdAt: DateTime(now.year, now.month, now.day - 1, 17, 30),
        isRead: false,
      ),
      AppNotification(
        id: 'notif_004',
        title: 'Taxi payment completed',
        body:
            'Your ETB 70.00 taxi payment for the Mexico → Saris journey '
            'was processed successfully.',
        type: NotificationType.paymentReceived,
        createdAt: DateTime(now.year, now.month, now.day - 1, 17, 22),
        isRead: true,
      ),
      AppNotification(
        id: 'notif_005',
        title: 'Route update',
        body:
            'Service on the Megenagna → CMC route is operating normally. '
            'Estimated fare: ETB 50.00.',
        type: NotificationType.routeUpdate,
        createdAt: DateTime(now.year, now.month, now.day - 2, 8, 0),
        isRead: true,
      ),
      AppNotification(
        id: 'notif_006',
        title: 'Welcome to semuni',
        body:
            'Find taxi routes and stations easily across Addis Ababa. '
            'Pay cashlessly for every journey.',
        type: NotificationType.general,
        createdAt: DateTime(now.year, now.month, now.day - 7, 12, 0),
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
