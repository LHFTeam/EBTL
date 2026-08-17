// The delivery option is taller than pickup — it carries a "Coming soon" chip —
// so the row has to stretch both tiles to the same height. Without that the
// selected pill sits centred inside a taller row and the white space above and
// below it reads as thicker than the inset on the sides.

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:google_fonts/google_fonts.dart';

import 'package:ebtl_customer_app/core/constants/fulfillment_types.dart';
import 'package:ebtl_customer_app/features/cart/cart_screen.dart';

/// The container pads by 5 and draws a 1px border, so the pill sits 6 from the
/// outer edge on every side.
const double _inset = 6;

Future<Rect> pumpToggle(WidgetTester tester) async {
  await tester.pumpWidget(
    MaterialApp(
      home: Scaffold(
        body: CartFulfillmentToggle(
          fulfillmentType: FulfillmentTypes.pickupAtCart,
          onChanged: (_) {},
        ),
      ),
    ),
  );

  return tester.getRect(
    find.descendant(
      of: find.byType(CartFulfillmentToggle),
      matching: find.byType(Container),
    ).first,
  );
}

void main() {
  setUpAll(() => GoogleFonts.config.allowRuntimeFetching = false);

  group('CartFulfillmentToggle', () {
    testWidgets('insets the selected pill evenly on all four sides', (
      tester,
    ) async {
      final shell = await pumpToggle(tester);
      final pill = tester.getRect(find.byType(AnimatedContainer).first);

      expect(pill.top - shell.top, closeTo(_inset, 0.01));
      expect(shell.bottom - pill.bottom, closeTo(_inset, 0.01));
      expect(pill.left - shell.left, closeTo(_inset, 0.01));
    });

    testWidgets('gives both options the same height', (tester) async {
      await pumpToggle(tester);

      final tiles = tester
          .widgetList<AnimatedContainer>(find.byType(AnimatedContainer))
          .toList();
      expect(tiles.length, 2);

      final heights = find
          .byType(AnimatedContainer)
          .evaluate()
          .map((element) => tester.getRect(find.byWidget(element.widget)).height)
          .toSet();
      expect(heights.length, 1);
    });
  });
}
