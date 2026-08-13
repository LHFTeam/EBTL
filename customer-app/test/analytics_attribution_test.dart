import 'package:ebtl_customer_app/services/analytics_service.dart';
import 'package:flutter_test/flutter_test.dart';

AnalyticsItem itemWith({String? source, String? sourceDetail}) {
  return AnalyticsItem(
    id: 'prod-1',
    name: 'Negroni',
    category: 'Classics',
    variant: 'Single',
    price: 180,
    quantity: 2,
    currency: 'EGP',
    source: source,
    sourceDetail: sourceDetail,
  );
}

void main() {
  group('the item a product event reports', () {
    test('carries the name and category the reports break down by', () {
      final item = itemWith().toFirebaseItem();

      expect(item.itemName, 'Negroni');
      expect(item.itemCategory, 'Classics');
      expect(item.itemId, 'prod-1');
      expect(item.itemVariant, 'Single');
    });

    test('reports its source as the item list it was picked from', () {
      final item = itemWith(source: AnalyticsSource.cocktailFinder);

      expect(item.toFirebaseItem().itemListName, 'cocktail_finder');
    });

    test('leaves the item list unset when nothing named the source', () {
      expect(itemWith().toFirebaseItem().itemListName, isNull);
    });

    test('treats a blank source as no source rather than an empty list', () {
      expect(itemWith(source: '   ').toFirebaseItem().itemListName, isNull);
    });
  });

  group('the event parameters an item repeats its origin in', () {
    test('are absent when the item has no origin to report', () {
      expect(itemWith().sourceParameters, isNull);
    });

    test('name the surface', () {
      expect(itemWith(source: AnalyticsSource.spotlight).sourceParameters, {
        'source': 'spotlight_banner',
      });
    });

    test('name the instance of it alongside the surface', () {
      final parameters = itemWith(
        source: AnalyticsSource.cocktailFinder,
        sourceDetail: 'Gin',
      ).sourceParameters;

      expect(parameters, {'source': 'cocktail_finder', 'source_detail': 'Gin'});
    });

    test('drop a blank detail instead of reporting an empty one', () {
      expect(
        itemWith(
          source: AnalyticsSource.home,
          sourceDetail: ' ',
        ).sourceParameters,
        {'source': 'home'},
      );
    });

    test('report a detail that arrived without a surface', () {
      // Not how the app calls it, but a caller that names only the banner
      // should still get that banner into the report.
      expect(itemWith(sourceDetail: 'Summer Kit').sourceParameters, {
        'source_detail': 'Summer Kit',
      });
    });
  });

  group('every source is distinct', () {
    test('so two surfaces never collapse into one row', () {
      const sources = [
        AnalyticsSource.home,
        AnalyticsSource.heroBanner,
        AnalyticsSource.spotlight,
        AnalyticsSource.goldenHour,
        AnalyticsSource.orderAgain,
        AnalyticsSource.recentlyViewed,
        AnalyticsSource.explore,
        AnalyticsSource.search,
        AnalyticsSource.shop,
        AnalyticsSource.shopCategory,
        AnalyticsSource.cocktailFinder,
        AnalyticsSource.relatedCocktail,
        AnalyticsSource.favorites,
      ];

      expect(sources.toSet(), hasLength(sources.length));
    });
  });

  group('logging with no provider configured', () {
    // Analytics is inert in tests — no Firebase platform config, and Clarity
    // is off in debug. Every entry point still has to be safe to call, since
    // screens call them unconditionally.
    test('a product view is a no-op rather than a crash', () {
      expect(
        () => AnalyticsService.logViewItem(
          itemWith(source: AnalyticsSource.explore),
        ),
        returnsNormally,
      );
    });

    test('a banner tap is a no-op', () {
      expect(
        () => AnalyticsService.logPromotionSelected(
          promotionId: 'banner-1',
          promotionName: 'Sunset Kits',
          slot: AnalyticsPromotionSlot.heroCarousel,
          destination: 'finder',
        ),
        returnsNormally,
      );
    });

    test('a banner with neither a name nor an id reports nothing', () {
      expect(
        () => AnalyticsService.logPromotionSelected(
          promotionId: '  ',
          promotionName: '',
          slot: AnalyticsPromotionSlot.spotlightRail,
        ),
        returnsNormally,
      );
    });

    test('a Finder bottle choice is a no-op', () {
      expect(
        () => AnalyticsService.logFinderBottleChanged(
          bottleName: 'Gin',
          isSelected: true,
          selectionCount: 1,
        ),
        returnsNormally,
      );
    });
  });
}
