import '../core/constants/cocktail_assets.dart';
import '../core/utils/json_helpers.dart';

class FavoriteCocktailsResponse {
  final List<FavoriteCocktail> results;
  final int total;
  final int page;
  final int pageSize;

  const FavoriteCocktailsResponse({
    required this.results,
    required this.total,
    required this.page,
    required this.pageSize,
  });

  factory FavoriteCocktailsResponse.fromJson(Map<String, dynamic> json) {
    final meta = asMap(json['meta']);
    final results = readMapList(
      json['results'],
    ).map(FavoriteCocktail.fromJson).toList();

    return FavoriteCocktailsResponse(
      results: results,
      total: readInt(meta['total'], fallback: results.length),
      page: readInt(meta['page'], fallback: 1),
      pageSize: readInt(meta['page_size'], fallback: results.length),
    );
  }
}

class FavoriteCocktail {
  final String id;
  final String slug;
  final String name;
  final String? shortDescription;
  final String? imageUrl;
  final String productType;
  final bool isFavorite;
  final String? favoriteCreatedAt;
  final String imageAsset;

  const FavoriteCocktail({
    required this.id,
    required this.slug,
    required this.name,
    required this.shortDescription,
    required this.imageUrl,
    required this.productType,
    required this.isFavorite,
    required this.favoriteCreatedAt,
    required this.imageAsset,
  });

  factory FavoriteCocktail.fromJson(Map<String, dynamic> json) {
    final name = readString(json['name'], fallback: 'Cocktail');

    return FavoriteCocktail(
      id: readString(json['id'] ?? json['product_id']),
      slug: readString(json['slug']),
      name: name,
      shortDescription: nullableString(json['short_description']),
      imageUrl: nullableString(json['image_url']),
      productType: readString(json['product_type'], fallback: 'cocktail'),
      isFavorite: readBool(json['is_favorite'], fallback: true),
      favoriteCreatedAt: nullableString(json['favorite_created_at']),
      imageAsset: CocktailAssets.forName(name),
    );
  }

  FavoriteCocktail copyWith({bool? isFavorite}) {
    return FavoriteCocktail(
      id: id,
      slug: slug,
      name: name,
      shortDescription: shortDescription,
      imageUrl: imageUrl,
      productType: productType,
      isFavorite: isFavorite ?? this.isFavorite,
      favoriteCreatedAt: favoriteCreatedAt,
      imageAsset: imageAsset,
    );
  }
}
