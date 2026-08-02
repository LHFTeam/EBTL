import 'package:flutter_test/flutter_test.dart';

import 'package:ebtl_customer_app/models/app_data.dart';
import 'package:ebtl_customer_app/models/common_models.dart';
import 'package:ebtl_customer_app/models/finder_models.dart';

const _homeJson = <String, dynamic>{
  'hero': {'headline': 'Beach cocktails', 'subheadline': 'Delivered'},
  'serviceAreas': [
    {'id': 'north-coast', 'name': 'North Coast'},
  ],
  'featuredCocktails': [],
  'categories': [],
  'liquorTypes': [
    {'id': 'gin', 'name': 'Gin', 'display_order': 2},
  ],
  'cartSummary': {'cart_id': 'cart-1', 'total_quantity': 3, 'item_count': 2},
};

const _optionsJson = <String, dynamic>{
  'liquorTypes': [
    {'id': 'rum', 'name': 'Rum', 'display_order': 1},
    {'id': 'gin', 'name': 'Gin', 'display_order': 2},
  ],
  'tags': ['citrus', 'sweet'],
  'categories': [],
  'productTags': [],
  'sortOptions': [],
};

void main() {
  group('AppData.fromApi', () {
    test('builds finder options from a fresh options payload', () {
      final data = AppData.fromApi(
        homeJson: _homeJson,
        optionsJson: _optionsJson,
        selectedLocationId: 'north-coast',
        selectedLocationName: 'North Coast',
      );

      expect(data.finderOptions.tags, ['citrus', 'sweet']);
      expect(data.liquorTypes.map((type) => type.id), ['rum', 'gin']);
      expect(data.cartSummary?.totalQuantity, 3);
    });

    test(
      'carries reused options over instead of requiring a fresh payload',
      () {
        final first = AppData.fromApi(
          homeJson: _homeJson,
          optionsJson: _optionsJson,
          selectedLocationId: 'north-coast',
          selectedLocationName: 'North Coast',
        );

        // What a cart-only refresh does: new /home payload, no second request.
        final refreshed = AppData.fromApi(
          homeJson: {
            ..._homeJson,
            'cartSummary': {
              'cart_id': 'cart-1',
              'total_quantity': 5,
              'item_count': 3,
            },
          },
          reusedOptions: first.finderOptions,
          selectedLocationId: 'north-coast',
          selectedLocationName: 'North Coast',
        );

        expect(refreshed.cartSummary?.totalQuantity, 5);
        expect(refreshed.finderOptions, same(first.finderOptions));
        expect(refreshed.liquorTypes.map((type) => type.id), ['rum', 'gin']);
      },
    );

    test('falls back to home liquor types when options carry none', () {
      final data = AppData.fromApi(
        homeJson: _homeJson,
        reusedOptions: const FinderOptions(
          liquorTypes: [],
          categories: [],
          tags: [],
          productTags: [],
          sortOptions: [],
        ),
        selectedLocationId: null,
        selectedLocationName: null,
      );

      expect(data.liquorTypes.map((type) => type.id), ['gin']);
    });
  });

  group('AppData.withCartSummary', () {
    AppData loaded() {
      return AppData.fromApi(
        homeJson: _homeJson,
        optionsJson: _optionsJson,
        selectedLocationId: 'north-coast',
        selectedLocationName: 'North Coast',
      );
    }

    test('swaps in the summary a cart write answered with', () {
      // The point of the whole exercise: the badge learns the new count from
      // the write's own response, with no /home request behind it.
      final data = loaded().withCartSummary(
        CartSummary.fromJson(const {
          'cart_id': 'cart-1',
          'total_quantity': 7,
          'item_count': 4,
        }),
      );

      expect(data.cartSummary?.totalQuantity, 7);
      expect(data.cartSummary?.itemCount, 4);
    });

    test('leaves the rest of the payload untouched', () {
      final first = loaded();
      final data = first.withCartSummary(CartSummary.emptied('cart-1'));

      expect(data.cartSummary?.totalQuantity, 0);
      expect(data.finderOptions, same(first.finderOptions));
      expect(data.hero, same(first.hero));
      expect(data.featuredCocktails, same(first.featuredCocktails));
      expect(data.selectedLocationId, 'north-coast');
      expect(data.selectedLocationName, 'North Coast');
    });
  });

  group('CartSummary.emptied', () {
    test('describes a cart with nothing in it', () {
      final summary = CartSummary.emptied('cart-1');

      expect(summary.cartId, 'cart-1');
      expect(summary.itemCount, 0);
      expect(summary.totalQuantity, 0);
      expect(summary.subtotalIncVat, 0);
    });
  });
}
