// Layout regressions for the cards that render backend-controlled text inside
// a box the layout does not let grow.
//
// Two shapes keep producing overflow stripes in this app, and both are covered
// here:
//
//   * a card whose artwork and text block are fixed boxes, dropped into a rail
//     or grid whose extent was hand-tuned and then drifted (the shop product
//     tile), or a fixed-height column that a rarely-populated optional line
//     pushes past (the cart line);
//   * a `Row` whose text child has no `Flexible`/`Expanded`, so a long name or
//     promo code runs off the edge instead of ellipsizing.
//
// Note on fonts: `flutter test` renders with a fixed-advance test font that is
// far wider than Manrope, so the width cases here are *stricter* than the real
// app, not looser. The height cases are driven by the fixed box sizes rather
// than by glyph metrics, so they measure the same either way.

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:google_fonts/google_fonts.dart';

import 'package:ebtl_customer_app/features/cart/cart_screen.dart';
import 'package:ebtl_customer_app/features/checkout/checkout_screen.dart';
import 'package:ebtl_customer_app/features/profile/widgets/spirit_widgets.dart';
import 'package:ebtl_customer_app/features/shop/widgets/shop_product_widgets.dart';
import 'package:ebtl_customer_app/models/cart_models.dart';
import 'package:ebtl_customer_app/models/shop_models.dart';
import 'package:ebtl_customer_app/models/spirit_models.dart';

final _product = ShopProduct.fromJson({
  'id': 'p1',
  'slug': 'mojito',
  'name': 'Classic Mojito Beach Kit',
  'product_type': 'cocktail',
  'short_description':
      'White rum, lime, mint and soda over crushed ice, packed for the beach.',
  'price': {'starting_price_inc_vat': 320.0, 'currency': 'EGP'},
});

/// A cart line with every optional row populated: the case that used to push
/// the text column past the thumbnail-height box it was locked into.
final _fullCartItem = CartPageItem.fromJson({
  'id': 'i1',
  'product_id': 'p1',
  'variant_id': 'v1',
  'quantity': 2,
  'product': {
    'name': 'Classic Mojito Beach Kit',
    'short_description': 'White rum, lime, mint and soda over crushed ice.',
  },
  'variant': {'name': 'Standard'},
  'pricing': {
    'unit_price_inc_vat': 320.0,
    'line_total_inc_vat': 640.0,
    'currency': 'EGP',
  },
  'customization': {'summary': '2 removed · 1 added'},
  'availability': {'is_orderable': false, 'reason': 'Out of stock right now'},
});

/// The ordinary line: no description, no customization, nothing unavailable.
final _plainCartItem = CartPageItem.fromJson({
  'id': 'i2',
  'product_id': 'p2',
  'variant_id': 'v2',
  'quantity': 1,
  'product': {'name': 'Beach Towel'},
  'variant': {'name': 'Standard'},
  'pricing': {
    'unit_price_inc_vat': 120.0,
    'line_total_inc_vat': 120.0,
    'currency': 'EGP',
  },
  'availability': {'is_orderable': true},
});

Widget wrap(Widget child) =>
    MaterialApp(home: Scaffold(body: Center(child: child)));

void main() {
  setUpAll(() => GoogleFonts.config.allowRuntimeFetching = false);

  void phone(WidgetTester tester) {
    tester.view.physicalSize = const Size(390, 844);
    tester.view.devicePixelRatio = 1.0;
    addTearDown(tester.view.reset);
  }

  group('ShopProductCardTile.heightFor', () {
    // Every fixed-extent rail and grid sizes itself from `heightFor`, so it has
    // to keep agreeing with what the tile actually lays out to. If the card's
    // artwork or text block changes and this is not updated, the call sites
    // overflow rather than adapt.
    Future<double> measure(
      WidgetTester tester, {
      required bool compact,
      int? subtitleMaxLines,
    }) async {
      await tester.pumpWidget(
        wrap(
          SizedBox(
            width: 160,
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                ShopProductCardTile(
                  product: _product,
                  compact: compact,
                  isAdding: false,
                  subtitleOverride: _product.shortDescription,
                  subtitleMaxLines: subtitleMaxLines,
                  onTap: () {},
                  onAdd: () {},
                ),
              ],
            ),
          ),
        ),
      );

      return tester.getSize(find.byType(ShopProductCardTile)).height;
    }

    testWidgets('matches the tile it describes', (tester) async {
      phone(tester);

      for (final (compact, maxLines) in const [
        (false, null),
        (false, 2),
        (false, 3),
        (true, null),
        (true, 2),
      ]) {
        expect(
          await measure(tester, compact: compact, subtitleMaxLines: maxLines),
          ShopProductCardTile.heightFor(
            compact: compact,
            subtitleMaxLines: maxLines,
          ),
          reason: 'compact: $compact, subtitleMaxLines: $maxLines',
        );
      }
    });
  });

  testWidgets('product tile fits the Explore recently-viewed rail', (
    tester,
  ) async {
    phone(tester);

    await tester.pumpWidget(
      wrap(
        SizedBox(
          height: ShopProductCardTile.heightFor(
            compact: false,
            subtitleMaxLines: 2,
          ),
          child: ListView(
            scrollDirection: Axis.horizontal,
            children: [
              ShopProductCardTile(
                product: _product,
                width: 128,
                compact: false,
                isAdding: false,
                subtitleOverride: _product.shortDescription,
                subtitleMaxLines: 2,
                onTap: () {},
                onAdd: null,
              ),
            ],
          ),
        ),
      ),
    );

    expect(tester.takeException(), isNull);
  });

  testWidgets('product tile fits the shop search grid', (tester) async {
    phone(tester);

    await tester.pumpWidget(
      wrap(
        SizedBox(
          width: 346,
          height: 600,
          child: GridView(
            gridDelegate: SliverGridDelegateWithFixedCrossAxisCount(
              crossAxisCount: 2,
              mainAxisExtent: ShopProductCardTile.heightFor(compact: false),
              mainAxisSpacing: 14,
              crossAxisSpacing: 14,
            ),
            children: [
              ShopProductCardTile(
                product: _product,
                compact: false,
                isAdding: false,
                onTap: () {},
                onAdd: () {},
              ),
            ],
          ),
        ),
      ),
    );

    expect(tester.takeException(), isNull);
  });

  group('CartItemCard', () {
    Future<double> pumpLine(WidgetTester tester, CartPageItem item) async {
      await tester.pumpWidget(
        wrap(
          SizedBox(
            width: 346,
            child: CartItemCard(
              item: item,
              isMutating: false,
              onIncrement: () {},
              onDecrement: () {},
              onDelete: () {},
            ),
          ),
        ),
      );

      return tester.getSize(find.byType(CartItemCard)).height;
    }

    testWidgets('grows for its optional rows instead of overflowing', (
      tester,
    ) async {
      phone(tester);

      final plainHeight = await pumpLine(tester, _plainCartItem);
      expect(tester.takeException(), isNull);

      final fullHeight = await pumpLine(tester, _fullCartItem);
      expect(tester.takeException(), isNull);

      // A line with nothing extra to say still sits on the thumbnail's own
      // height: 86 thumbnail + 7pt padding + 1pt border on each side. The
      // ordinary card keeps exactly the layout it has always had.
      expect(plainHeight, 102);
      expect(fullHeight, greaterThan(plainHeight));
    });
  });

  testWidgets('checkout summary line ellipsizes a long promo label', (
    tester,
  ) async {
    phone(tester);

    await tester.pumpWidget(
      wrap(
        const Padding(
          // 22 screen gutter + 18 DetailCard padding on each side.
          padding: EdgeInsets.symmetric(horizontal: 40),
          child: CheckoutSummaryLine(
            label: 'Discount (SUMMERBEACHPARTY26)',
            value: '- EGP 1,250.00',
          ),
        ),
      ),
    );

    expect(tester.takeException(), isNull);
  });

  testWidgets('spirit pill ellipsizes a long bottle name', (tester) async {
    phone(tester);

    await tester.pumpWidget(
      wrap(
        Padding(
          padding: const EdgeInsets.symmetric(horizontal: 38),
          child: Wrap(
            children: [
              SpiritPill(
                spirit: ProfileSpirit.fromJson(const {
                  'id': 's1',
                  'name': 'Johnnie Walker Blue Label Ghost and Rare Port Ellen',
                }),
                trailingLabel: 'Ordered 12 times',
                actionIcon: Icons.close,
                onAction: () {},
              ),
            ],
          ),
        ),
      ),
    );

    expect(tester.takeException(), isNull);
  });
}
