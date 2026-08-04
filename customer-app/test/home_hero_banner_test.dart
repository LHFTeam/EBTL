// The hero carousel is now a merchandising slot: whatever marketing has live
// on the home payload, falling back to the three bundled slides when they have
// none. Only the image and the order are required, so the interesting cases are
// the ones where the optional parts are missing.

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:google_fonts/google_fonts.dart';

import 'package:ebtl_customer_app/features/home/widgets/home_hero_carousel.dart';
import 'package:ebtl_customer_app/models/app_data.dart';
import 'package:ebtl_customer_app/models/common_models.dart';

const _optionsJson = <String, dynamic>{
  'liquorTypes': [],
  'tags': [],
  'categories': [],
  'productTags': [],
  'sortOptions': [],
};

AppData appDataWith(List<Map<String, dynamic>> heroBanners) {
  return AppData.fromApi(
    homeJson: {
      'hero': const {},
      'serviceAreas': const [],
      'featuredCocktails': const [],
      'categories': const [],
      'liquorTypes': const [],
      'heroBanners': heroBanners,
    },
    optionsJson: _optionsJson,
    selectedLocationId: null,
    selectedLocationName: null,
  );
}

HomeHeroBanner banner({
  String id = 'b1',
  String imageUrl = 'https://cdn.ebtl.test/hero.webp',
  String? headline,
  String? body,
  String? deepLink,
  int displayOrder = 0,
}) {
  return HomeHeroBanner(
    id: id,
    imageUrl: imageUrl,
    headline: headline,
    body: body,
    deepLink: deepLink,
    displayOrder: displayOrder,
  );
}

Widget wrap(Widget child) {
  return MaterialApp(home: Scaffold(body: child));
}

void main() {
  setUpAll(() => GoogleFonts.config.allowRuntimeFetching = false);

  group('HeroBannerLink.parse', () {
    test('reads the destinations that take no value', () {
      expect(HeroBannerLink.parse('finder').kind, HeroBannerLinkKind.finder);
      expect(HeroBannerLink.parse('explore').kind, HeroBannerLinkKind.explore);
      expect(HeroBannerLink.parse('cart').kind, HeroBannerLinkKind.cart);
      expect(HeroBannerLink.parse('orders').kind, HeroBannerLinkKind.orders);
    });

    test('splits the destinations that carry a slug or id', () {
      final cocktail = HeroBannerLink.parse('cocktail/beach-mojito');
      expect(cocktail.kind, HeroBannerLinkKind.cocktail);
      expect(cocktail.value, 'beach-mojito');

      final category = HeroBannerLink.parse('category/cat-1');
      expect(category.kind, HeroBannerLinkKind.category);
      expect(category.value, 'cat-1');
    });

    test('treats blank, unknown and value-less links as untappable', () {
      for (final deepLink in [null, '', '   ', 'https://ebtl.wtf', 'cocktail/']) {
        expect(
          HeroBannerLink.parse(deepLink).isTappable,
          isFalse,
          reason: 'expected "$deepLink" to be untappable',
        );
      }
    });
  });

  group('AppData hero banners', () {
    test('sorts by display order and drops rows with no image', () {
      final data = appDataWith([
        {'id': 'b2', 'image_url': 'https://cdn.ebtl.test/2.webp', 'display_order': 2},
        {'id': 'b1', 'image_url': 'https://cdn.ebtl.test/1.webp', 'display_order': 1},
        {'id': 'b3', 'image_url': '', 'display_order': 0},
      ]);

      expect(data.heroBanners.map((banner) => banner.id), ['b1', 'b2']);
    });

    test('is empty when the payload carries no banners', () {
      expect(appDataWith(const []).heroBanners, isEmpty);
    });

    test('keeps the optional fields null rather than inventing copy', () {
      final data = appDataWith([
        {'id': 'b1', 'image_url': 'https://cdn.ebtl.test/1.webp', 'display_order': 0},
      ]);

      final only = data.heroBanners.single;
      expect(only.headline, isNull);
      expect(only.body, isNull);
      expect(only.deepLink, isNull);
      expect(only.hasText, isFalse);
      expect(only.link.isTappable, isFalse);
    });
  });

  group('HomeHeroCarousel', () {
    testWidgets('falls back to the bundled slides with no banners', (
      tester,
    ) async {
      await tester.pumpWidget(
        wrap(HomeHeroCarousel(banners: const [], onOpenBanner: (_) {})),
      );

      expect(find.text('You bring the bottle.'), findsOneWidget);
    });

    testWidgets('renders the CMS copy instead once banners exist', (
      tester,
    ) async {
      await tester.pumpWidget(
        wrap(
          HomeHeroCarousel(
            banners: [
              banner(headline: 'Ramadan kits', body: 'Ready at your cart.'),
            ],
            onOpenBanner: (_) {},
          ),
        ),
      );

      expect(find.text('Ramadan kits'), findsOneWidget);
      expect(find.text('Ready at your cart.'), findsOneWidget);
      expect(find.text('You bring the bottle.'), findsNothing);
    });

    testWidgets('only reports a tap for a banner that carries a deep link', (
      tester,
    ) async {
      final opened = <String>[];

      await tester.pumpWidget(
        wrap(
          HomeHeroCarousel(
            banners: [banner(id: 'no-link', headline: 'Just art')],
            onOpenBanner: (banner) => opened.add(banner.id),
          ),
        ),
      );

      await tester.tap(find.text('Just art'));
      expect(opened, isEmpty);

      await tester.pumpWidget(
        wrap(
          HomeHeroCarousel(
            banners: [
              banner(id: 'linked', headline: 'Find yours', deepLink: 'finder'),
            ],
            onOpenBanner: (banner) => opened.add(banner.id),
          ),
        ),
      );

      await tester.tap(find.text('Find yours'));
      expect(opened, ['linked']);
    });
  });
}
