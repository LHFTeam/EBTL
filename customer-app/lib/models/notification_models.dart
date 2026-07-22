import '../core/utils/formatters.dart';
import '../core/utils/json_helpers.dart';

/// Payload of `GET /api/customer/notifications`.
class CustomerNotificationsResponse {
  final List<CustomerNotification> notifications;
  final int unreadCount;

  const CustomerNotificationsResponse({
    required this.notifications,
    required this.unreadCount,
  });

  factory CustomerNotificationsResponse.fromJson(Map<String, dynamic> json) {
    return CustomerNotificationsResponse(
      notifications: readMapList(
        json['notifications'],
      ).map(CustomerNotification.fromJson).toList(),
      unreadCount: readInt(json['unread_count']),
    );
  }
}

/// A single in-app notification (order updates, pickup alerts, etc.).
/// A null `read_at` means the notification is unread.
class CustomerNotification {
  final String id;
  final String type;
  final String title;
  final String body;
  final Map<String, dynamic> data;
  final String? orderId;
  final String? orderNumber;
  final String? readAt;
  final String? createdAt;

  const CustomerNotification({
    required this.id,
    required this.type,
    required this.title,
    required this.body,
    required this.data,
    required this.orderId,
    required this.orderNumber,
    required this.readAt,
    required this.createdAt,
  });

  factory CustomerNotification.fromJson(Map<String, dynamic> json) {
    return CustomerNotification(
      id: readString(json['id']),
      type: readString(json['type']),
      title: readString(json['title'], fallback: 'EBTL update'),
      body: readString(json['body']),
      data: asMap(json['data']),
      orderId: nullableString(json['order_id']),
      orderNumber: nullableString(json['order_number']),
      readAt: nullableString(json['read_at']),
      createdAt: nullableString(json['created_at']),
    );
  }

  bool get isUnread => readAt == null;

  String get createdAtLabel => formatProfileDateTime(createdAt);
}
