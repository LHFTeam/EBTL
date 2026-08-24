// Pickup orders are never charged a delivery fee, and a "Delivery fee EGP 0.00"
// line is just something the customer has to read and dismiss. Both order
// summaries drop the line when the fee is zero and keep it when there is one.

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:google_fonts/google_fonts.dart';

import 'package:ebtl_customer_app/features/cart/cart_screen.dart';
import 'package:ebtl_customer_app/features/checkout/checkout_screen.dart';
import 'package:ebtl_customer_app/models/cart_models.dart';
import 'package:ebtl_customer_app/models/checkout_models.dart';

CartTotals cartTotals({required double deliveryFee}) {
  return CartTotals(
    subtotalIncVat: 400,
    estimatedVatAmount: 55.17,
    discountAmount: 0,
    deliveryFee: deliveryFee,
    totalAmount: 400 + deliveryFee,
    currency: 'EGP',
  );
}

CheckoutSummary checkoutSummary({required double deliveryFee}) {
  return CheckoutSummary(
    subtotalExVat: 344.83,
    vatAmount: 55.17,
    subtotalIncVat: 400,
    discountAmount: 0,
    referralDiscountAmount: 0,
    creditApplied: 0,
    deliveryFee: deliveryFee,
    totalAmount: 400 + deliveryFee,
    currency: 'EGP',
    vatIncluded: true,
  );
}

Future<void> pumpCart(WidgetTester tester, double deliveryFee) {
  return tester.pumpWidget(
    MaterialApp(
      home: Scaffold(
        body: SingleChildScrollView(
          child: CartOrderSummaryCard(
            totals: cartTotals(deliveryFee: deliveryFee),
            checkoutReadiness: const CheckoutReadiness(
              canCheckout: true,
              blockingReasons: [],
            ),
            onCheckout: () {},
          ),
        ),
      ),
    ),
  );
}

Future<void> pumpCheckout(WidgetTester tester, double deliveryFee) {
  return tester.pumpWidget(
    MaterialApp(
      home: Scaffold(
        body: SingleChildScrollView(
          child: CheckoutSummaryCard(
            summary: checkoutSummary(deliveryFee: deliveryFee),
            promotion: null,
            canPlaceOrder: true,
            isPlacingOrder: false,
            onPlaceOrder: () {},
          ),
        ),
      ),
    ),
  );
}

void main() {
  setUpAll(() => GoogleFonts.config.allowRuntimeFetching = false);

  group('CartOrderSummaryCard', () {
    testWidgets('hides the delivery fee line when there is no fee', (
      tester,
    ) async {
      await pumpCart(tester, 0);

      expect(find.text('Delivery Fee'), findsNothing);
    });

    testWidgets('shows the delivery fee line when there is a fee', (
      tester,
    ) async {
      await pumpCart(tester, 45);

      expect(find.text('Delivery Fee'), findsOneWidget);
    });
  });

  group('CheckoutSummaryCard', () {
    testWidgets('hides the delivery fee line when there is no fee', (
      tester,
    ) async {
      await pumpCheckout(tester, 0);

      expect(find.text('Delivery fee'), findsNothing);
      expect(find.text('Subtotal'), findsOneWidget);
    });

    testWidgets('shows the delivery fee line when there is a fee', (
      tester,
    ) async {
      await pumpCheckout(tester, 45);

      expect(find.text('Delivery fee'), findsOneWidget);
    });
  });
}
