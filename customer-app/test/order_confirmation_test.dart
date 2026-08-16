// Behavioural tests for the order confirmation screen.
//
// Two jobs are being protected here. The first is that a customer who has just
// paid can see what they paid for and where it lands — the receipt and the
// fulfilment copy, which differ for pickup and delivery. The second is that the
// sign-in card sells the account without ever standing between the customer and
// their order: it can always be dismissed, and the screen is complete without it.
//
// Per AGENTS.md the harness gets a plain ThemeData — building the full Manrope
// text theme deadlocks `flutter test` while it fetches fonts.

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:google_fonts/google_fonts.dart';

import 'package:ebtl_customer_app/features/checkout/order_confirmed_screen.dart';
import 'package:ebtl_customer_app/models/checkout_models.dart';

CheckoutOrder _order({
  String fulfillmentType = 'pickup_at_cart',
  String paymentStatus = 'paid',
  Map<String, dynamic>? location,
  String? address,
  Map<String, dynamic>? totals,
}) {
  return CheckoutOrder.fromJson({
    'id': 'order-1',
    'order_number': 'EBTL-1001',
    'status': 'confirmed',
    'payment_status': paymentStatus,
    'fulfillment_type': fulfillmentType,
    'address': address,
    'location': location,
    'totals':
        totals ??
        {
          'subtotal_inc_vat': 640.0,
          'discount_amount': 40.0,
          'delivery_fee': 0.0,
          'total_amount': 600.0,
          'currency': 'EGP',
          'vat_included': true,
        },
  });
}

List<PlacedOrderItem> _items() {
  return [
    PlacedOrderItem.fromJson({
      'id': 'item-1',
      'product_name_snapshot': 'Espresso Martini Kit',
      'variant_name_snapshot': 'Serves 4',
      'quantity': 2,
      'line_total': 640.0,
      'customization_summary': 'No sugar syrup',
    }),
  ];
}

Widget _wrap(
  CheckoutOrder order, {
  List<PlacedOrderItem> items = const [],
  ScrollController? primaryScrollController,
  VoidCallback? onDone,
}) {
  return MaterialApp(
    theme: ThemeData(),
    builder: (context, child) {
      if (primaryScrollController == null) return child!;
      return PrimaryScrollController(
        controller: primaryScrollController,
        child: child!,
      );
    },
    home: OrderConfirmedScreen(
      order: order,
      items: items,
      onDone: onDone ?? () {},
    ),
  );
}

void main() {
  setUpAll(() {
    // Avoid runtime font fetching over the network during tests.
    GoogleFonts.config.allowRuntimeFetching = false;
  });

  // The screen is a tall scroll view, and everything below the receipt is off a
  // phone-sized surface. Give the tests a surface tall enough to hold the whole
  // page so a `findsOneWidget` is about the widget existing, not about where it
  // happened to land.
  Future<void> pumpScreen(WidgetTester tester, Widget app) async {
    await tester.binding.setSurfaceSize(const Size(390, 2400));
    addTearDown(() => tester.binding.setSurfaceSize(null));
    await tester.pumpWidget(app);
    await tester.pump();
  }

  testWidgets('opens at the top rather than scrolled to the action', (
    tester,
  ) async {
    final inheritedController = ScrollController(initialScrollOffset: 1000);
    addTearDown(inheritedController.dispose);

    await tester.binding.setSurfaceSize(const Size(390, 844));
    addTearDown(() => tester.binding.setSurfaceSize(null));
    await tester.pumpWidget(
      _wrap(_order(), primaryScrollController: inheritedController),
    );
    await tester.pump();

    expect(find.text('Order Confirmed'), findsOneWidget);
    expect(find.text('Track my order').hitTestable(), findsNothing);
  });

  testWidgets('shows what was bought and what it came to', (tester) async {
    await pumpScreen(tester, _wrap(_order(), items: _items()));

    expect(find.text('Espresso Martini Kit'), findsOneWidget);
    expect(find.text('Serves 4'), findsOneWidget);
    expect(find.text('No sugar syrup'), findsOneWidget);
    expect(find.text('2×'), findsOneWidget);
    expect(find.text('1 item'), findsOneWidget);

    // The totals breakdown, not just the headline number.
    expect(find.text('Subtotal'), findsOneWidget);
    expect(find.text('Total'), findsOneWidget);
    expect(find.text('VAT included'), findsOneWidget);
  });

  testWidgets('an order with no lines still renders, without a receipt', (
    tester,
  ) async {
    // The idempotent replay of place-order returns no items. The screen has to
    // stay complete rather than showing an empty receipt card.
    await pumpScreen(tester, _wrap(_order()));

    expect(find.text('Order Confirmed'), findsOneWidget);
    expect(find.text('Subtotal'), findsNothing);
  });

  group('fulfilment', () {
    testWidgets('a pickup order names the beach cart', (tester) async {
      await pumpScreen(
        tester,
        _wrap(
          _order(
            location: {
              'id': 'loc-1',
              'name': 'Hacienda Bay Cart',
              'compound_name': 'Hacienda Bay',
              'beach_name': 'North Beach',
            },
          ),
        ),
      );

      expect(find.text('Pick up from'), findsOneWidget);
      expect(find.text('Hacienda Bay Cart'), findsOneWidget);
      expect(
        find.textContaining('ready at Hacienda Bay Cart'),
        findsOneWidget,
      );
      expect(find.text('Delivering to'), findsNothing);
    });

    testWidgets('a delivery order reads back the address instead', (
      tester,
    ) async {
      await pumpScreen(
        tester,
        _wrap(
          _order(
            fulfillmentType: 'delivery_to_unit',
            address: 'Villa 42, Hacienda Bay',
          ),
        ),
      );

      expect(find.text('Delivering to'), findsOneWidget);
      expect(find.text('Villa 42, Hacienda Bay'), findsOneWidget);
      expect(
        find.textContaining('on the way to Villa 42, Hacienda Bay'),
        findsOneWidget,
      );
      // The old screen told delivery customers to come and collect.
      expect(find.text('Pick up from'), findsNothing);
    });

    testWidgets('an unscheduled order says as soon as possible', (tester) async {
      await pumpScreen(tester, _wrap(_order()));

      expect(find.text('As soon as possible'), findsOneWidget);
    });
  });

  group('sign-in card', () {
    testWidgets('sells the four things an account keeps', (tester) async {
      await pumpScreen(tester, _wrap(_order()));

      expect(find.text('Keep this order'), findsOneWidget);
      expect(find.text('Your order history'), findsOneWidget);
      expect(find.text('Your spirits and favourites'), findsOneWidget);
      expect(find.text('Loyalty points'), findsOneWidget);
      expect(find.text('Your referral bonuses'), findsOneWidget);
      expect(find.text('Continue with Facebook'), findsOneWidget);
    });

    testWidgets('can be dismissed, and dismissing it keeps the order', (
      tester,
    ) async {
      await pumpScreen(tester, _wrap(_order(), items: _items()));

      await tester.tap(find.text('Not now'));
      await tester.pump();

      expect(find.text('Keep this order'), findsNothing);
      // The order itself is untouched — this is the whole point of asking here.
      expect(find.text('Order Confirmed'), findsOneWidget);
      expect(find.text('Espresso Martini Kit'), findsOneWidget);
    });
  });

  testWidgets('the referral strip stays hidden when the hub cannot be read', (
    tester,
  ) async {
    // Under `flutter test` the referral fetch fails at the secure-storage
    // channel. That is the same path a backend outage takes, and neither may
    // put an error in front of somebody who has just paid.
    await pumpScreen(tester, _wrap(_order()));

    expect(find.textContaining('Share EBTL'), findsNothing);
    expect(find.byType(SnackBar), findsNothing);
  });

  testWidgets('a payment still settling is not presented as confirmed', (
    tester,
  ) async {
    await pumpScreen(tester, _wrap(_order(paymentStatus: 'pending')));

    expect(find.text('Order Placed'), findsOneWidget);
    expect(find.text('Order Confirmed'), findsNothing);
    expect(find.text('Pending'), findsOneWidget);
  });
}
