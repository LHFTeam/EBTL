import '../core/utils/json_helpers.dart';
import 'shop_models.dart';

/// Which sheet tapping a [SpotlightBanner] opens. Parsed from `content_type`;
/// anything the backend does not send or that this app does not recognise
/// falls back to [products] — the original and still the default behaviour —
/// so an older or unexpected payload keeps working rather than opening
/// nothing.
enum SpotlightContentType { products, markdown }

/// A banner in Home's "The Spotlight" rail.
///
/// Where a hero slide carries a deep link to somewhere the app already has, a
/// Spotlight banner's destination is always its own sheet: the same artwork
/// across the top, then either [title] and [subtitle] under it with a grid of
/// the products marketing selected for it in the dashboard's Marketing →
/// Banners tab (`spotlight_banners`), or — when [contentType] is
/// [SpotlightContentType.markdown] — [markdownBody] rendered as a slide, whose
/// own heading takes the title's place. The products are not on this payload;
/// the product-grid sheet fetches them when it opens.
class SpotlightBanner {
  final String id;
  final String imageUrl;
  final String title;
  final String? subtitle;
  final int displayOrder;
  final SpotlightContentType contentType;
  final String? markdownBody;

  const SpotlightBanner({
    required this.id,
    required this.imageUrl,
    required this.title,
    required this.subtitle,
    required this.displayOrder,
    this.contentType = SpotlightContentType.products,
    this.markdownBody,
  });

  factory SpotlightBanner.fromJson(Map<String, dynamic> json) {
    return SpotlightBanner(
      id: readString(json['id']),
      imageUrl: readString(json['image_url']),
      title: readString(json['title']),
      subtitle: nullableString(json['subtitle']),
      displayOrder: readInt(json['display_order']),
      contentType: readString(json['content_type']) == 'markdown'
          ? SpotlightContentType.markdown
          : SpotlightContentType.products,
      markdownBody: nullableString(json['markdown_body']),
    );
  }

  /// A markdown banner with nothing to show is treated as a products banner
  /// would be with no selection: [isRenderable] does not depend on it, since
  /// the rail card only ever needs the artwork — the empty state is the open
  /// sheet's problem, same split as an empty product grid.
  bool get isMarkdownSlide =>
      contentType == SpotlightContentType.markdown &&
      (markdownBody?.trim().isNotEmpty ?? false);

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
