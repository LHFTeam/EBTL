// A product tag decides for itself where it may appear: as a filter chip in
// the finder, and as a badge on the card. The product's own page lists every
// tag it carries regardless, which is what these tests pin down.

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:google_fonts/google_fonts.dart';

import 'package:ebtl_customer_app/core/utils/model_sorters.dart';
import 'package:ebtl_customer_app/features/finder/widgets/finder_filter_widgets.dart';
import 'package:ebtl_customer_app/models/common_models.dart';
import 'package:ebtl_customer_app/models/shop_models.dart';
import 'package:ebtl_customer_app/shared/widgets/product_tag_widgets.dart';

Map<String, dynamic> tagJson({
  required String id,
  required String name,
  int displayOrder = 0,
  bool? showInFilters,
  bool? showOnProductCard,
}) {
  return <String, dynamic>{
    'id': id,
    'name': name,
    'color_hex': '#1F6F68',
    'display_order': displayOrder,
    'show_in_filters': ?showInFilters,
    'show_on_product_card': ?showOnProductCard,
  };
}

ShopProduct productWithTags(List<Map<String, dynamic>> tags) {
  return ShopProduct.fromJson(<String, dynamic>{
    'id': 'p1',
    'slug': 'mojito',
    'name': 'Mojito',
    'product_type': 'cocktail',
    'tags': tags.map((tag) => tag['name']).toList(),
    'tag_details': tags,
  });
}

Widget wrap(Widget child) {
  return MaterialApp(
    home: Scaffold(body: SingleChildScrollView(child: child)),
  );
}

void main() {
  setUpAll(() => GoogleFonts.config.allowRuntimeFetching = false);

  group('ProductTag.fromJson', () {
    test('an API that predates the flags leaves the tag in both places', () {
      final tag = ProductTag.fromJson(tagJson(id: 't1', name: 'Best Seller'));

      expect(tag.showInFilters, isTrue);
      expect(tag.showOnProductCard, isTrue);
    });

    test('reads both flags when the API sends them', () {
      final tag = ProductTag.fromJson(
        tagJson(
          id: 't1',
          name: 'Best Seller',
          showInFilters: false,
          showOnProductCard: true,
        ),
      );

      expect(tag.showInFilters, isFalse);
      expect(tag.showOnProductCard, isTrue);
    });
  });

  group('tag placement', () {
    final tags = [
      ProductTag.fromJson(
        tagJson(id: 't1', name: 'Card only', displayOrder: 2, showInFilters: false),
      ),
      ProductTag.fromJson(
        tagJson(
          id: 't2',
          name: 'Filter only',
          displayOrder: 1,
          showOnProductCard: false,
        ),
      ),
      ProductTag.fromJson(tagJson(id: 't3', name: 'Both', displayOrder: 3)),
    ];

    test('cards badge the card tags, in display order', () {
      expect(
        cardProductTags(tags).map((tag) => tag.name),
        ['Card only', 'Both'],
      );
    });

    test('the finder offers the filter tags, in display order', () {
      expect(
        filterProductTags(tags).map((tag) => tag.name),
        ['Filter only', 'Both'],
      );
    });
  });

  group('ShopProduct', () {
    final product = productWithTags([
      tagJson(id: 't1', name: 'Best Seller', displayOrder: 1),
      tagJson(
        id: 't2',
        name: 'Vegan',
        displayOrder: 2,
        showOnProductCard: false,
      ),
    ]);

    test('a product carries every tag assigned to it', () {
      expect(product.tagDetails.map((tag) => tag.name), [
        'Best Seller',
        'Vegan',
      ]);
    });

    test('the card badges only the tags marked for it', () {
      expect(product.cardTagDetails.map((tag) => tag.name), ['Best Seller']);
    });
  });

  group('ProductTagFilterSection', () {
    testWidgets('lists the filter tags and leaves the others out', (
      tester,
    ) async {
      await tester.pumpWidget(
        wrap(
          ProductTagFilterSection(
            productTags: [
              ProductTag.fromJson(tagJson(id: 't1', name: 'Refreshing')),
              ProductTag.fromJson(
                tagJson(id: 't2', name: 'Card Only', showInFilters: false),
              ),
            ],
            selectedTagNames: const {},
            onToggle: (_) {},
            onClear: () {},
          ),
        ),
      );

      expect(find.text('Refreshing'), findsOneWidget);
      expect(find.text('Card Only'), findsNothing);
      expect(find.byType(ProductTagFilterChip), findsOneWidget);
    });

    testWidgets('hides itself when no tag is a filter', (tester) async {
      await tester.pumpWidget(
        wrap(
          ProductTagFilterSection(
            productTags: [
              ProductTag.fromJson(
                tagJson(id: 't1', name: 'Card Only', showInFilters: false),
              ),
            ],
            selectedTagNames: const {},
            onToggle: (_) {},
            onClear: () {},
          ),
        ),
      );

      expect(find.byType(ProductTagFilterChip), findsNothing);
      expect(find.text('Filter by Style'), findsNothing);
    });
  });
}
