// Covers what the order detail screen decides from an order's payload — whether
// it offers to finish or cancel the payment — the beach-cart status lines the
// cart card splits, and the "Recently viewed" snapshot Home draws its rail from.

import 'package:flutter_test/flutter_test.dart';

import 'package:ebtl_customer_app/features/cart/cart_screen.dart';
import 'package:ebtl_customer_app/models/order_detail_models.dart';
import 'package:ebtl_customer_app/models/recently_viewed.dart';

OrderDetail orderWith({required String status, required String paymentStatus}) {
  return OrderDetail.fromJson({
    'id': 'ord_1',
    'order_number': 'EBTL-1001',
    'status': status,
    'payment_status': paymentStatus,
    'fulfillment_type': 'pickup_at_cart',
  });
}

void main() {
  group('OrderDetail.awaitsPayment', () {
    test('an order placed but never paid for can still be paid or cancelled', () {
      for (final paymentStatus in ['unpaid', 'pending', 'failed']) {
        expect(
          orderWith(
            status: 'pending_payment',
            paymentStatus: paymentStatus,
          ).awaitsPayment,
          isTrue,
          reason: 'payment_status $paymentStatus is money that never arrived',
        );
      }
    });

    test('an order that has been paid for offers neither', () {
      expect(
        orderWith(status: 'confirmed', paymentStatus: 'paid').awaitsPayment,
        isFalse,
      );
    });

    test('a payment status the app does not know is never assumed unpaid', () {
      expect(
        orderWith(
          status: 'pending_payment',
          paymentStatus: 'authorized',
        ).awaitsPayment,
        isFalse,
      );
    });

    test('an order the backend has closed is left alone', () {
      for (final status in ['expired', 'cancelled', 'completed']) {
        expect(
          orderWith(status: status, paymentStatus: 'unpaid').awaitsPayment,
          isFalse,
          reason: '$status orders cannot be paid for from the app',
        );
      }
    });
  });

  group('OrderDetailItem', () {
    // The line's artwork comes from the product the backend joins onto the
    // order item; without it the page draws the local placeholder asset for
    // every cocktail it lists.
    test('draws the artwork the order line was answered with', () {
      final item = OrderDetailItem.fromJson({
        'id': 'oi_1',
        'product_name_snapshot': 'Classic Mojito',
        'quantity': 2,
        'unit_price_inc_vat_snapshot': 320.0,
        'image_url': 'https://cdn.example.com/mojito.jpg',
      });

      expect(item.imageUrl, 'https://cdn.example.com/mojito.jpg');
      expect(item.imageAsset, 'assets/images/mojito.jpg');
    });

    test('falls back to the local asset when the product carries no image', () {
      final item = OrderDetailItem.fromJson({
        'id': 'oi_2',
        'product_name_snapshot': 'Beach Towel',
        'quantity': 1,
        'unit_price_inc_vat_snapshot': 120.0,
        'image_url': null,
      });

      expect(item.imageUrl, isNull);
      expect(item.imageAsset, 'assets/images/cocktail_placeholder.jpg');
    });
  });

  group('beachCartStatusLines', () {
    test('splits the state from the hours', () {
      expect(beachCartStatusLines('Open now · Closes at 11:00 PM'), [
        'Open now',
        'Closes at 11:00 PM',
      ]);
    });

    test('a label without hours stays on one line', () {
      expect(beachCartStatusLines('Closed now'), ['Closed now']);
    });

    test('a missing label falls back rather than rendering nothing', () {
      expect(beachCartStatusLines(null), ['Hours unavailable']);
      expect(beachCartStatusLines('   '), ['Hours unavailable']);
      expect(beachCartStatusLines(' · '), ['Hours unavailable']);
    });
  });

  group('RecentlyViewedProduct', () {
    test('round-trips through the stored JSON', () {
      const product = RecentlyViewedProduct(
        slug: 'mojito',
        name: 'Mojito',
        imageUrl: 'https://cdn.example/mojito.jpg',
        imageAsset: 'assets/images/cocktail_placeholder.jpg',
        priceLabel: 'EGP 120',
        isCocktail: true,
      );

      final restored = RecentlyViewedProduct.fromJson(product.toJson());

      expect(restored.slug, 'mojito');
      expect(restored.name, 'Mojito');
      expect(restored.imageUrl, 'https://cdn.example/mojito.jpg');
      expect(restored.imageAsset, 'assets/images/cocktail_placeholder.jpg');
      expect(restored.priceLabel, 'EGP 120');
      expect(restored.isCocktail, isTrue);
    });

    test('a half-written entry still draws a card', () {
      final product = RecentlyViewedProduct.fromJson(const {'slug': 'mojito'});

      expect(product.slug, 'mojito');
      expect(product.name, 'Product');
      expect(product.imageUrl, isNull);
      expect(product.imageAsset, isNotEmpty);
      expect(product.isCocktail, isFalse);
    });
  });
}
