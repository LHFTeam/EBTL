// Parsing tests for the parts of the place-order response the confirmation
// screen is built from.
//
// All of this was already on the wire and silently dropped by the models before
// the confirmation redesign, so these exist to keep it from being dropped again:
// a field that stops parsing does not throw, it just renders an empty receipt.

import 'package:flutter_test/flutter_test.dart';

import 'package:ebtl_customer_app/models/checkout_models.dart';

void main() {
  group('CheckoutOrder', () {
    test('reads the beach cart and ready-by time the order recorded', () {
      final order = CheckoutOrder.fromJson({
        'id': 'order-1',
        'order_number': 'EBTL-1001',
        'status': 'confirmed',
        'payment_status': 'paid',
        'fulfillment_type': 'pickup_at_cart',
        'requested_fulfillment_at': '2026-08-16T15:30:00Z',
        'location': {
          'id': 'loc-1',
          'name': 'Hacienda Bay Cart',
          'compound_name': 'Hacienda Bay',
          'beach_name': 'North Beach',
        },
        'totals': {'total_amount': 150, 'currency': 'EGP'},
      });

      expect(order.requestedFulfillmentAt, '2026-08-16T15:30:00Z');
      expect(order.location?.name, 'Hacienda Bay Cart');
      expect(order.location?.subtitle, contains('Hacienda Bay'));
      expect(order.isDelivery, isFalse);
    });

    test('a delivery order is recognised as one', () {
      final order = CheckoutOrder.fromJson({
        'id': 'order-2',
        'fulfillment_type': 'delivery_to_unit',
        'address': 'Villa 42, Hacienda Bay',
      });

      expect(order.isDelivery, isTrue);
      expect(order.address, 'Villa 42, Hacienda Bay');
    });

    test('an older payload without a location or ready-by still parses', () {
      final order = CheckoutOrder.fromJson({
        'id': 'order-3',
        'order_number': 'EBTL-1003',
        'payment_status': 'paid',
      });

      expect(order.location, isNull);
      expect(order.requestedFulfillmentAt, isNull);
      expect(order.hasTotals, isFalse);
    });
  });

  group('PlacedOrderItem', () {
    test('reads the stored snapshots, not the live product fields', () {
      // The backend hands back the inserted order_items rows verbatim, so the
      // names carry the _snapshot suffix and the prices are what was charged.
      final response = PlaceOrderResponse.fromJson({
        'order': {'id': 'order-1', 'payment_status': 'paid'},
        'payment': <String, dynamic>{},
        'nextScreen': 'order_confirmed',
        'items': [
          {
            'id': 'item-1',
            'product_name_snapshot': 'Espresso Martini Kit',
            'variant_name_snapshot': 'Serves 4',
            'quantity': 2,
            'unit_price_inc_vat_snapshot': 320.0,
            'line_total': 640.0,
            'customization_summary': 'No sugar syrup',
          },
        ],
      });

      expect(response.items, hasLength(1));

      final item = response.items.single;
      expect(item.productName, 'Espresso Martini Kit');
      expect(item.variantName, 'Serves 4');
      expect(item.quantity, 2);
      expect(item.unitPriceIncVat, 320.0);
      expect(item.lineTotal, 640.0);
      expect(item.customizationSummary, 'No sugar syrup');
      expect(item.hasVariant, isTrue);
      expect(item.hasCustomization, isTrue);
      expect(item.lineTotalLabel('EGP'), contains('640'));
    });

    test('an item with no variant or customisation says so', () {
      final item = PlacedOrderItem.fromJson({
        'id': 'item-2',
        'product_name_snapshot': 'Ice Bag',
        'quantity': 1,
        'line_total': 30.0,
      });

      expect(item.hasVariant, isFalse);
      expect(item.hasCustomization, isFalse);
    });

    test('a response with no items is a normal state, not an error', () {
      // The idempotent replay of place-order — a customer retrying after
      // dismissing the payment sheet — comes back without any lines.
      final response = PlaceOrderResponse.fromJson({
        'order': {'id': 'order-1'},
        'payment': <String, dynamic>{},
        'nextScreen': 'order_confirmed',
      });

      expect(response.items, isEmpty);
    });
  });
}
