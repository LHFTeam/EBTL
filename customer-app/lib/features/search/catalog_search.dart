import 'package:flutter/material.dart';

import '../../models/cocktail_models.dart';
import '../../models/common_models.dart';
import '../../models/shop_models.dart';
import '../../services/api_service.dart';
import '../../shared/widgets/app_state_widgets.dart';
import '../shop/shop_product_loading.dart';
import '../shop/widgets/shop_product_detail_sheet.dart';

/// The catalog the search fields on Home and Explore both read from, and the
/// matching that turns a typed query into the grouped rows they show.
///
/// The customer API has no "all products" endpoint, so the catalog is stitched
/// together from every category (see [SearchCatalog.load]). Both surfaces
/// search the same stitched result client-side.

class SearchCatalog {
  /// Every category that came back with at least one product, in server order.
  final List<ShopCategory> categories;

  /// Products keyed by category id.
  final Map<String, List<ShopProduct>> productsByCategory;

  /// Deduped union of everything above.
  final List<ShopProduct> allProducts;

  const SearchCatalog({
    required this.categories,
    required this.productsByCategory,
    required this.allProducts,
  });

  List<ShopProduct> productsFor(String? categoryId) {
    if (categoryId == null) return allProducts;
    return productsByCategory[categoryId] ?? const [];
  }

  ShopCategory? categoryById(String? categoryId) {
    if (categoryId == null) return null;

    for (final category in categories) {
      if (category.id == categoryId) return category;
    }

    return null;
  }

  /// Loads the whole catalog for a beach cart.
  ///
  /// No "all products" endpoint exists, so every category is paged in parallel
  /// and the results are stitched into one catalog.
  static Future<SearchCatalog> load({required String? locationId}) async {
    final shop = await ApiService.fetchShop(locationId: locationId);

    final productLists = await Future.wait(
      shop.categories.map(
        (category) =>
            loadAllProductsInCategory(category, locationId: locationId),
      ),
    );

    final categories = <ShopCategory>[];
    final productsByCategory = <String, List<ShopProduct>>{};
    final combined = <ShopProduct>[];

    for (var index = 0; index < shop.categories.length; index++) {
      final category = shop.categories[index];
      final products = productLists[index];

      if (products.isEmpty) continue;

      categories.add(category);
      productsByCategory[category.id] = products;
      combined.addAll(products);
    }

    final allProducts = dedupeShopProducts(combined);

    // Fall back to the featured sections if the catalog came back empty, so a
    // misconfigured category list does not leave the screen blank.
    return SearchCatalog(
      categories: categories,
      productsByCategory: productsByCategory,
      allProducts: allProducts.isEmpty
          ? dedupeShopProducts(shop.allFeaturedProducts)
          : allProducts,
    );
  }

  /// The products, categories, tags and ingredients matching [query].
  SearchResults search(String query) {
    final clean = query.trim().toLowerCase();
    if (clean.isEmpty) return const SearchResults.empty();

    return SearchResults(
      products: allProducts
          .where((product) => product.matchesQuery(clean))
          .toList(),
      categories: categories
          .where((category) => category.matchesQuery(clean))
          .toList(),
      tags: _matchingValues(
        clean,
        allProducts.expand(
          (product) => [
            ...product.tags,
            ...product.tagDetails.map((tag) => tag.name),
          ],
        ),
      ),
      ingredients: _matchingValues(
        clean,
        allProducts.expand((product) => product.ingredientNames),
      ),
    );
  }

  /// Every product carrying [tag], as its own collection.
  List<ShopProduct> productsWithTag(String tag) {
    return _productsForValue(
      tag,
      (product) => [
        ...product.tags,
        ...product.tagDetails.map((item) => item.name),
      ],
    );
  }

  /// Every product made with [ingredient], as its own collection.
  List<ShopProduct> productsWithIngredient(String ingredient) {
    return _productsForValue(ingredient, (product) => product.ingredientNames);
  }

  List<ShopProduct> _productsForValue(
    String value,
    Iterable<String> Function(ShopProduct product) valuesForProduct,
  ) {
    final target = value.trim().toLowerCase();

    return allProducts
        .where(
          (product) => valuesForProduct(
            product,
          ).any((candidate) => candidate.trim().toLowerCase() == target),
        )
        .toList();
  }

  /// The distinct values containing [query], keeping the first spelling seen
  /// and sorted alphabetically.
  static List<String> _matchingValues(String query, Iterable<String> values) {
    final matches = <String, String>{};

    for (final value in values) {
      final clean = value.trim();
      if (clean.toLowerCase().contains(query)) {
        matches.putIfAbsent(clean.toLowerCase(), () => clean);
      }
    }

    final result = matches.values.toList();
    result.sort((a, b) => a.toLowerCase().compareTo(b.toLowerCase()));
    return result;
  }
}

/// What one query matched, grouped by the kind of row it becomes.
class SearchResults {
  final List<ShopProduct> products;
  final List<ShopCategory> categories;
  final List<String> tags;
  final List<String> ingredients;

  const SearchResults({
    required this.products,
    required this.categories,
    required this.tags,
    required this.ingredients,
  });

  const SearchResults.empty()
    : products = const [],
      categories = const [],
      tags = const [],
      ingredients = const [];

  bool get isEmpty =>
      products.isEmpty &&
      categories.isEmpty &&
      tags.isEmpty &&
      ingredients.isEmpty;

  bool get isNotEmpty => !isEmpty;
}

/// Opens a product picked out of search results the way both surfaces do: shop
/// items in the detail sheet, cocktails on their own screen.
Future<void> openCatalogProduct(
  BuildContext context, {
  required ShopProduct product,
  required String? locationId,
  required CartChangedCallback onCartChanged,
  required Future<void> Function(Cocktail cocktail) onOpenCocktail,
}) async {
  if (!product.isCocktail) {
    await showShopProductDetailSheet(
      context: context,
      product: product,
      locationId: locationId,
      onCartChanged: onCartChanged,
    );
    return;
  }

  if (product.slug.trim().isEmpty) {
    if (!context.mounted) return;
    showAppSnackBar(context, 'This cocktail is missing a detail link.');
    return;
  }

  await onOpenCocktail(Cocktail.fromShopProduct(product));
}
