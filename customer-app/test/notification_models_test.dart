// Model tests for the in-app notification payloads. The backend payload is
// treated as untrusted, so the fromJson factories must survive missing and
// mistyped fields with safe defaults.

import 'package:flutter_test/flutter_test.dart';

import 'package:ebtl_customer_app/models/notification_models.dart';

void main() {
  group('CustomerNotification.fromJson', () {
    test('parses a full payload', () {
      final notification = CustomerNotification.fromJson(const {
        'id': 'ntf_1',
        'type': 'order_ready',
        'title': 'Order ready',
        'body': 'Your kit is waiting at the cart.',
        'data': {'order_id': 'ord_1'},
        'order_id': 'ord_1',
        'order_number': 'EBTL-1042',
        'read_at': '2026-07-20T10:00:00Z',
        'created_at': '2026-07-20T09:00:00Z',
      });

      expect(notification.id, 'ntf_1');
      expect(notification.type, 'order_ready');
      expect(notification.title, 'Order ready');
      expect(notification.body, 'Your kit is waiting at the cart.');
      expect(notification.data, {'order_id': 'ord_1'});
      expect(notification.orderId, 'ord_1');
      expect(notification.orderNumber, 'EBTL-1042');
      expect(notification.isUnread, isFalse);
    });

    test('falls back safely on an empty payload', () {
      final notification = CustomerNotification.fromJson(const {});

      expect(notification.id, '');
      expect(notification.type, '');
      expect(notification.title, 'EBTL update');
      expect(notification.body, '');
      expect(notification.data, isEmpty);
      expect(notification.orderId, isNull);
      expect(notification.orderNumber, isNull);
      expect(notification.readAt, isNull);
      expect(notification.createdAt, isNull);
    });

    test('isUnread is true only while read_at is null', () {
      final unread = CustomerNotification.fromJson(const {'id': 'a'});
      final read = CustomerNotification.fromJson(const {
        'id': 'b',
        'read_at': '2026-07-20T10:00:00Z',
      });

      expect(unread.isUnread, isTrue);
      expect(read.isUnread, isFalse);
    });

    test('blank read_at strings count as unread', () {
      final notification = CustomerNotification.fromJson(const {
        'id': 'a',
        'read_at': '   ',
      });

      expect(notification.isUnread, isTrue);
    });

    test('createdAtLabel falls back when created_at is missing', () {
      final notification = CustomerNotification.fromJson(const {'id': 'a'});

      expect(notification.createdAtLabel, 'Time unavailable');
    });
  });

  group('CustomerNotificationsResponse.fromJson', () {
    test('parses notifications and unread_count', () {
      final response = CustomerNotificationsResponse.fromJson(const {
        'notifications': [
          {'id': 'ntf_1', 'title': 'One'},
          {'id': 'ntf_2', 'title': 'Two'},
        ],
        'unread_count': 2,
      });

      expect(response.notifications, hasLength(2));
      expect(response.notifications.first.id, 'ntf_1');
      expect(response.unreadCount, 2);
    });

    test('falls back safely on an empty payload', () {
      final response = CustomerNotificationsResponse.fromJson(const {});

      expect(response.notifications, isEmpty);
      expect(response.unreadCount, 0);
    });

    test('survives mistyped fields', () {
      final response = CustomerNotificationsResponse.fromJson(const {
        'notifications': 'not-a-list',
        'unread_count': '3',
      });

      expect(response.notifications, isEmpty);
      expect(response.unreadCount, 3);
    });
  });
}
