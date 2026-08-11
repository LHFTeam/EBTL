import '../core/constants/cocktail_assets.dart';
import '../core/utils/formatters.dart';
import '../core/utils/json_helpers.dart';
import '../core/utils/model_sorters.dart';
import 'common_models.dart';
import 'product_models.dart';

class ShopBanner {
  final String? imageUrl;

  const ShopBanner({required this.imageUrl});

  factory ShopBanner.fromJson(Map<String, dynamic> json) {
    return ShopBanner(imageUrl: nullableString(json['image_url']));
  }
}

class ShopMeta {
  final String? locationId;

  const ShopMeta({required this.locationId});

  factory ShopMeta.fromJson(Map<String, dynamic> json) {
    return ShopMeta(locationId: nullableString(json['location_id']));
  }
}

class ShopCategory {
  final String id;
  final String name;
  final String? slug;
  final String? imageUrl;
  final int sortOrder;
  final int productCount;

  const ShopCategory({
    required this.id,
    required this.name,
    required this.slug,
    required this.imageUrl,
    required this.sortOrder,
    required this.productCount,
  });

  factory ShopCategory.fromJson(Map<String, dynamic> json) {
    return ShopCategory(
      id: readString(json['id']),
      name: readString(json['name'], fallback: 'Category'),
      slug: nullableString(json['slug']),
      imageUrl: nullableString(json['image_url']),
      sortOrder: readInt(json['sort_order']),
      productCount: readInt(json['product_count']),
    );
  }

  String get identifier {
    final cleanSlug = slug?.trim();
    if (cleanSlug != null && cleanSlug.isNotEmpty) return cleanSlug;
    return id;
  }

  bool matchesQuery(String query) {
    final clean = query.trim().toLowerCase();
    if (clean.isEmpty) return true;

    return name.toLowerCase().contains(clean) ||
        (slug ?? '').toLowerCase().contains(clean);
  }
}

List<ShopCategory> sortShopCategories(List<ShopCategory> categories) {
  return sortByOrderThenName(categories, (c) => c.sortOrder, (c) => c.name);
}

class ShopResponse {
  final ShopBanner banner;
  final List<ShopCategory> categories;
  final ShopSections sections;
  final CartSummary? cartSummary;
  final ShopMeta meta;

  const ShopResponse({
    required this.banner,
    required this.categories,
    required this.sections,
    required this.cartSummary,
    required this.meta,
  });

  factory ShopResponse.fromJson(Map<String, dynamic> json) {
    final cartMap = asMap(json['cartSummary'] ?? json['cart_summary']);

    return ShopResponse(
      banner: ShopBanner.fromJson(asMap(json['banner'])),
      categories: sortShopCategories(
        readMapList(json['categories']).map(ShopCategory.fromJson).toList(),
      ),
      sections: ShopSections.fromJson(asMap(json['sections'])),
      cartSummary: cartMap.isEmpty ? null : CartSummary.fromJson(cartMap),
      meta: ShopMeta.fromJson(asMap(json['meta'])),
    );
  }

  ShopCategory? categoryByTarget(String target) {
    final cleanTarget = target.trim().toLowerCase();

    for (final category in categories) {
      if (category.slug?.trim().toLowerCase() == cleanTarget) {
        return category;
      }
    }

    for (final category in categories) {
      if (category.name.trim().toLowerCase() == cleanTarget) {
        return category;
      }
    }

    for (final category in categories) {
      final name = category.name.trim().toLowerCase();
      final slug = category.slug?.trim().toLowerCase() ?? '';

      if (name.contains(cleanTarget) || slug.contains(cleanTarget)) {
        return category;
      }
    }

    return null;
  }

  List<ShopProduct> get allFeaturedProducts {
    final byId = <String, ShopProduct>{};

    for (final product in sections.featuredCocktails.items) {
      byId[product.id] = product;
    }

    for (final product in sections.snacksAndMore.items) {
      byId[product.id] = product;
    }

    return byId.values.toList();
  }
}

Map<String, dynamic> _readFirstMapByKeys(
  Map<String, dynamic> json,
  List<String> keys,
) {
  for (final key in keys) {
    final map = asMap(json[key]);
    if (map.isNotEmpty) return map;
  }

  return <String, dynamic>{};
}

class ShopSections {
  final ShopSection featuredCocktails;
  final ShopSection snacksAndMore;

  const ShopSections({
    required this.featuredCocktails,
    required this.snacksAndMore,
  });

  factory ShopSections.fromJson(Map<String, dynamic> json) {
    return ShopSections(
      featuredCocktails: ShopSection.fromJson(
        _readFirstMapByKeys(json, const [
          'featured_cocktails',
          'featuredCocktails',
          'cocktails',
        ]),
        fallbackTitle: 'Cocktails',
      ),
      snacksAndMore: ShopSection.fromJson(
        _readFirstMapByKeys(json, const [
          'snacks_and_more',
          'snacksAndMore',
          'snacks_essentials_and_more',
          'snacksEssentialsAndMore',
          'snacks_essentials_more',
          'non_cocktail_products',
        ]),
        fallbackTitle: 'Snacks, essentials and more',
      ),
    );
  }
}

class ShopSection {
  final String title;
  final List<ShopProduct> items;

  const ShopSection({required this.title, required this.items});

  factory ShopSection.fromJson(
    Map<String, dynamic> json, {
    required String fallbackTitle,
  }) {
    return ShopSection(
      title: readString(json['title'], fallback: fallbackTitle),
      items: readMapList(json['items']).map(ShopProduct.fromJson).toList(),
    );
  }
}

class ShopProduct {
  final String id;
  final String slug;
  final String name;
  final String productType;
  final String? shortDescription;
  final String? description;
  final String descriptionFormat;
  final String? imageUrl;
  final String imageAsset;
  final List<String> tags;
  final List<ProductTag> tagDetails;
  final List<String> ingredientNames;

  /// The subset of [ingredientNames] search may offer as its own result row.
  /// Admins keep noise like ice or water out of the results this way; the
  /// products still match on the hidden ones.
  final List<String> searchableIngredientNames;

  final int prepTimeMinutes;
  final bool isFeatured;
  final int displayOrder;
  final ShopCategory? category;
  final double? startingPriceIncVat;
  final String currency;
  final List<ProductVariant> variants;
  final List<LiquorCompatibility> compatibility;
  final Availability availability;

  const ShopProduct({
    required this.id,
    required this.slug,
    required this.name,
    required this.productType,
    required this.shortDescription,
    required this.description,
    required this.descriptionFormat,
    required this.imageUrl,
    required this.imageAsset,
    required this.tags,
    required this.tagDetails,
    required this.ingredientNames,
    required this.searchableIngredientNames,
    required this.prepTimeMinutes,
    required this.isFeatured,
    required this.displayOrder,
    required this.category,
    required this.startingPriceIncVat,
    required this.currency,
    required this.variants,
    required this.compatibility,
    required this.availability,
  });

  factory ShopProduct.fromJson(Map<String, dynamic> json) {
    final name = readString(json['name'], fallback: 'Product');
    final price = asMap(json['price']);
    final categoryMap = asMap(json['category']);
    final ingredientNames = readStringList(json['ingredient_names']);

    return ShopProduct(
      id: readString(json['id']),
      slug: readString(json['slug']),
      name: name,
      productType: readString(json['product_type'], fallback: 'product'),
      shortDescription: nullableString(json['short_description']),
      description: nullableString(json['description']),
      descriptionFormat: readString(
        json['description_format'],
        fallback: 'markdown',
      ),
      imageUrl: nullableString(json['image_url']),
      imageAsset: CocktailAssets.forName(name),
      tags: readStringList(json['tags']),
      tagDetails: sortProductTags(
        readMapList(json['tag_details']).map(ProductTag.fromJson).toList(),
      ),
      ingredientNames: ingredientNames,
      // An API that predates the flag sends no list at all, and every
      // ingredient stays searchable the way it was before.
      searchableIngredientNames: json.containsKey('searchable_ingredient_names')
          ? readStringList(json['searchable_ingredient_names'])
          : ingredientNames,
      prepTimeMinutes: readInt(json['prep_time_minutes'], fallback: 5),
      isFeatured: readBool(json['is_featured']),
      displayOrder: readInt(json['display_order']),
      category: categoryMap.isEmpty ? null : ShopCategory.fromJson(categoryMap),
      startingPriceIncVat: readDouble(
        price['starting_price_inc_vat'] ?? json['starting_price_inc_vat'],
      ),
      currency: readString(
        price['currency'] ?? json['currency'],
        fallback: 'EGP',
      ),
      variants: readMapList(
        json['variants'],
      ).map(ProductVariant.fromJson).toList(),
      compatibility: readMapList(
        json['compatibility'],
      ).map(LiquorCompatibility.fromJson).toList(),
      availability: Availability.fromJson(asMap(json['availability'])),
    );
  }

  bool get isCocktail => productType == 'cocktail';

  ProductVariant? get firstOrderableVariant {
    for (final variant in variants) {
      if (variant.isActive && variant.availability.isOrderable) {
        return variant;
      }
    }

    return null;
  }

  ProductVariant? get defaultVariant {
    if (firstOrderableVariant != null) return firstOrderableVariant;
    if (variants.isNotEmpty) return variants.first;
    return null;
  }

  String get subtitle {
    final variantName = defaultVariant?.name.trim();

    if (isCocktail && variantName != null && variantName.isNotEmpty) {
      return variantName;
    }

    final shortText = shortDescription?.trim();
    if (shortText != null && shortText.isNotEmpty) return shortText;

    final categoryName = category?.name.trim();
    if (categoryName != null && categoryName.isNotEmpty) return categoryName;

    return productTypeLabel;
  }

  String get productTypeLabel {
    switch (productType) {
      case 'snack':
        return 'Snacks';
      case 'essential':
        return 'Beach Essentials';
      case 'bundle':
        return 'Bundles';
      case 'add_on':
        return 'Add-ons';
      case 'cocktail':
        return 'Cocktails';
      default:
        return 'Products';
    }
  }

  String get priceLabel =>
      formatOptionalPrice(startingPriceIncVat, currency);

  String get unavailableReason {
    final reason = availability.reason?.trim();
    if (reason != null && reason.isNotEmpty) return reason;

    final variantReason = defaultVariant?.availability.reason?.trim();
    if (variantReason != null && variantReason.isNotEmpty) {
      return variantReason;
    }

    return 'This item is currently unavailable.';
  }

  bool matchesQuery(String query) {
    final clean = query.trim().toLowerCase();
    if (clean.isEmpty) return true;

    final searchable = [
      name,
      productType,
      shortDescription ?? '',
      description ?? '',
      category?.name ?? '',
      ...tags,
      ...tagDetails.map((tag) => tag.name),
      ...ingredientNames,
    ].join(' ').toLowerCase();

    return searchable.contains(clean);
  }
}

class ShopCategoryProductsResponse {
  final ShopCategory? category;
  final List<ShopProduct> results;
  final ShopCategoryProductsMeta meta;

  const ShopCategoryProductsResponse({
    required this.category,
    required this.results,
    required this.meta,
  });

  factory ShopCategoryProductsResponse.fromJson(Map<String, dynamic> json) {
    final categoryMap = asMap(json['category']);
    final results = readMapList(
      json['results'],
    ).map(ShopProduct.fromJson).toList();

    return ShopCategoryProductsResponse(
      category: categoryMap.isEmpty ? null : ShopCategory.fromJson(categoryMap),
      results: results,
      meta: ShopCategoryProductsMeta.fromJson(
        asMap(json['meta']),
        fallbackCount: results.length,
      ),
    );
  }
}

class ShopCategoryProductsMeta {
  final int total;
  final int page;
  final int pageSize;
  final bool hasMore;
  final String? locationId;
  final String sort;

  const ShopCategoryProductsMeta({
    required this.total,
    required this.page,
    required this.pageSize,
    required this.hasMore,
    required this.locationId,
    required this.sort,
  });

  factory ShopCategoryProductsMeta.fromJson(
    Map<String, dynamic> json, {
    required int fallbackCount,
  }) {
    return ShopCategoryProductsMeta(
      total: readInt(json['total'], fallback: fallbackCount),
      page: readInt(json['page'], fallback: 1),
      pageSize: readInt(json['page_size'], fallback: 24),
      hasMore: readBool(json['has_more']),
      locationId: nullableString(json['location_id']),
      sort: readString(json['sort'], fallback: 'display_order'),
    );
  }
}
