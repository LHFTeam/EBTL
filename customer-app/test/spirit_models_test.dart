// Model tests for the customer spirit profile payloads. The backend payload is
// treated as untrusted, so the fromJson factories must survive missing and
// mistyped fields with safe defaults.

import 'package:flutter_test/flutter_test.dart';

import 'package:ebtl_customer_app/models/profile_models.dart';
import 'package:ebtl_customer_app/models/spirit_models.dart';

void main() {
  group('ProfileSpirit.fromJson', () {
    test('parses a most-ordered entry', () {
      final spirit = ProfileSpirit.fromJson(const {
        'id': 'liq_gin',
        'name': 'Gin',
        'image_url': 'https://cdn.example/gin.png',
        'display_order': 2,
        'is_favorite': true,
        'order_count': 10,
        'rank': 1,
      });

      expect(spirit.id, 'liq_gin');
      expect(spirit.name, 'Gin');
      expect(spirit.imageUrl, 'https://cdn.example/gin.png');
      expect(spirit.displayOrder, 2);
      expect(spirit.isFavorite, isTrue);
      expect(spirit.orderCount, 10);
      expect(spirit.rank, 1);
      expect(spirit.orderCountLabel, 'In 10 orders');
    });

    test('reads the favorites payload, which carries no counts', () {
      final spirit = ProfileSpirit.fromJson(const {
        'id': 'liq_rum',
        'name': 'Rum',
        'is_favorite': true,
        'favorite_created_at': '2026-08-01T10:00:00Z',
      });

      expect(spirit.imageUrl, isNull);
      expect(spirit.orderCount, 0);
      expect(spirit.rank, 1);
      expect(spirit.orderCountLabel, '');
    });

    test('singularizes a one-order count', () {
      final spirit = ProfileSpirit.fromJson(const {
        'id': 'liq_tequila',
        'name': 'Tequila',
        'order_count': 1,
      });

      expect(spirit.orderCountLabel, 'In 1 order');
    });

    test('falls back safely on an empty payload', () {
      final spirit = ProfileSpirit.fromJson(const {});

      expect(spirit.name, 'Bottle');
      expect(spirit.id, 'Bottle');
      expect(spirit.isFavorite, isFalse);
      expect(spirit.orderCount, 0);
    });
  });

  group('ProfileSpirits.fromJson', () {
    final payload = <String, dynamic>{
      'favorite_spirits': {
        'title': 'My Spirits',
        'subtitle': 'The bottles you keep at hand',
        'count': 1,
        'items': [
          {'id': 'liq_gin', 'name': 'Gin', 'is_favorite': true},
        ],
      },
      'top_spirits': {
        'title': 'Most Ordered',
        'subtitle': 'Worked out from your order history',
        'places': 2,
        'computed_at': '2026-08-04T09:00:00Z',
        'items': [
          {'id': 'liq_gin', 'name': 'Gin', 'order_count': 10, 'rank': 1},
          {'id': 'liq_rum', 'name': 'Rum', 'order_count': 6, 'rank': 2},
          {'id': 'liq_vodka', 'name': 'Vodka', 'order_count': 6, 'rank': 2},
        ],
      },
      'available_spirits': [
        {'id': 'liq_gin', 'name': 'Gin', 'is_favorite': true},
        {'id': 'liq_rum', 'name': 'Rum', 'is_favorite': false},
        {'id': 'liq_vodka', 'name': 'Vodka', 'is_favorite': false},
      ],
    };

    test('parses all three lists', () {
      final spirits = ProfileSpirits.fromJson(payload);

      expect(spirits.favoriteSpirits.title, 'My Spirits');
      expect(spirits.favoriteSpirits.count, 1);
      expect(spirits.topSpirits.items, hasLength(3));
      expect(spirits.availableSpirits, hasLength(3));
    });

    test('keeps a second-place tie whole', () {
      final spirits = ProfileSpirits.fromJson(payload);
      final secondPlace = spirits.topSpirits.items
          .where((spirit) => spirit.rank == 2)
          .map((spirit) => spirit.name)
          .toList();

      expect(secondPlace, ['Rum', 'Vodka']);
    });

    test('addableSpirits drops what is already saved', () {
      final spirits = ProfileSpirits.fromJson(payload);

      expect(
        spirits.addableSpirits.map((spirit) => spirit.id),
        ['liq_rum', 'liq_vodka'],
      );
    });

    test('falls back safely on an empty payload', () {
      final spirits = ProfileSpirits.fromJson(const {});

      expect(spirits.favoriteSpirits.title, 'My Spirits');
      expect(spirits.favoriteSpirits.isEmpty, isTrue);
      expect(spirits.topSpirits.title, 'Most Ordered');
      expect(spirits.availableSpirits, isEmpty);
      expect(spirits.addableSpirits, isEmpty);
    });
  });

  group('CustomerProfileResponse.fromJson', () {
    test('carries the spirits block', () {
      final profile = CustomerProfileResponse.fromJson(const {
        'customer': {'id': 'cus_1'},
        'spirits': {
          'favorite_spirits': {
            'items': [
              {'id': 'liq_gin', 'name': 'Gin'},
            ],
          },
        },
      });

      expect(profile.spirits.favoriteSpirits.count, 1);
      expect(profile.spirits.favoriteSpirits.items.first.name, 'Gin');
    });

    test('survives a backend that has not shipped spirits yet', () {
      final profile = CustomerProfileResponse.fromJson(const {
        'customer': {'id': 'cus_1'},
      });

      expect(profile.spirits.favoriteSpirits.isEmpty, isTrue);
      expect(profile.spirits.topSpirits.isEmpty, isTrue);
    });
  });
}
