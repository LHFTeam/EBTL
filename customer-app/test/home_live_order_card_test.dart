// The live-order card is the tracker Home leads with while an order is being
// made. It shows the order's own status, not a legend of every stage, and its
// progress bar has to follow the order as staff move it along.

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:google_fonts/google_fonts.dart';

import 'package:ebtl_customer_app/features/home/widgets/home_modules.dart';
import 'package:ebtl_customer_app/models/profile_models.dart';

ProfileOrder orderWithStatus(String status) {
  return ProfileOrder.fromJson({
    'id': 'o1',
    'order_number': 'EBTL-1001',
    'status': status,
    'status_label': status,
    'payment_status': 'paid',
    'payment_status_label': 'Paid',
    'fulfillment_type': 'pickup_at_cart',
    'total_amount': 450,
    'currency': 'EGP',
    'item_count': 1,
    'total_quantity': 1,
    'location_name': 'Hacienda Bay',
    'primary_item': {'name': 'Piña Colada Kit', 'quantity': 1},
  });
}

Widget wrap(Widget child) {
  return MaterialApp(home: Scaffold(body: child));
}

void main() {
  setUpAll(() => GoogleFonts.config.allowRuntimeFetching = false);

  testWidgets('the card carries no stage legend', (tester) async {
    await tester.pumpWidget(
      wrap(HomeLiveOrderCard(order: orderWithStatus('preparing'), onTap: () {})),
    );

    expect(find.text('Paid · Mixing · Ready · Collected'), findsNothing);
    expect(find.textContaining('Mixing', findRichText: true), findsNothing);
    expect(find.text('Track order'), findsOneWidget);
  });

  testWidgets('the card follows the order it is given', (tester) async {
    await tester.pumpWidget(
      wrap(HomeLiveOrderCard(order: orderWithStatus('confirmed'), onTap: () {})),
    );
    expect(find.text('ORDER CONFIRMED'), findsOneWidget);

    // A rebuild with the updated order — what a background refresh does — has
    // to repaint the card rather than leave the old status behind.
    await tester.pumpWidget(
      wrap(HomeLiveOrderCard(order: orderWithStatus('ready'), onTap: () {})),
    );
    expect(find.text('ORDER CONFIRMED'), findsNothing);
    expect(find.text('READY FOR COLLECTION'), findsOneWidget);
  });
}
