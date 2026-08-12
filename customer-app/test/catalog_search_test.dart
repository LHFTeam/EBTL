// Home and Explore now share one search field and one set of results, so the
// matching and the field itself are tested once, here.

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:google_fonts/google_fonts.dart';

import 'package:ebtl_customer_app/features/search/catalog_search.dart';
import 'package:ebtl_customer_app/features/search/widgets/catalog_search_field.dart';
import 'package:ebtl_customer_app/features/search/widgets/search_results_panel.dart';
import 'package:ebtl_customer_app/models/shop_models.dart';

const _cocktails = ShopCategory(
  id: 'c1',
  name: 'Cocktails',
  slug: 'cocktails',
  imageUrl: null,
  sortOrder: 1,
  productCount: 2,
);

const _snacks = ShopCategory(
  id: 'c2',
  name: 'Snacks',
  slug: 'snacks',
  imageUrl: null,
  sortOrder: 2,
  productCount: 1,
);

ShopProduct product({
  required String id,
  required String name,
  String productType = 'cocktail',
  List<String> tags = const [],
  List<String> ingredients = const [],
  List<String>? searchableIngredients,
}) {
  return ShopProduct.fromJson({
    'id': id,
    'slug': name.toLowerCase().replaceAll(' ', '-'),
    'name': name,
    'product_type': productType,
    'tags': tags,
    'ingredient_names': ingredients,
    'searchable_ingredient_names': ?searchableIngredients,
  });
}

SearchCatalog catalogWith({
  List<ShopCategory> categories = const [_cocktails, _snacks],
  Map<String, List<ShopProduct>> productsByCategory = const {},
}) {
  return SearchCatalog(
    categories: categories,
    productsByCategory: productsByCategory,
    allProducts: [
      for (final products in productsByCategory.values) ...products,
    ],
  );
}

final _mojito = product(
  id: 'p1',
  name: 'Mojito',
  tags: const ['Refreshing', 'refreshing'],
  ingredients: const ['Mint', 'Lime'],
);
final _margarita = product(
  id: 'p2',
  name: 'Margarita',
  tags: const ['Citrus'],
  ingredients: const ['Lime', 'Salt'],
);
final _chips = product(
  id: 'p3',
  name: 'Salted Chips',
  productType: 'snack',
  ingredients: const ['Salt'],
);

final _catalog = catalogWith(
  productsByCategory: {
    'c1': [_mojito, _margarita],
    'c2': [_chips],
  },
);

Widget wrap(Widget child) {
  return MaterialApp(
    home: Scaffold(body: SingleChildScrollView(child: child)),
  );
}

void main() {
  setUpAll(() => GoogleFonts.config.allowRuntimeFetching = false);

  group('SearchCatalog.search', () {
    test('an empty query matches nothing at all', () {
      expect(_catalog.search('   ').isEmpty, isTrue);
    });

    test('matches products, categories, tags and ingredients at once', () {
      final results = _catalog.search('salt');

      // A product matches on its ingredients too, so the Margarita comes back
      // for "salt" without carrying the word in its name.
      expect(results.products.map((p) => p.name), ['Margarita', 'Salted Chips']);
      expect(results.ingredients, ['Salt']);
      expect(results.categories, isEmpty);
      expect(results.tags, isEmpty);
      expect(results.isNotEmpty, isTrue);
    });

    test('is case-insensitive and ignores surrounding space', () {
      expect(_catalog.search('  MOJ ').products.map((p) => p.name), ['Mojito']);
    });

    test('offers each tag once, alphabetically, in its first spelling', () {
      final results = _catalog.search('i');

      expect(results.tags, ['Citrus', 'Refreshing']);
      expect(results.ingredients, ['Lime', 'Mint']);
    });

    test('matches a category by name', () {
      expect(_catalog.search('snack').categories.map((c) => c.name), [
        'Snacks',
      ]);
    });

    test('a miss reports empty rather than falling back to everything', () {
      expect(_catalog.search('absinthe').isEmpty, isTrue);
    });

    test('an ingredient hidden from search loses its row, not its product', () {
      final soda = product(
        id: 'p4',
        name: 'Highball',
        ingredients: const ['Lime', 'Soda water'],
        searchableIngredients: const ['Lime'],
      );
      final catalog = catalogWith(
        productsByCategory: {
          'c1': [soda],
        },
      );

      final results = catalog.search('soda');

      expect(results.ingredients, isEmpty);
      expect(results.products.map((p) => p.name), ['Highball']);
    });

    test('every ingredient is searchable when the API sends no subset', () {
      expect(_catalog.search('mint').ingredients, ['Mint']);
    });
  });

  group('SearchCatalog collections', () {
    test('a tag collects every product carrying it', () {
      expect(_catalog.productsWithTag('refreshing').map((p) => p.name), [
        'Mojito',
      ]);
    });

    test('an ingredient collects every product made with it', () {
      expect(_catalog.productsWithIngredient('Lime').map((p) => p.name), [
        'Mojito',
        'Margarita',
      ]);
    });

    test('a category collects its own products, and null collects all', () {
      expect(_catalog.productsFor('c2').map((p) => p.name), ['Salted Chips']);
      expect(_catalog.productsFor(null).length, 3);
    });
  });

  group('CatalogSearchField', () {
    testWidgets('shows the hint and reports what is typed', (tester) async {
      final controller = TextEditingController();
      addTearDown(controller.dispose);
      final typed = <String>[];

      await tester.pumpWidget(
        wrap(
          CatalogSearchField(
            controller: controller,
            onChanged: typed.add,
            onClear: () {},
          ),
        ),
      );

      expect(find.text('Search cocktails, mixers, snacks'), findsOneWidget);

      await tester.enterText(find.byType(TextField), 'moj');
      expect(typed, ['moj']);
    });

    testWidgets('the clear button only appears once something is typed', (
      tester,
    ) async {
      final controller = TextEditingController();
      addTearDown(controller.dispose);
      var cleared = 0;

      await tester.pumpWidget(
        wrap(
          CatalogSearchField(
            controller: controller,
            onChanged: (_) {},
            onClear: () => cleared++,
          ),
        ),
      );

      expect(find.byIcon(Icons.close_rounded), findsNothing);

      await tester.enterText(find.byType(TextField), 'moj');
      await tester.pump();

      expect(find.byIcon(Icons.close_rounded), findsOneWidget);

      await tester.tap(find.byIcon(Icons.close_rounded));
      expect(cleared, 1);
    });

    testWidgets('keeps the pill height the header is built around', (
      tester,
    ) async {
      final controller = TextEditingController();
      addTearDown(controller.dispose);

      await tester.pumpWidget(
        wrap(
          CatalogSearchField(
            controller: controller,
            onChanged: (_) {},
            onClear: () {},
          ),
        ),
      );

      expect(
        tester.getSize(find.byType(CatalogSearchField)).height,
        CatalogSearchField.height,
      );
    });
  });

  group('SearchResultsPanel', () {
    Widget panel({
      required String query,
      ValueChanged<ShopProduct>? onOpenProduct,
      void Function(String, List<ShopProduct>)? onOpenCollection,
    }) {
      return wrap(
        SearchResultsPanel(
          catalog: _catalog,
          results: _catalog.search(query),
          onOpenProduct: onOpenProduct ?? (_) {},
          onOpenCollection: onOpenCollection ?? (_, _) {},
        ),
      );
    }

    testWidgets('labels every row with the kind of thing it opens', (
      tester,
    ) async {
      await tester.pumpWidget(panel(query: 'lime'));

      expect(find.text('Mojito'), findsOneWidget);
      expect(find.text('Margarita'), findsOneWidget);
      expect(find.text('Lime'), findsOneWidget);
      expect(find.text('INGREDIENT'), findsOneWidget);
    });

    testWidgets('says so when nothing matched', (tester) async {
      await tester.pumpWidget(panel(query: 'absinthe'));

      expect(
        find.text('No matches found. Try a different search.'),
        findsOneWidget,
      );
    });

    testWidgets('floats over the page instead of replacing it', (tester) async {
      // What the screens do: the page keeps rendering, and the dropdown hangs
      // off the field on top of it.
      final controller = TextEditingController(text: 'salt');
      addTearDown(controller.dispose);
      final link = LayerLink();

      await tester.pumpWidget(
        MaterialApp(
          home: Scaffold(
            body: Stack(
              children: [
                Column(
                  children: [
                    // The 22pt page gutters both screens lay the field out on.
                    Padding(
                      padding: const EdgeInsets.symmetric(horizontal: 22),
                      child: CatalogSearchField(
                        controller: controller,
                        layerLink: link,
                        onChanged: (_) {},
                        onClear: () {},
                      ),
                    ),
                    const Text('the page underneath'),
                  ],
                ),
                SearchResultsDropdown(
                  link: link,
                  child: SearchResultsPanel(
                    catalog: _catalog,
                    results: _catalog.search('salt'),
                    onOpenProduct: (_) {},
                    onOpenCollection: (_, _) {},
                  ),
                ),
              ],
            ),
          ),
        ),
      );

      expect(find.text('the page underneath'), findsOneWidget);
      expect(find.text('Salted Chips'), findsOneWidget);

      // Wide as the field it hangs from: the page width less both gutters.
      final width = tester.getSize(find.byType(SearchResultsDropdown)).width;
      expect(width, tester.getSize(find.byType(CatalogSearchField)).width);
    });

    testWidgets('opens a product, and a collection for everything else', (
      tester,
    ) async {
      final opened = <String>[];
      final collections = <String, int>{};

      await tester.pumpWidget(
        panel(
          query: 'salt',
          onOpenProduct: (product) => opened.add(product.name),
          onOpenCollection: (title, products) =>
              collections[title] = products.length,
        ),
      );

      await tester.tap(find.text('Salted Chips'));
      await tester.tap(find.text('Salt'));

      expect(opened, ['Salted Chips']);
      expect(collections, {'Salt': 2});
    });
  });

  // A touch outside a focused field does not dismiss the keyboard on iOS, so
  // the field puts it away itself — and the dropdown it shares a tap group
  // with has to count as inside.
  group('search keyboard dismissal', () {
    Future<FocusNode> pumpSearch(WidgetTester tester) async {
      final controller = TextEditingController(text: 'salt');
      addTearDown(controller.dispose);
      final focusNode = FocusNode();
      addTearDown(focusNode.dispose);
      final link = LayerLink();
      final tapGroup = SearchTapGroup();

      await tester.pumpWidget(
        MaterialApp(
          home: Scaffold(
            body: Stack(
              children: [
                Column(
                  children: [
                    Padding(
                      padding: const EdgeInsets.symmetric(horizontal: 22),
                      child: CatalogSearchField(
                        controller: controller,
                        focusNode: focusNode,
                        layerLink: link,
                        tapGroup: tapGroup,
                        onChanged: (_) {},
                        onClear: () => focusNode.requestFocus(),
                      ),
                    ),
                    // Below the dropdown, so tapping it is a tap on the page
                    // rather than on the results.
                    const Expanded(
                      child: Align(
                        alignment: Alignment.bottomCenter,
                        child: Text('the page underneath'),
                      ),
                    ),
                  ],
                ),
                SearchResultsDropdown(
                  link: link,
                  tapGroup: tapGroup,
                  child: SearchResultsPanel(
                    catalog: _catalog,
                    results: _catalog.search('salt'),
                    onOpenProduct: (_) {},
                    onOpenCollection: (_, _) {},
                  ),
                ),
              ],
            ),
          ),
        ),
      );

      focusNode.requestFocus();
      await tester.pump();
      expect(focusNode.hasFocus, isTrue);

      return focusNode;
    }

    testWidgets('a tap on the page puts the keyboard away', (tester) async {
      final focusNode = await pumpSearch(tester);

      await tester.tap(find.text('the page underneath'));
      await tester.pump();

      expect(focusNode.hasFocus, isFalse);
    });

    testWidgets('a tap on the results does not', (tester) async {
      final focusNode = await pumpSearch(tester);

      await tester.tap(find.text('Salted Chips'));
      await tester.pump();

      expect(focusNode.hasFocus, isTrue);
    });

    testWidgets('nor does the clear button next to the field', (tester) async {
      final focusNode = await pumpSearch(tester);

      await tester.tap(find.byIcon(Icons.close_rounded));
      await tester.pump();

      expect(focusNode.hasFocus, isTrue);
    });
  });
}
