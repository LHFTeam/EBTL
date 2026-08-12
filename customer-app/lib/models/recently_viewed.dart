import '../core/constants/cocktail_assets.dart';
import '../core/utils/json_helpers.dart';

/// One product the customer opened, as much of it as the "Recently viewed" rail
/// needs to draw a card.
///
/// The rail lives on Home, which does not load the shop catalog (that is a
/// request per category — see `SearchCatalog.load`), so the card is drawn from
/// this on-device snapshot instead of being resolved against a live catalog.
/// The snapshot is display-only: opening the card re-fetches the product by
/// slug, so the price and availability a customer acts on are always live.
class RecentlyViewedProduct {
  final String slug;
  final String name;
  final String? imageUrl;
  final String imageAsset;
  final String priceLabel;

  /// Cocktails open the full detail screen from their slug alone. Everything
  /// else needs the catalog entry the sheet is built from, which Home does not
  /// have — so only cocktails are offered there.
  final bool isCocktail;

  const RecentlyViewedProduct({
    required this.slug,
    required this.name,
    required this.imageUrl,
    required this.imageAsset,
    required this.priceLabel,
    required this.isCocktail,
  });

  factory RecentlyViewedProduct.fromJson(Map<String, dynamic> json) {
    return RecentlyViewedProduct(
      slug: readString(json['slug']),
      name: readString(json['name'], fallback: 'Product'),
      imageUrl: nullableString(json['image_url']),
      imageAsset: readString(
        json['image_asset'],
        fallback: CocktailAssets.forName(readString(json['name'])),
      ),
      priceLabel: readString(json['price_label']),
      isCocktail: readBool(json['is_cocktail']),
    );
  }

  Map<String, dynamic> toJson() {
    return {
      'slug': slug,
      'name': name,
      'image_url': imageUrl,
      'image_asset': imageAsset,
      'price_label': priceLabel,
      'is_cocktail': isCocktail,
    };
  }
}
