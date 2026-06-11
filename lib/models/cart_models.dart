import '../core/constants/cocktail_assets.dart';
import '../core/constants/fulfillment_types.dart';
import '../core/utils/formatters.dart';
import '../core/utils/json_helpers.dart';
import 'product_models.dart';

class CartPageResponse {
  final CartInfo? cart;
  final CartLocation? selectedLocation;
  final List<CartPageItem> items;
  final CartTotals totals;
  final CheckoutReadiness checkoutReadiness;

  const CartPageResponse({
    required this.cart,
    required this.selectedLocation,
    required this.items,
    required this.totals,
    required this.checkoutReadiness,
  });

  factory CartPageResponse.fromJson(Map<String, dynamic> json) {
    final cartMap = asMap(json['cart']);
    final locationMap = asMap(json['selected_location']);

    return CartPageResponse(
      cart: cartMap.isEmpty ? null : CartInfo.fromJson(cartMap),
      selectedLocation: locationMap.isEmpty
          ? null
          : CartLocation.fromJson(locationMap),
      items: readMapList(json['items']).map(CartPageItem.fromJson).toList(),
      totals: CartTotals.fromJson(asMap(json['totals'])),
      checkoutReadiness: CheckoutReadiness.fromJson(
        asMap(json['checkoutReadiness'] ?? json['checkout_readiness']),
      ),
    );
  }

  bool get isEmpty => items.isEmpty;
}

class CartInfo {
  final String id;
  final List<String> selectedLiquorTypeIds;
  final String status;
  final String? expiresAt;
  final String? createdAt;
  final String? updatedAt;
  final String fulfillmentType;

  const CartInfo({
    required this.id,
    required this.selectedLiquorTypeIds,
    required this.status,
    required this.expiresAt,
    required this.createdAt,
    required this.updatedAt,
    required this.fulfillmentType,
  });

  factory CartInfo.fromJson(Map<String, dynamic> json) {
    return CartInfo(
      id: readString(json['id']),
      selectedLiquorTypeIds: readStringList(json['selected_liquor_type_ids']),
      status: readString(json['status'], fallback: 'active'),
      expiresAt: nullableString(json['expires_at']),
      createdAt: nullableString(json['created_at']),
      updatedAt: nullableString(json['updated_at']),
      fulfillmentType: readString(
        json['fulfillment_type'],
        fallback: FulfillmentTypes.pickupAtCart,
      ),
    );
  }
}

class CartLocation {
  final String id;
  final String name;
  final String type;
  final String? compoundName;
  final String? beachName;
  final String? bannerImageUrl;
  final bool isActive;
  final LocationCurrentStatus currentStatus;

  const CartLocation({
    required this.id,
    required this.name,
    required this.type,
    required this.compoundName,
    required this.beachName,
    required this.bannerImageUrl,
    required this.isActive,
    required this.currentStatus,
  });

  factory CartLocation.fromJson(Map<String, dynamic> json) {
    return CartLocation(
      id: readString(json['id']),
      name: readString(json['name'], fallback: 'Beach Cart'),
      type: readString(json['type']),
      compoundName: nullableString(json['compound_name']),
      beachName: nullableString(json['beach_name']),
      bannerImageUrl: nullableString(json['banner_image_url']),
      isActive: readBool(json['is_active'], fallback: true),
      currentStatus: LocationCurrentStatus.fromJson(
        asMap(json['current_status']),
      ),
    );
  }

  String get subtitle {
    final parts = [
      compoundName,
      beachName,
    ].whereType<String>().where((part) => part.trim().isNotEmpty).toList();

    return parts.isEmpty ? 'Selected beach cart' : parts.join(' • ');
  }
}

class LocationCurrentStatus {
  final String timezone;
  final bool isOpen;
  final String label;

  const LocationCurrentStatus({
    required this.timezone,
    required this.isOpen,
    required this.label,
  });

  factory LocationCurrentStatus.fromJson(Map<String, dynamic> json) {
    return LocationCurrentStatus(
      timezone: readString(json['timezone'], fallback: 'Africa/Cairo'),
      isOpen: readBool(json['is_open']),
      label: readString(json['label'], fallback: 'Hours unavailable'),
    );
  }
}

class CartPageItem {
  final String id;
  final String productId;
  final String variantId;
  final int quantity;
  final CartProduct product;
  final CartVariant variant;
  final CartPricing pricing;
  final CartItemCustomization? customization;
  final Availability availability;

  const CartPageItem({
    required this.id,
    required this.productId,
    required this.variantId,
    required this.quantity,
    required this.product,
    required this.variant,
    required this.pricing,
    required this.customization,
    required this.availability,
  });

  factory CartPageItem.fromJson(Map<String, dynamic> json) {
    return CartPageItem(
      id: readString(json['id']),
      productId: readString(json['product_id']),
      variantId: readString(json['variant_id']),
      quantity: readInt(json['quantity'], fallback: 1),
      product: CartProduct.fromJson(asMap(json['product'])),
      variant: CartVariant.fromJson(asMap(json['variant'])),
      pricing: CartPricing.fromJson(asMap(json['pricing'])),
      customization: json['customization'] is Map
          ? CartItemCustomization.fromJson(asMap(json['customization']))
          : null,
      availability: Availability.fromJson(asMap(json['availability'])),
    );
  }

  String get lineTotalLabel =>
      formatMoney(pricing.lineTotalIncVat, pricing.currency);

  String get unitPriceLabel =>
      formatMoney(pricing.unitPriceIncVat, pricing.currency);

  String? get customizationSummary {
    final summary = customization?.summary?.trim();
    if (summary == null || summary.isEmpty) return null;
    return summary;
  }
}

class CartItemCustomization {
  final String hash;
  final String? summary;
  final double baseUnitPriceIncVat;
  final double customizationTotalIncVat;
  final List<CartRemovedIngredient> removedIngredients;
  final List<CartAddition> additions;

  const CartItemCustomization({
    required this.hash,
    required this.summary,
    required this.baseUnitPriceIncVat,
    required this.customizationTotalIncVat,
    required this.removedIngredients,
    required this.additions,
  });

  factory CartItemCustomization.fromJson(Map<String, dynamic> json) {
    return CartItemCustomization(
      hash: readString(json['hash'], fallback: 'base'),
      summary: nullableString(json['summary']),
      baseUnitPriceIncVat: readDouble(json['base_unit_price_inc_vat']) ?? 0,
      customizationTotalIncVat:
          readDouble(json['customization_total_inc_vat']) ?? 0,
      removedIngredients: readMapList(
        json['removed_ingredients'],
      ).map(CartRemovedIngredient.fromJson).toList(),
      additions: readMapList(
        json['additions'],
      ).map(CartAddition.fromJson).toList(),
    );
  }
}

class CartRemovedIngredient {
  final String? recipeItemId;
  final String? ingredientId;
  final String? name;
  final num? quantity;
  final String? unit;

  const CartRemovedIngredient({
    required this.recipeItemId,
    required this.ingredientId,
    required this.name,
    required this.quantity,
    required this.unit,
  });

  factory CartRemovedIngredient.fromJson(Map<String, dynamic> json) {
    return CartRemovedIngredient(
      recipeItemId: nullableString(json['recipe_item_id']),
      ingredientId: nullableString(json['ingredient_id']),
      name: nullableString(json['name']),
      quantity: readDouble(json['quantity']),
      unit: nullableString(json['unit']),
    );
  }
}

class CartAddition {
  final String? productId;
  final String? variantId;
  final String? recipeId;
  final String? name;
  final String? variantName;
  final int quantityPerParent;
  final double unitPriceIncVat;
  final double lineUnitPriceIncVat;
  final double vatRate;
  final String currency;

  const CartAddition({
    required this.productId,
    required this.variantId,
    required this.recipeId,
    required this.name,
    required this.variantName,
    required this.quantityPerParent,
    required this.unitPriceIncVat,
    required this.lineUnitPriceIncVat,
    required this.vatRate,
    required this.currency,
  });

  factory CartAddition.fromJson(Map<String, dynamic> json) {
    return CartAddition(
      productId: nullableString(json['product_id']),
      variantId: nullableString(json['variant_id']),
      recipeId: nullableString(json['recipe_id']),
      name: nullableString(json['name']),
      variantName: nullableString(json['variant_name']),
      quantityPerParent: readInt(json['quantity_per_parent'], fallback: 1),
      unitPriceIncVat: readDouble(json['unit_price_inc_vat']) ?? 0,
      lineUnitPriceIncVat: readDouble(json['line_unit_price_inc_vat']) ?? 0,
      vatRate: readDouble(json['vat_rate']) ?? 0,
      currency: readString(json['currency'], fallback: 'EGP'),
    );
  }
}

class CartProduct {
  final String slug;
  final String name;
  final String? shortDescription;
  final String? imageUrl;
  final String status;
  final String imageAsset;

  const CartProduct({
    required this.slug,
    required this.name,
    required this.shortDescription,
    required this.imageUrl,
    required this.status,
    required this.imageAsset,
  });

  factory CartProduct.fromJson(Map<String, dynamic> json) {
    final name = readString(
      json['name'] ?? json['product_name'],
      fallback: 'Cocktail',
    );

    return CartProduct(
      slug: readString(json['slug']),
      name: name,
      shortDescription: nullableString(json['short_description']),
      imageUrl: nullableString(
        json['image_url'] ?? json['product_image_url'] ?? json['thumbnail_url'],
      ),
      status: readString(json['status'], fallback: 'active'),
      imageAsset: CocktailAssets.forName(name),
    );
  }
}

class CartVariant {
  final String name;
  final int servingCount;
  final bool isActive;

  const CartVariant({
    required this.name,
    required this.servingCount,
    required this.isActive,
  });

  factory CartVariant.fromJson(Map<String, dynamic> json) {
    return CartVariant(
      name: readString(json['name'], fallback: 'Serving'),
      servingCount: readInt(json['serving_count'], fallback: 1),
      isActive: readBool(json['is_active'], fallback: true),
    );
  }
}

class CartPricing {
  final double unitPriceIncVat;
  final double lineTotalIncVat;
  final String currency;

  const CartPricing({
    required this.unitPriceIncVat,
    required this.lineTotalIncVat,
    required this.currency,
  });

  factory CartPricing.fromJson(Map<String, dynamic> json) {
    return CartPricing(
      unitPriceIncVat: readDouble(json['unit_price_inc_vat']) ?? 0,
      lineTotalIncVat: readDouble(json['line_total_inc_vat']) ?? 0,
      currency: readString(json['currency'], fallback: 'EGP'),
    );
  }
}

class CartTotals {
  final double subtotalIncVat;
  final double estimatedVatAmount;
  final double discountAmount;
  final double deliveryFee;
  final double totalAmount;
  final String currency;

  const CartTotals({
    required this.subtotalIncVat,
    required this.estimatedVatAmount,
    required this.discountAmount,
    required this.deliveryFee,
    required this.totalAmount,
    required this.currency,
  });

  factory CartTotals.fromJson(Map<String, dynamic> json) {
    return CartTotals(
      subtotalIncVat: readDouble(json['subtotal_inc_vat']) ?? 0,
      estimatedVatAmount: readDouble(json['estimated_vat_amount']) ?? 0,
      discountAmount: readDouble(json['discount_amount']) ?? 0,
      deliveryFee: readDouble(json['delivery_fee']) ?? 0,
      totalAmount: readDouble(json['total_amount']) ?? 0,
      currency: readString(json['currency'], fallback: 'EGP'),
    );
  }

  String get subtotalLabel => formatMoney(subtotalIncVat, currency);
  String get deliveryFeeLabel => formatMoney(deliveryFee, currency);
  String get totalLabel => formatMoney(totalAmount, currency);
}

class CheckoutReadiness {
  final bool canCheckout;
  final List<String> blockingReasons;

  const CheckoutReadiness({
    required this.canCheckout,
    required this.blockingReasons,
  });

  factory CheckoutReadiness.fromJson(Map<String, dynamic> json) {
    return CheckoutReadiness(
      canCheckout: readBool(json['can_checkout']),
      blockingReasons: readStringList(json['blocking_reasons']),
    );
  }

  String? get firstBlockingReason {
    if (blockingReasons.isEmpty) return null;
    return blockingReasons.first;
  }
}
