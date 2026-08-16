// Behavioural tests for the post-payment result screen.
//
// The key beta-launch guarantee: a payment that hasn't finished reconciling
// (webhook still in flight) is presented as "processing" with a way to
// re-check — never as a failure — so a customer who was charged is never told
// their payment failed.

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:google_fonts/google_fonts.dart';

import 'package:ebtl_customer_app/features/checkout/checkout_screen.dart';
import 'package:ebtl_customer_app/models/checkout_models.dart';

PaymentStatusResponse _status({
  required String orderStatus,
  required String paymentStatus,
}) {
  return PaymentStatusResponse.fromJson({
    'order_id': 'order-1',
    'order_number': 'EBTL-1001',
    'order_status': orderStatus,
    'payment_status': paymentStatus,
    'payment': const <String, dynamic>{},
  });
}

Widget _wrap(PaymentStatusResponse status) {
  return MaterialApp(
    home: CheckoutResultScreen(status: status, onDone: () {}),
  );
}

void main() {
  setUpAll(() {
    // Avoid runtime font fetching over the network during tests.
    GoogleFonts.config.allowRuntimeFetching = false;
  });

  testWidgets(
    'a still-processing payment is reassuring, not a failure, and can be re-checked',
    (tester) async {
      await tester.pumpWidget(
        _wrap(_status(orderStatus: 'pending', paymentStatus: 'processing')),
      );
      await tester.pump();

      expect(find.text('Payment Processing'), findsOneWidget);
      expect(find.text('Payment Failed'), findsNothing);
      // Customer-facing reassurance and a manual re-check are both present.
      expect(find.textContaining("won't be charged twice"), findsOneWidget);
      expect(find.text('Check Again'), findsOneWidget);
    },
  );

  testWidgets('a confirmed payment is terminal with no re-check', (
    tester,
  ) async {
    await tester.pumpWidget(
      _wrap(_status(orderStatus: 'confirmed', paymentStatus: 'paid')),
    );
    await tester.pump();

    expect(find.text('Order Confirmed'), findsOneWidget);
    expect(find.text('Check Again'), findsNothing);
    expect(find.text('Done'), findsOneWidget);
  });

  testWidgets('a failed payment is terminal with no re-check', (tester) async {
    await tester.pumpWidget(
      _wrap(_status(orderStatus: 'cancelled', paymentStatus: 'failed')),
    );
    await tester.pump();

    expect(find.text('Payment Failed'), findsOneWidget);
    expect(find.text('Check Again'), findsNothing);
    expect(find.text('Done'), findsOneWidget);
  });
}
