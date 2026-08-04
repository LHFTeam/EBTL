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

AppData appDataWith(
  List<Map<String, dynamic>> heroBanners, {
  Map<String, dynamic>? heroCarousel,
}) {
  return AppData.fromApi(
    homeJson: {
      'hero': const {},
      'serviceAreas': const [],
      'featuredCocktails': const [],
      'categories': const [],
      'liquorTypes': const [],
      'heroBanners': heroBanners,
      'heroCarousel': ?heroCarousel,
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

/// The banner the carousel is currently showing in its center slot.
String centeredHeadline(WidgetTester tester) {
  final texts = tester.widgetList<Text>(find.byType(Text)).toList();
  var best = '';
  var bestDistance = double.infinity;
  final center = tester.getCenter(find.byType(PageView)).dx;

  for (final text in texts) {
    final finder = find.text(text.data ?? '');
    if (finder.evaluate().length != 1) continue;

    final distance = (tester.getCenter(finder).dx - center).abs();
    if (distance < bestDistance) {
      bestDistance = distance;
      best = text.data ?? '';
    }
  }

  return best;
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

    test('reads the rotation interval, falling back to five seconds', () {
      expect(appDataWith(const []).heroRotation, const Duration(seconds: 5));
      expect(
        appDataWith(const [], heroCarousel: {'rotation_seconds': 9}).heroRotation,
        const Duration(seconds: 9),
      );
    });

    test('clamps a rotation interval the carousel could not run at', () {
      expect(
        appDataWith(const [], heroCarousel: {'rotation_seconds': 0}).heroRotation,
        HomeHeroBanner.minRotation,
      );
      expect(
        appDataWith(const [], heroCarousel: {'rotation_seconds': 6000}).heroRotation,
        HomeHeroBanner.maxRotation,
      );
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

    testWidgets('draws the centered slide about 30% bigger than its neighbours', (
      tester,
    ) async {
      tester.view.physicalSize = const Size(390, 844);
      tester.view.devicePixelRatio = 1.0;
      addTearDown(tester.view.reset);

      await tester.pumpWidget(
        wrap(
          HomeHeroCarousel(
            banners: [
              banner(id: 'a', headline: 'Slide A'),
              banner(id: 'b', headline: 'Slide B'),
              banner(id: 'c', headline: 'Slide C'),
            ],
            onOpenBanner: (_) {},
          ),
        ),
      );
      await tester.pump();

      // Scaling is painted, not laid out, so the slides measure the same in
      // their own coordinates — the global rects are where the growth shows.
      expect(slideLayoutWidth(tester, 'Slide A'),
          slideLayoutWidth(tester, 'Slide B'));
      expect(
        slidePaintedWidth(tester, 'Slide A') /
            slidePaintedWidth(tester, 'Slide B'),
        closeTo(1.3, 0.01),
      );
    });

    testWidgets('advances itself after the rotation interval', (tester) async {
      await tester.pumpWidget(
        wrap(
          HomeHeroCarousel(
            banners: [
              banner(id: 'a', headline: 'Slide A'),
              banner(id: 'b', headline: 'Slide B'),
            ],
            rotationInterval: const Duration(seconds: 3),
            onOpenBanner: (_) {},
          ),
        ),
      );

      expect(centeredHeadline(tester), 'Slide A');

      await tester.pump(const Duration(seconds: 3));
      await tester.pumpAndSettle();
      expect(centeredHeadline(tester), 'Slide B');

      // And it keeps going: the loop has no last slide to stop on.
      await tester.pump(const Duration(seconds: 3));
      await tester.pumpAndSettle();
      expect(centeredHeadline(tester), 'Slide A');
    });

    testWidgets('a swipe takes over, and the timer restarts after it', (
      tester,
    ) async {
      await tester.pumpWidget(
        wrap(
          HomeHeroCarousel(
            banners: [
              banner(id: 'a', headline: 'Slide A'),
              banner(id: 'b', headline: 'Slide B'),
            ],
            rotationInterval: const Duration(seconds: 3),
            onOpenBanner: (_) {},
          ),
        ),
      );

      // Backwards, which an endlessly-paging carousel allows from any slide.
      await tester.drag(find.byType(PageView), const Offset(320, 0));
      await tester.pumpAndSettle();
      expect(centeredHeadline(tester), 'Slide B');

      // The interval starts again from where they let go, not from the tick
      // that was pending when they grabbed it.
      await tester.pump(const Duration(seconds: 2));
      expect(centeredHeadline(tester), 'Slide B');

      await tester.pump(const Duration(seconds: 1));
      await tester.pumpAndSettle();
      expect(centeredHeadline(tester), 'Slide A');
    });

    testWidgets('holds still for a single slide and when motion is reduced', (
      tester,
    ) async {
      await tester.pumpWidget(
        wrap(
          HomeHeroCarousel(
            banners: [banner(id: 'only', headline: 'Only slide')],
            rotationInterval: const Duration(seconds: 3),
            onOpenBanner: (_) {},
          ),
        ),
      );

      // No dots for a carousel with nowhere to go.
      expect(find.byType(AnimatedContainer), findsNothing);
      await tester.pump(const Duration(seconds: 10));
      expect(centeredHeadline(tester), 'Only slide');

      await tester.pumpWidget(
        MaterialApp(
          home: MediaQuery(
            data: const MediaQueryData(disableAnimations: true),
            child: Scaffold(
              body: HomeHeroCarousel(
                banners: [
                  banner(id: 'a', headline: 'Slide A'),
                  banner(id: 'b', headline: 'Slide B'),
                ],
                rotationInterval: const Duration(seconds: 3),
                onOpenBanner: (_) {},
              ),
            ),
          ),
        ),
      );

      await tester.pump(const Duration(seconds: 10));
      expect(centeredHeadline(tester), 'Slide A');
    });
  });
}

Finder slideBody(String headline) {
  return find
      .ancestor(of: find.text(headline), matching: find.byType(ClipRRect))
      .first;
}

/// The slide's width as laid out, before the carousel's scaling.
double slideLayoutWidth(WidgetTester tester, String headline) {
  return tester.getSize(slideBody(headline)).width;
}

/// The slide's width as it lands on the screen, scaling included.
double slidePaintedWidth(WidgetTester tester, String headline) {
  return tester.getRect(slideBody(headline)).width;
}
