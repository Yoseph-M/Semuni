/// App notification model.
///
/// Used by both passenger and driver notification screens.
/// Platform-agnostic — no UI logic here.
class AppNotification {
  const AppNotification({
    required this.id,
    required this.title,
    required this.body,
    required this.type,
    required this.createdAt,
    this.isRead = false,
  });

  final String id;
  final String title;
  final String body;
  final NotificationType type;
  final DateTime createdAt;
  final bool isRead;

  AppNotification copyWith({
    String? id,
    String? title,
    String? body,
    NotificationType? type,
    DateTime? createdAt,
    bool? isRead,
  }) {
    return AppNotification(
      id: id ?? this.id,
      title: title ?? this.title,
      body: body ?? this.body,
      type: type ?? this.type,
      createdAt: createdAt ?? this.createdAt,
      isRead: isRead ?? this.isRead,
    );
  }

  @override
  String toString() =>
      'AppNotification(id: $id, title: $title, isRead: $isRead)';
}

/// Categories of notifications SMUNI may display.
enum NotificationType {
  paymentReceived,
  rideCompleted,
  walletTopUp,
  routeUpdate,
  withdrawal,
  general,
}
