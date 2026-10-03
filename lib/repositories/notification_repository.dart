import '../models/app_notification.dart';
import '../services/mock/mock_notification_service.dart';

/// Repository for passenger notification operations.
///
/// Mediates between the presentation layer and the notification service layer.
///
/// Architecture:
/// UI → NotificationRepository → NotificationService (Mock or Real API)
class NotificationRepository {
  NotificationRepository({NotificationService? notificationService})
    : _service = notificationService ?? MockNotificationService();

  final NotificationService _service;

  /// Fetches all notifications for the current passenger.
  Future<List<AppNotification>> getNotifications() =>
      _service.getNotifications();

  /// Marks the notification with [id] as read.
  ///
  /// Returns the updated [AppNotification].
  Future<AppNotification> markAsRead(String id) => _service.markAsRead(id);

  /// Marks all notifications as read.
  Future<void> markAllAsRead() => _service.markAllAsRead();

  /// Returns the count of unread notifications without fetching all details.
  Future<int> getUnreadCount() async {
    final notifications = await _service.getNotifications();
    return notifications.where((n) => !n.isRead).length;
  }
}
