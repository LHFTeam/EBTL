import '../core/utils/json_helpers.dart';
import 'shop_models.dart';

/// A banner in Home's "The Spotlight" rail.
///
/// Where a hero slide carries a deep link to somewhere the app already has, a
/// Spotlight banner's destination is always its own sheet: the same artwork
/// across the top, [title] and [subtitle] under it, and a grid of the products
/// marketing selected for it in the dashboard's Marketing → Banners tab
/// (`spotlight_banners`). The products are not on this payload — the sheet
/// fetches them when it opens.
class SpotlightBanner {
  final String id;
  final String imageUrl;
  final String title;
  final String? subtitle;
  final int displayOrder;

  const SpotlightBanner({
    required this.id,
    required this.imageUrl,
    required this.title,
    required this.subtitle,
    required this.displayOrder,
  });

  factory SpotlightBanner.fromJson(Map<String, dynamic> json) {
    return SpotlightBanner(
      id: readString(json['id']),
      imageUrl: readString(json['image_url']),
      title: readString(json['title']),
      subtitle: nullableString(json['subtitle']),
      displayOrder: readInt(json['display_order']),
    );
  }

  /// The backend requires an image, an id and a title, but the payload is
  /// treated as untrusted like every other model here: a banner missing any of
  /// them could neither be drawn in the rail nor open a sheet worth reading.
  bool get isRenderable =>
      id.trim().isNotEmpty &&
      imageUrl.trim().isNotEmpty &&
      title.trim().isNotEmpty;
}

/// `/customer/spotlight/:id/products`. The banner comes back with its products
/// so the sheet renders from this one response rather than depending on the home
/// payload it was opened from still being current.
class SpotlightProductsResponse {
  final SpotlightBanner banner;
  final List<ShopProduct> results;

  const SpotlightProductsResponse({
    required this.banner,
    required this.results,
  });

  factory SpotlightProductsResponse.fromJson(Map<String, dynamic> json) {
    return SpotlightProductsResponse(
      banner: SpotlightBanner.fromJson(asMap(json['banner'])),
      results: readMapList(json['results']).map(ShopProduct.fromJson).toList(),
    );
  }
}
