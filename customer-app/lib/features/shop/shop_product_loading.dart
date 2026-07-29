import '../../models/shop_models.dart';
import '../../services/api_service.dart';

/// Product-catalog loading helpers shared by the Shop and Explore screens.
///
/// The customer API has no "all products" endpoint — products are only
/// reachable per category — so both screens page through
/// `/shop/categories/{identifier}/products` and stitch the results together.

/// Pages through a whole category and returns its deduped products.
Future<List<ShopProduct>> loadAllProductsInCategory(
  ShopCategory category, {
  required String? locationId,
}) async {
  final products = <ShopProduct>[];
  var page = 1;
  var hasMore = true;

  while (hasMore) {
    final response = await ApiService.fetchShopCategoryProducts(
      identifier: category.identifier,
      locationId: locationId,
      page: page,
      pageSize: 100,
      sort: 'display_order',
    );

    products.addAll(response.results);
    hasMore = response.meta.hasMore;
    page = response.meta.page + 1;

    if (response.results.isEmpty) {
      break;
    }
  }

  return dedupeShopProducts(products);
}

/// Resolves a loose target like `cocktails` against the server's categories,
/// falling back to the singular form (`cocktail`).
ShopCategory? categoryForTarget(ShopResponse shop, String target) {
  return shop.categoryByTarget(target) ??
      shop.categoryByTarget(singularCategoryTarget(target));
}

String singularCategoryTarget(String target) {
  final clean = target.trim().toLowerCase();

  if (clean.endsWith('ies') && clean.length > 3) {
    return '${clean.substring(0, clean.length - 3)}y';
  }

  if (clean.endsWith('s') && clean.length > 1) {
    return clean.substring(0, clean.length - 1);
  }

  return clean;
}

/// Client-side match used when the server has no category for a target — the
/// featured sections are filtered by category name/slug/product type instead.
List<ShopProduct> productsMatchingCategoryTarget(
  Iterable<ShopProduct> products,
  String target,
) {
  final cleanTarget = target.trim().toLowerCase();
  final singularTarget = singularCategoryTarget(cleanTarget);

  return dedupeShopProducts(
    products.where((product) {
      final categoryName = product.category?.name.trim().toLowerCase() ?? '';
      final categorySlug = product.category?.slug?.trim().toLowerCase() ?? '';
      final productType = product.productType.trim().toLowerCase();

      return categoryName == cleanTarget ||
          categoryName == singularTarget ||
          categoryName.contains(cleanTarget) ||
          categoryName.contains(singularTarget) ||
          categorySlug == cleanTarget ||
          categorySlug == singularTarget ||
          categorySlug.contains(cleanTarget) ||
          categorySlug.contains(singularTarget) ||
          productType == cleanTarget ||
          productType == singularTarget;
    }).toList(),
  );
}

/// Dedupes by product id and sorts by `display_order` then name.
List<ShopProduct> dedupeShopProducts(List<ShopProduct> products) {
  final byId = <String, ShopProduct>{};

  for (final product in products) {
    byId[product.id] = product;
  }

  final deduped = byId.values.toList();

  deduped.sort((a, b) {
    final orderCompare = a.displayOrder.compareTo(b.displayOrder);
    if (orderCompare != 0) return orderCompare;

    return a.name.toLowerCase().compareTo(b.name.toLowerCase());
  });

  return deduped;
}
