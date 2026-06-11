import '../core/constants/cocktail_assets.dart';
import '../core/utils/formatters.dart';
import '../core/utils/json_helpers.dart';
import '../core/utils/model_sorters.dart';
import 'common_models.dart';
import 'product_models.dart';
import 'shop_models.dart';

class CocktailSearchResult {
  final List<Cocktail> results;
  final int total;
  final int page;
  final int pageSize;

  const CocktailSearchResult({
    required this.results,
    required this.total,
    required this.page,
    required this.pageSize,
  });

  factory CocktailSearchResult.fromJson(Map<String, dynamic> json) {
    final meta = asMap(json['meta']);
    final results = readMapList(
      json['results'],
    ).map(Cocktail.fromCustomerJson).toList();

    return CocktailSearchResult(
      results: results,
      total: readInt(meta['total'], fallback: results.length),
      page: readInt(meta['page'], fallback: 1),
      pageSize: readInt(meta['page_size'], fallback: results.length),
    );
  }
}

class Cocktail {
  final String id;
  final String slug;
  final String name;
  final String? shortDescription;
  final String? description;
  final String descriptionFormat;
  final String imageAsset;
  final String? imageUrl;
  final bool isFeatured;
  final List<String> tags;
  final List<ProductTag> tagDetails;
  final int prepTimeMinutes;
  final Category? category;
  final double? startingPriceIncVat;
  final String currency;
  final List<ProductVariant> variants;
  final List<LiquorCompatibility> compatibility;
  final Availability availability;
  final bool isFavorite;
  final String? favoriteCreatedAt;

  const Cocktail({
    required this.id,
    required this.slug,
    required this.name,
    required this.shortDescription,
    required this.description,
    required this.descriptionFormat,
    required this.imageAsset,
    this.imageUrl,
    required this.isFeatured,
    required this.tags,
    required this.tagDetails,
    required this.prepTimeMinutes,
    required this.category,
    required this.startingPriceIncVat,
    required this.currency,
    required this.variants,
    required this.compatibility,
    required this.availability,
    required this.isFavorite,
    required this.favoriteCreatedAt,
  });

  factory Cocktail.fromCustomerJson(Map<String, dynamic> json) {
    final name = readString(json['name'], fallback: 'Cocktail');
    final price = asMap(json['price']);

    return Cocktail(
      id: readString(json['id']),
      slug: readString(json['slug']),
      name: name,
      shortDescription: nullableString(json['short_description']),
      description: nullableString(json['description']),
      descriptionFormat: readString(
        json['description_format'],
        fallback: 'markdown',
      ),
      imageUrl: nullableString(json['image_url']),
      imageAsset: CocktailAssets.forName(name),
      isFeatured: readBool(json['is_featured']),
      tags: readStringList(json['tags']),
      tagDetails: sortProductTags(
        readMapList(json['tag_details']).map(ProductTag.fromJson).toList(),
      ),
      prepTimeMinutes: readInt(json['prep_time_minutes'], fallback: 5),
      category: json['category'] is Map<String, dynamic>
          ? Category.fromJson(asMap(json['category']))
          : null,
      startingPriceIncVat: readDouble(price['starting_price_inc_vat']),
      currency: readString(price['currency'], fallback: 'EGP'),
      variants: readMapList(
        json['variants'],
      ).map(ProductVariant.fromJson).toList(),
      compatibility: readMapList(
        json['compatibility'],
      ).map(LiquorCompatibility.fromJson).toList(),
      availability: Availability.fromJson(asMap(json['availability'])),
      isFavorite: readBool(json['is_favorite']),
      favoriteCreatedAt: nullableString(json['favorite_created_at']),
    );
  }

  factory Cocktail.fromShopProduct(ShopProduct product) {
    final category = product.category;

    return Cocktail(
      id: product.id,
      slug: product.slug,
      name: product.name,
      shortDescription: product.shortDescription,
      description: product.description,
      descriptionFormat: product.descriptionFormat,
      imageAsset: product.imageAsset,
      imageUrl: product.imageUrl,
      isFeatured: product.isFeatured,
      tags: product.tags,
      tagDetails: product.tagDetails,
      prepTimeMinutes: product.prepTimeMinutes,
      category: category == null
          ? null
          : Category(
              id: category.id,
              name: category.name,
              sortOrder: category.sortOrder,
            ),
      startingPriceIncVat: product.startingPriceIncVat,
      currency: product.currency,
      variants: product.variants,
      compatibility: product.compatibility,
      availability: product.availability,
      isFavorite: false,
      favoriteCreatedAt: null,
    );
  }

  String get cardSubtitle {
    final text = shortDescription?.trim();
    if (text == null || text.isEmpty) return '';
    return text;
  }

  List<ProductTag> get sortedTagDetails => sortProductTags(tagDetails);

  String get detailDescription {
    final text = description?.trim();
    if (text == null || text.isEmpty) return '';
    return text;
  }

  String get usingLabel {
    if (compatibility.isEmpty) return 'Any bottle';

    final names = compatibility
        .map((item) => item.liquorTypeName.trim())
        .where((name) => name.isNotEmpty)
        .take(2)
        .toList();

    if (names.isEmpty) return 'Any bottle';

    final extraCount = compatibility.length - names.length;
    return extraCount > 0
        ? '${names.join(', ')} +$extraCount'
        : names.join(', ');
  }

  String get priceLabel {
    final price = startingPriceIncVat;
    if (price == null) return currency;
    return formatMoney(price, currency);
  }
}
