import '../core/utils/formatters.dart';
import '../core/utils/json_helpers.dart';

class CustomerSession {
  final String customerId;
  final String customerSessionToken;
  final String tokenType;

  const CustomerSession({
    required this.customerId,
    required this.customerSessionToken,
    required this.tokenType,
  });

  factory CustomerSession.fromJson(Map<String, dynamic> json) {
    return CustomerSession(
      customerId: readString(json['customer_id']),
      customerSessionToken: readString(json['customer_session_token']),
      tokenType: readString(json['token_type'], fallback: 'Bearer'),
    );
  }
}

class HeroContent {
  final String headline;
  final String subheadline;
  final String? imageUrl;
  final String primaryCtaLabel;

  const HeroContent({
    required this.headline,
    required this.subheadline,
    required this.imageUrl,
    required this.primaryCtaLabel,
  });

  factory HeroContent.fromJson(Map<String, dynamic> json) {
    return HeroContent(
      headline: readString(
        json['headline'],
        fallback: 'Premium mixers, garnishes, syrups & cocktail ingredients.',
      ),
      subheadline: readString(
        json['subheadline'],
        fallback: 'You bring the bottle. We bring the magic.',
      ),
      imageUrl: nullableString(json['image_url']),
      primaryCtaLabel: readString(
        json['primary_cta_label'],
        fallback: 'Find your cocktail',
      ),
    );
  }
}

class ServiceLocation {
  final String id;
  final String name;
  final String type;
  final String? compoundName;
  final String? beachName;
  final double? latitude;
  final double? longitude;
  final bool isActive;
  final bool isAvailable;

  const ServiceLocation({
    required this.id,
    required this.name,
    required this.type,
    required this.compoundName,
    required this.beachName,
    required this.latitude,
    required this.longitude,
    required this.isActive,
    required this.isAvailable,
  });

  factory ServiceLocation.fromJson(Map<String, dynamic> json) {
    return ServiceLocation(
      id: readString(json['id']),
      name: readString(json['name'], fallback: 'Beach Cart'),
      type: readString(json['type']),
      compoundName: nullableString(json['compound_name']),
      beachName: nullableString(json['beach_name']),
      latitude: readDouble(json['latitude']),
      longitude: readDouble(json['longitude']),
      isActive: readBool(json['is_active'], fallback: true),
      isAvailable: readBool(json['is_available'], fallback: true),
    );
  }

  String get subtitle => locationSubtitle(
    compoundName,
    beachName,
    fallback: 'Available service area',
  );
}

class ProductTag {
  final String id;
  final String name;
  final String colorHex;
  final int displayOrder;

  const ProductTag({
    required this.id,
    required this.name,
    required this.colorHex,
    required this.displayOrder,
  });

  factory ProductTag.fromJson(Map<String, dynamic> json) {
    return ProductTag(
      id: readString(json['id']),
      name: readString(json['name'], fallback: 'Tag'),
      colorHex: readString(json['color_hex'], fallback: '#1F6F68'),
      displayOrder: readInt(json['display_order']),
    );
  }
}

class Category {
  final String id;
  final String name;
  final int sortOrder;

  const Category({
    required this.id,
    required this.name,
    required this.sortOrder,
  });

  factory Category.fromJson(Map<String, dynamic> json) {
    return Category(
      id: readString(json['id']),
      name: readString(json['name'], fallback: 'Category'),
      sortOrder: readInt(json['sort_order']),
    );
  }
}

class CartSummary {
  final String cartId;
  final int itemCount;
  final int totalQuantity;
  final double subtotalIncVat;
  final String currency;

  const CartSummary({
    required this.cartId,
    required this.itemCount,
    required this.totalQuantity,
    required this.subtotalIncVat,
    required this.currency,
  });

  factory CartSummary.fromJson(Map<String, dynamic> json) {
    return CartSummary(
      cartId: readString(json['cart_id']),
      itemCount: readInt(json['item_count']),
      totalQuantity: readInt(json['total_quantity']),
      subtotalIncVat: readDouble(json['subtotal_inc_vat']) ?? 0,
      currency: readString(json['currency'], fallback: 'EGP'),
    );
  }

  String get subtotalLabel => formatMoney(subtotalIncVat, currency);

  /// A cart that was just emptied. Clearing the cart is the one cart write the
  /// backend answers without a summary — an empty cart has only one shape, so
  /// there is nothing to fetch back.
  factory CartSummary.emptied(String cartId) {
    return CartSummary(
      cartId: cartId,
      itemCount: 0,
      totalQuantity: 0,
      subtotalIncVat: 0,
      currency: 'EGP',
    );
  }
}

/// Announces that the cart changed, carrying the new summary when the caller
/// has it.
///
/// Every cart write comes back with the authoritative new summary, so passing
/// it lets the shell update the bottom-nav badge from that response instead of
/// refetching `/home` to learn what the write already said. Callers with
/// nothing to hand — a screen that only knows the cart moved — call it with no
/// argument and the shell refetches.
typedef CartChangedCallback = void Function([CartSummary? summary]);

class LiquorType {
  final String id;
  final String name;
  final String? imageUrl;
  final int displayOrder;

  const LiquorType({
    required this.id,
    required this.name,
    required this.imageUrl,
    required this.displayOrder,
  });

  factory LiquorType.fromJson(Map<String, dynamic> json) {
    final name = readString(json['name'], fallback: 'Bottle');

    return LiquorType(
      id: readString(json['id'], fallback: name),
      name: name,
      imageUrl: nullableString(json['image_url']),
      displayOrder: readInt(json['display_order']),
    );
  }
}
