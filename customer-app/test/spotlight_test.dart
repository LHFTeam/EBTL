// The Spotlight rail is a merchandising slot like the hero carousel, with one
// difference that drives most of these cases: it has no bundled fallback. A
// banner that cannot be drawn, or a payload with none live, means no rail at all
// rather than a placeholder.

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:ebtl_customer_app/core/theme/home_screen_visuals.dart';
import 'package:ebtl_customer_app/features/home/widgets/home_spotlight_rail.dart';
import 'package:ebtl_customer_app/models/app_data.dart';
import 'package:ebtl_customer_app/models/spotlight_models.dart';

const _optionsJson = <String, dynamic>{
  'liquorTypes': [],
  'tags': [],
  'categories': [],
  'productTags': [],
  'sortOptions': [],
};

AppData appDataWith(List<Map<String, dynamic>> spotlightBanners) {
  return AppData.fromApi(
    homeJson: {
      'hero': const {},
      'serviceAreas': const [],
      'featuredCocktails': const [],
      'categories': const [],
      'liquorTypes': const [],
      'heroBanners': const [],
      'spotlightBanners': spotlightBanners,
    },
    optionsJson: _optionsJson,
    selectedLocationId: null,
    selectedLocationName: null,
  );
}

SpotlightBanner banner({
  String id = 's1',
  String imageUrl = 'https://cdn.ebtl.test/spotlight.webp',
  String title = 'Lunch in minutes',
  String? subtitle,
  int displayOrder = 0,
  SpotlightContentType contentType = SpotlightContentType.products,
  String? markdownBody,
}) {
  return SpotlightBanner(
    id: id,
    imageUrl: imageUrl,
    title: title,
    subtitle: subtitle,
    displayOrder: displayOrder,
    contentType: contentType,
    markdownBody: markdownBody,
  );
}

void main() {
  group('SpotlightBanner payload', () {
    test('reads a full banner off the home payload', () {
      final data = appDataWith([
        {
          'id': 's1',
          'image_url': 'https://cdn.ebtl.test/lunch.webp',
          'title': 'Lunch in minutes',
          'subtitle': 'Ready when you are.',
          'display_order': 0,
        },
      ]);

      expect(data.spotlightBanners, hasLength(1));
      expect(data.spotlightBanners.first.title, 'Lunch in minutes');
      expect(data.spotlightBanners.first.subtitle, 'Ready when you are.');
    });

    test('a missing subtitle stays null rather than becoming empty text', () {
      final data = appDataWith([
        {
          'id': 's1',
          'image_url': 'https://cdn.ebtl.test/lunch.webp',
          'title': 'Lunch in minutes',
        },
      ]);

      expect(data.spotlightBanners.first.subtitle, isNull);
    });

    test('banners sort by display order', () {
      final data = appDataWith([
        {
          'id': 'b',
          'image_url': 'https://cdn.ebtl.test/b.webp',
          'title': 'Second',
          'display_order': 5,
        },
        {
          'id': 'a',
          'image_url': 'https://cdn.ebtl.test/a.webp',
          'title': 'First',
          'display_order': 1,
        },
      ]);

      expect(
        data.spotlightBanners.map((banner) => banner.title),
        ['First', 'Second'],
      );
    });

    test('a banner with no image, id or title is dropped', () {
      final data = appDataWith([
        {'id': '', 'image_url': 'https://cdn.ebtl.test/a.webp', 'title': 'No id'},
        {'id': 'b', 'image_url': '', 'title': 'No image'},
        {'id': 'c', 'image_url': 'https://cdn.ebtl.test/c.webp', 'title': ''},
        {
          'id': 'd',
          'image_url': 'https://cdn.ebtl.test/d.webp',
          'title': 'Keeper',
        },
      ]);

      expect(data.spotlightBanners.map((banner) => banner.title), ['Keeper']);
    });

    test('a payload with no spotlight banners leaves the list empty', () {
      expect(appDataWith(const []).spotlightBanners, isEmpty);
    });

    test('an unrecognised or missing content_type reads as products', () {
      final data = appDataWith([
        {
          'id': 's1',
          'image_url': 'https://cdn.ebtl.test/a.webp',
          'title': 'Products banner',
        },
        {
          'id': 's2',
          'image_url': 'https://cdn.ebtl.test/b.webp',
          'title': 'Typo banner',
          'content_type': 'not-a-real-type',
        },
      ]);

      expect(
        data.spotlightBanners.map((banner) => banner.contentType),
        [SpotlightContentType.products, SpotlightContentType.products],
      );
    });

    test('a markdown banner reads its content_type and markdown_body', () {
      final data = appDataWith([
        {
          'id': 's1',
          'image_url': 'https://cdn.ebtl.test/a.webp',
          'title': 'Recipe of the week',
          'content_type': 'markdown',
          'markdown_body': '# Recipe of the week\n\nMuddle, shake, pour.',
        },
      ]);

      final slide = data.spotlightBanners.first;
      expect(slide.contentType, SpotlightContentType.markdown);
      expect(slide.markdownBody, '# Recipe of the week\n\nMuddle, shake, pour.');
      expect(slide.isMarkdownSlide, isTrue);
    });

    test('a markdown banner with no body does not report as a slide', () {
      final slide = banner(contentType: SpotlightContentType.markdown);
      expect(slide.isMarkdownSlide, isFalse);
    });

    test('a products banner never reports as a markdown slide', () {
      final slide = banner(markdownBody: '# Ignored');
      expect(slide.isMarkdownSlide, isFalse);
    });
  });

  group('HomeSpotlightRail', () {
    testWidgets('draws each banner at the 2.5:1 authored ratio', (tester) async {
      await tester.pumpWidget(
        MaterialApp(
          home: Scaffold(
            body: HomeSpotlightRail(
              banners: [banner(id: 's1'), banner(id: 's2', title: 'Gatherings')],
              onOpenBanner: (_) {},
            ),
          ),
        ),
      );

      final cards = find.descendant(
        of: find.byType(HomeSpotlightRail),
        matching: find.byType(GestureDetector),
      );

      expect(cards, findsNWidgets(2));

      for (var index = 0; index < 2; index++) {
        final size = tester.getSize(cards.at(index));

        expect(size.width, HomeScreenVisuals.spotlightBannerWidth);
        expect(
          size.width / size.height,
          closeTo(HomeScreenVisuals.spotlightBannerAspectRatio, 0.01),
        );
      }
    });

    testWidgets('tapping a banner reports which one', (tester) async {
      SpotlightBanner? opened;

      await tester.pumpWidget(
        MaterialApp(
          home: Scaffold(
            body: HomeSpotlightRail(
              banners: [
                banner(id: 's1', title: 'Lunch'),
                banner(id: 's2', title: 'Gatherings'),
              ],
              onOpenBanner: (banner) => opened = banner,
            ),
          ),
        ),
      );

      await tester.tap(find.byType(GestureDetector).last);
      expect(opened?.id, 's2');
    });
  });
}
