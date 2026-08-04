import '../core/utils/json_helpers.dart';

/// One spirit (a `liquor_types` row) as the profile sees it.
///
/// The same shape backs all three lists in the spirits payload: the customer's
/// favorites, the spirits the backend worked out they order most, and the full
/// picker of spirits they could add. `orderCount`/`rank` are only meaningful on
/// the most-ordered list and read as 0/1 elsewhere.
class ProfileSpirit {
  final String id;
  final String name;
  final String? imageUrl;
  final int displayOrder;
  final bool isFavorite;
  final int orderCount;
  final int rank;

  const ProfileSpirit({
    required this.id,
    required this.name,
    required this.imageUrl,
    required this.displayOrder,
    required this.isFavorite,
    required this.orderCount,
    required this.rank,
  });

  factory ProfileSpirit.fromJson(Map<String, dynamic> json) {
    final name = readString(json['name'], fallback: 'Bottle');

    return ProfileSpirit(
      id: readString(json['id'] ?? json['liquor_type_id'], fallback: name),
      name: name,
      imageUrl: nullableString(json['image_url']),
      displayOrder: readInt(json['display_order']),
      isFavorite: readBool(json['is_favorite']),
      orderCount: readInt(json['order_count']),
      rank: readInt(json['rank'], fallback: 1),
    );
  }

  /// "In 6 orders" — how the most-ordered list explains itself.
  String get orderCountLabel {
    if (orderCount <= 0) return '';
    return orderCount == 1 ? 'In 1 order' : 'In $orderCount orders';
  }
}

/// A titled list of spirits. Both the favorites and most-ordered blocks in the
/// payload carry their own copy so the wording stays server-side.
class SpiritSection {
  final String title;
  final String subtitle;
  final List<ProfileSpirit> items;

  const SpiritSection({
    required this.title,
    required this.subtitle,
    required this.items,
  });

  factory SpiritSection.fromJson(
    Map<String, dynamic> json, {
    required String fallbackTitle,
    String fallbackSubtitle = '',
  }) {
    return SpiritSection(
      title: readString(json['title'], fallback: fallbackTitle),
      subtitle: readString(json['subtitle'], fallback: fallbackSubtitle),
      items: readMapList(json['items']).map(ProfileSpirit.fromJson).toList(),
    );
  }

  int get count => items.length;

  bool get isEmpty => items.isEmpty;
}

/// The whole spirits payload: `GET /api/customer/spirits`, and the `spirits`
/// block the profile response embeds.
class ProfileSpirits {
  final SpiritSection favoriteSpirits;
  final SpiritSection topSpirits;
  final List<ProfileSpirit> availableSpirits;

  const ProfileSpirits({
    required this.favoriteSpirits,
    required this.topSpirits,
    required this.availableSpirits,
  });

  factory ProfileSpirits.fromJson(Map<String, dynamic> json) {
    return ProfileSpirits(
      favoriteSpirits: SpiritSection.fromJson(
        asMap(json['favorite_spirits']),
        fallbackTitle: 'My Spirits',
        fallbackSubtitle: 'The bottles you keep at hand',
      ),
      topSpirits: SpiritSection.fromJson(
        asMap(json['top_spirits']),
        fallbackTitle: 'Most Ordered',
      ),
      availableSpirits: readMapList(
        json['available_spirits'],
      ).map(ProfileSpirit.fromJson).toList(),
    );
  }

  static const empty = ProfileSpirits(
    favoriteSpirits: SpiritSection(
      title: 'My Spirits',
      subtitle: 'The bottles you keep at hand',
      items: [],
    ),
    topSpirits: SpiritSection(title: 'Most Ordered', subtitle: '', items: []),
    availableSpirits: [],
  );

  /// The spirits the customer has not favorited yet — what the add picker
  /// offers.
  List<ProfileSpirit> get addableSpirits {
    final favoriteIds = favoriteSpirits.items.map((spirit) => spirit.id).toSet();
    return availableSpirits
        .where((spirit) => !favoriteIds.contains(spirit.id))
        .toList();
  }
}
