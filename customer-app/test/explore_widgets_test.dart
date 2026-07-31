// The Explore hero's whole point is that its copy stays clear of the artwork
// on the right half of the banner, and that tapping anywhere on it opens the
// Cocktail Finder — which no longer has a nav tab of its own to fall back on.

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:google_fonts/google_fonts.dart';

import 'package:ebtl_customer_app/features/explore/widgets/explore_category_badges.dart';
import 'package:ebtl_customer_app/features/explore/widgets/explore_hero_banner.dart';
import 'package:ebtl_customer_app/models/shop_models.dart';

const _categories = [
  ShopCategory(
    id: 'c1',
    name: 'Cocktails',
    slug: 'cocktails',
    imageUrl: null,
    sortOrder: 1,
    productCount: 6,
  ),
  ShopCategory(
    id: 'c2',
    name: 'Snacks',
    slug: 'snacks',
    imageUrl: null,
    sortOrder: 2,
    productCount: 3,
  ),
];

Widget wrap(Widget child) {
  return MaterialApp(
    home: Scaffold(body: SingleChildScrollView(child: child)),
  );
}

void main() {
  setUpAll(() => GoogleFonts.config.allowRuntimeFetching = false);

  group('ExploreHeroBanner', () {
    testWidgets('shows both lines of copy', (tester) async {
      await tester.pumpWidget(wrap(ExploreHeroBanner(onTap: () {})));

      expect(find.text('Match My Bottle'), findsOneWidget);
      expect(
        find.text('See cocktails made for the bottle you have.'),
        findsOneWidget,
      );
    });

    testWidgets('constrains its copy to the left half of the banner', (
      tester,
    ) async {
      tester.view.physicalSize = const Size(390, 844);
      tester.view.devicePixelRatio = 1.0;
      addTearDown(tester.view.reset);

      await tester.pumpWidget(wrap(ExploreHeroBanner(onTap: () {})));

      final banner = tester.getRect(find.byType(AspectRatio));
      final headline = tester.getRect(find.text('Match My Bottle'));
      final subhead = tester.getRect(
        find.text('See cocktails made for the bottle you have.'),
      );

      final midpoint = banner.left + banner.width / 2;

      expect(headline.right, lessThanOrEqualTo(midpoint));
      expect(subhead.right, lessThanOrEqualTo(midpoint));

      // 390 wide minus the 22pt gutters, at 2:1.
      expect(banner.width, closeTo(346, 0.5));
      expect(banner.height, closeTo(173, 0.5));
    });

    testWidgets('the whole banner is one tap target', (tester) async {
      var taps = 0;
      await tester.pumpWidget(wrap(ExploreHeroBanner(onTap: () => taps++)));

      // Top-left corner of the banner, far from the arrow.
      final banner = tester.getRect(find.byType(AspectRatio));
      await tester.tapAt(banner.topLeft + const Offset(12, 12));
      await tester.pump();

      expect(taps, 1);
    });
  });

  group('ExploreCategoryBadges', () {
    Widget badges({
      String? selected,
      required ValueChanged<String?> onSelect,
      List<ShopCategory> categories = _categories,
    }) {
      return wrap(
        ExploreCategoryBadges(
          categories: categories,
          productCounts: const {'c1': 6, 'c2': 3},
          selectedCategoryId: selected,
          totalProductCount: 9,
          onSelect: onSelect,
        ),
      );
    }

    testWidgets('leads with All and lists every category with its count', (
      tester,
    ) async {
      await tester.pumpWidget(badges(onSelect: (_) {}));

      expect(find.text('All'), findsOneWidget);
      expect(find.text('9'), findsOneWidget);
      expect(find.text('Cocktails'), findsOneWidget);
      expect(find.text('6'), findsOneWidget);
      expect(find.text('Snacks'), findsOneWidget);
      expect(find.text('3'), findsOneWidget);
    });

    testWidgets('reports the picked category, and null for All', (
      tester,
    ) async {
      final picked = <String?>[];

      await tester.pumpWidget(badges(selected: 'c1', onSelect: picked.add));

      await tester.tap(find.text('Snacks'));
      await tester.tap(find.text('All'));

      expect(picked, ['c2', null]);
    });

    testWidgets('renders nothing when there are no categories', (tester) async {
      await tester.pumpWidget(badges(categories: const [], onSelect: (_) {}));

      expect(find.text('All'), findsNothing);
    });
  });
}
