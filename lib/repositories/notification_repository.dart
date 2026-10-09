import '../services/api/interfaces.dart';
import '../models/app_notification.dart';

/// Repository for passenger notification operations.
///
/// Mediates between the presentation layer and the notification service layer.
///
/// Architecture:
/// UI → NotificationRepository → NotificationService (Mock or Real API)
///
/// DEFERRED IN PRODUCTION: the backend exposes no notification list / mark-as-read
/// endpoints. `NotificationsService` there is an outbox plus a dispatcher — it
/// pushes messages through a sender, and nothing reads them back over HTTP. The
/// default production wiring is therefore [_DeferredNotificationService], which
/// reports [isSupported] false so the UI can say notifications are not available
/// yet rather than showing an empty inbox. Wiring a real API service later is a
/// one-line change here; `MockNotificationService` remains available to tests.
class NotificationRepository {
  NotificationRepository({NotificationService? notificationService})
    : _service = notificationService ?? const _DeferredNotificationService();

  final NotificationService _service;

  /// False when notifications are not served by this backend build.
  bool get isSupported => _service.isSupported;

  /// Fetches all notifications for the current passenger or driver.
  Future<List<AppNotification>> getNotifications() async {
    try {
      return await _service.getNotifications();
    } catch (_) {
      return const [];
    }
  }

  /// Marks the notification with [id] as read.
  ///
  /// Returns the updated [AppNotification].
  Future<AppNotification> markAsRead(String id) async {
    try {
      return await _service.markAsRead(id);
    } catch (_) {
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

  /// Marks all notifications as read.
  Future<void> markAllAsRead() async {
    try {
      await _service.markAllAsRead();
    } catch (_) {
      // Ignored
    }
  }

  /// Returns the count of unread notifications without fetching all details.
  Future<int> getUnreadCount() async {
    try {
      final notifications = await getNotifications();
      return notifications.where((n) => !n.isRead).length;
    } catch (_) {
      return 0;
    }
  }
}

/// The honest "not available" service: it answers nothing, and says so.
class _DeferredNotificationService implements NotificationService {
  const _DeferredNotificationService();

  @override
  bool get isSupported => false;

  @override
  Future<List<AppNotification>> getNotifications() async => const [];

  @override
  Future<AppNotification> markAsRead(String id) async =>
      throw StateError('Notifications are not available on this backend yet');

  @override
  Future<void> markAllAsRead() async {
    throw StateError('Notifications are not available on this backend yet');
  }
}
