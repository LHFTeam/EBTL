import 'package:flutter_test/flutter_test.dart';

import 'package:ebtl_customer_app/models/app_data.dart';
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

    test('carries reused options over instead of requiring a fresh payload', () {
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
    });

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
}
