import '../core/constants/cocktail_assets.dart';
import '../core/constants/fulfillment_types.dart';
import '../core/utils/formatters.dart';
import '../core/utils/json_helpers.dart';
import 'cart_models.dart';

class CheckoutPageResponse {
  final CheckoutData checkout;

  const CheckoutPageResponse({required this.checkout});

  factory CheckoutPageResponse.fromJson(Map<String, dynamic> json) {
    return CheckoutPageResponse(
      checkout: CheckoutData.fromJson(asMap(json['checkout'])),
    );
  }
}

class CheckoutData {
  final String cartId;
  final String? cartExpiresAt;
  final CheckoutLocation? location;
  final CheckoutFulfillment fulfillment;
  final CheckoutCustomer customer;
  final List<CheckoutItem> items;
  final List<CheckoutItemWarning> itemWarnings;
  final CheckoutSummary summary;
  final CheckoutPromotion? promotion;
  final List<CheckoutPaymentMethod> paymentMethods;
  final CheckoutValidation validation;

  const CheckoutData({
    required this.cartId,
    required this.cartExpiresAt,
    required this.location,
    required this.fulfillment,
    required this.customer,
    required this.items,
    required this.itemWarnings,
    required this.summary,
    required this.promotion,
    required this.paymentMethods,
    required this.validation,
  });

  factory CheckoutData.fromJson(Map<String, dynamic> json) {
    final locationMap = asMap(json['location']);
    final promotionMap = asMap(json['promotion']);

    return CheckoutData(
      cartId: readString(json['cart_id']),
      cartExpiresAt: nullableString(json['cart_expires_at']),
      location: locationMap.isEmpty
          ? null
          : CheckoutLocation.fromJson(locationMap),
      fulfillment: CheckoutFulfillment.fromJson(asMap(json['fulfillment'])),
      customer: CheckoutCustomer.fromJson(asMap(json['customer'])),
      items: readMapList(json['items']).map(CheckoutItem.fromJson).toList(),
      itemWarnings: readMapList(
        json['item_warnings'],
      ).map(CheckoutItemWarning.fromJson).toList(),
      summary: CheckoutSummary.fromJson(asMap(json['summary'])),
      promotion: promotionMap.isEmpty
          ? null
          : CheckoutPromotion.fromJson(promotionMap),
      paymentMethods: readMapList(
        json['payment_methods'],
      ).map(CheckoutPaymentMethod.fromJson).toList(),
      validation: CheckoutValidation.fromJson(asMap(json['validation'])),
    );
  }

  int get totalQuantity {
    return items.fold<int>(0, (sum, item) => sum + item.quantity);
  }

  List<CheckoutPaymentMethod> get enabledPaymentMethods {
    return paymentMethods
        .where((method) => method.enabled && method.isAllowedCheckoutMethod)
        .toList();
  }

  CheckoutPaymentMethod? paymentMethodByKey(String? key) {
    if (key == null || key.trim().isEmpty) return null;

    for (final method in enabledPaymentMethods) {
      if (method.key == key) return method;
    }

    return null;
  }
}

class CheckoutLocation {
  final String id;
  final String name;
  final String type;
  final String? compoundName;
  final String? beachName;
  final String? bannerImageUrl;
  final double deliveryFee;
  final bool isActive;
  final LocationCurrentStatus currentStatus;

  const CheckoutLocation({
    required this.id,
    required this.name,
    required this.type,
    required this.compoundName,
    required this.beachName,
    required this.bannerImageUrl,
    required this.deliveryFee,
    required this.isActive,
    required this.currentStatus,
  });

  factory CheckoutLocation.fromJson(Map<String, dynamic> json) {
    return CheckoutLocation(
      id: readString(json['id']),
      name: readString(json['name'], fallback: 'Beach Cart'),
      type: readString(json['type']),
      compoundName: nullableString(json['compound_name']),
      beachName: nullableString(json['beach_name']),
      bannerImageUrl: nullableString(json['banner_image_url']),
      deliveryFee: readDouble(json['delivery_fee']) ?? 0,
      isActive: readBool(json['is_active'], fallback: true),
      currentStatus: LocationCurrentStatus.fromJson(
        asMap(json['current_status']),
      ),
    );
  }

  String get subtitle => locationSubtitle(
    compoundName,
    beachName,
    fallback: 'Selected beach cart',
  );
}

class CheckoutFulfillment {
  final String type;
  final double deliveryFee;
  final String currency;

  const CheckoutFulfillment({
    required this.type,
    required this.deliveryFee,
    required this.currency,
  });

  factory CheckoutFulfillment.fromJson(Map<String, dynamic> json) {
    return CheckoutFulfillment(
      type: readString(json['type'], fallback: FulfillmentTypes.pickupAtCart),
      deliveryFee: readDouble(json['delivery_fee']) ?? 0,
      currency: readString(json['currency'], fallback: 'EGP'),
    );
  }

  bool get isDelivery => type == FulfillmentTypes.deliveryToUnit;
}

class CheckoutCustomer {
  final String id;
  final String? name;
  final String? phone;

  const CheckoutCustomer({
    required this.id,
    required this.name,
    required this.phone,
  });

  factory CheckoutCustomer.fromJson(Map<String, dynamic> json) {
    return CheckoutCustomer(
      id: readString(json['id']),
      name: nullableString(
        json['name'] ?? json['full_name'] ?? json['customer_name'],
      ),
      phone: nullableString(json['phone'] ?? json['customer_phone']),
    );
  }
}

class CheckoutItem {
  final String cartItemId;
  final String productId;
  final String variantId;
  final String recipeId;
  final String productName;
  final String variantName;
  final int quantity;
  final int servingCount;
  final double baseUnitPriceIncVat;
  final double customizationTotalIncVat;
  final String? customizationSummary;
  final CartItemCustomization? customization;
  final double unitPriceIncVat;
  final double lineTotal;
  final bool isAvailable;
  final String? blockingReason;
  final String? imageUrl;
  final String currency;
  final String imageAsset;

  const CheckoutItem({
    required this.cartItemId,
    required this.productId,
    required this.variantId,
    required this.recipeId,
    required this.productName,
    required this.variantName,
    required this.quantity,
    required this.servingCount,
    required this.baseUnitPriceIncVat,
    required this.customizationTotalIncVat,
    required this.customizationSummary,
    required this.customization,
    required this.unitPriceIncVat,
    required this.lineTotal,
    required this.isAvailable,
    required this.blockingReason,
    required this.imageUrl,
    required this.currency,
    required this.imageAsset,
  });

  factory CheckoutItem.fromJson(Map<String, dynamic> json) {
    final productMap = asMap(json['product']);

    final name = readString(
      json['product_name'] ?? productMap['name'] ?? json['name'],
      fallback: 'Cocktail',
    );

    final imageUrl = nullableString(
      json['image_url'] ??
          json['product_image_url'] ??
          json['thumbnail_url'] ??
          productMap['image_url'] ??
          productMap['product_image_url'] ??
          productMap['thumbnail_url'],
    );

    return CheckoutItem(
      cartItemId: readString(json['cart_item_id'] ?? json['id']),
      productId: readString(json['product_id'] ?? productMap['id']),
      variantId: readString(json['variant_id']),
      recipeId: readString(json['recipe_id']),
      productName: name,
      variantName: readString(json['variant_name'], fallback: 'Serving'),
      quantity: readInt(json['quantity'], fallback: 1),
      servingCount: readInt(json['serving_count'], fallback: 1),
      baseUnitPriceIncVat: readDouble(json['base_unit_price_inc_vat']) ?? 0,
      customizationTotalIncVat:
          readDouble(json['customization_total_inc_vat']) ?? 0,
      customizationSummary: nullableString(
        json['customization_summary'] ??
            asMap(json['customization'])['summary'],
      ),
      customization: json['customization'] is Map
          ? CartItemCustomization.fromJson(asMap(json['customization']))
          : null,
      unitPriceIncVat: readDouble(json['unit_price_inc_vat']) ?? 0,
      lineTotal: readDouble(json['line_total']) ?? 0,
      isAvailable: readBool(json['is_available'], fallback: true),
      blockingReason: nullableString(json['blocking_reason']),
      imageUrl: imageUrl,
      currency: readString(json['currency'], fallback: 'EGP'),
      imageAsset: CocktailAssets.forName(name),
    );
  }

  String get lineTotalLabel => formatMoney(lineTotal, currency);

  String? get cleanCustomizationSummary {
    final summary = customizationSummary?.trim();
    if (summary == null || summary.isEmpty) return null;
    return summary;
  }
}

class CheckoutItemWarning {
  final String cartItemId;
  final String productId;
  final String productName;
  final String reason;

  const CheckoutItemWarning({
    required this.cartItemId,
    required this.productId,
    required this.productName,
    required this.reason,
  });

  factory CheckoutItemWarning.fromJson(Map<String, dynamic> json) {
    return CheckoutItemWarning(
      cartItemId: readString(json['cart_item_id']),
      productId: readString(json['product_id']),
      productName: readString(json['product_name'], fallback: 'Item'),
      reason: readString(json['reason'], fallback: 'Unavailable.'),
    );
  }
}

class CheckoutSummary {
  final double subtotalExVat;
  final double vatAmount;
  final double subtotalIncVat;
  final double discountAmount;
  final double referralDiscountAmount;
  final double creditApplied;
  final double deliveryFee;
  final double totalAmount;
  final String currency;
  final bool vatIncluded;

  const CheckoutSummary({
    required this.subtotalExVat,
    required this.vatAmount,
    required this.subtotalIncVat,
    required this.discountAmount,
    required this.referralDiscountAmount,
    required this.creditApplied,
    required this.deliveryFee,
    required this.totalAmount,
    required this.currency,
    required this.vatIncluded,
  });

  factory CheckoutSummary.fromJson(Map<String, dynamic> json) {
    return CheckoutSummary(
      subtotalExVat: readDouble(json['subtotal_ex_vat']) ?? 0,
      vatAmount: readDouble(json['vat_amount']) ?? 0,
      subtotalIncVat: readDouble(json['subtotal_inc_vat']) ?? 0,
      discountAmount: readDouble(json['discount_amount']) ?? 0,
      referralDiscountAmount: readDouble(json['referral_discount_amount']) ?? 0,
      creditApplied: readDouble(json['credit_applied']) ?? 0,
      deliveryFee: readDouble(json['delivery_fee']) ?? 0,
      totalAmount: readDouble(json['total_amount']) ?? 0,
      currency: readString(json['currency'], fallback: 'EGP'),
      vatIncluded: readBool(json['vat_included'], fallback: true),
    );
  }

  bool get hasReferralDiscount => referralDiscountAmount > 0;
  bool get hasCreditApplied => creditApplied > 0;

  String get subtotalLabel => formatMoney(subtotalIncVat, currency);
  String get discountLabel => '- ${formatMoney(discountAmount, currency)}';
  String get referralDiscountLabel =>
      '- ${formatMoney(referralDiscountAmount, currency)}';
  String get creditAppliedLabel => '- ${formatMoney(creditApplied, currency)}';
  String get deliveryFeeLabel => formatMoney(deliveryFee, currency);
  String get totalLabel => formatMoney(totalAmount, currency);
}

class CheckoutPromotion {
  final String id;
  final String code;
  final String name;
  final String discountType;
  final double discountValue;
  final double discountAmount;
  final String currency;

  const CheckoutPromotion({
    required this.id,
    required this.code,
    required this.name,
    required this.discountType,
    required this.discountValue,
    required this.discountAmount,
    required this.currency,
  });

  factory CheckoutPromotion.fromJson(Map<String, dynamic> json) {
    return CheckoutPromotion(
      id: readString(json['id']),
      code: readString(json['code']),
      name: readString(json['name'], fallback: 'Promotion'),
      discountType: readString(json['discount_type']),
      discountValue: readDouble(json['discount_value']) ?? 0,
      discountAmount: readDouble(json['discount_amount']) ?? 0,
      currency: readString(json['currency'], fallback: 'EGP'),
    );
  }
}

class CheckoutPaymentMethod {
  final String key;
  final String label;
  final String provider;
  final bool enabled;
  final bool setupRequired;
  final PaymentMethodSdk sdk;

  const CheckoutPaymentMethod({
    required this.key,
    required this.label,
    required this.provider,
    required this.enabled,
    required this.setupRequired,
    required this.sdk,
  });

  factory CheckoutPaymentMethod.fromJson(Map<String, dynamic> json) {
    return CheckoutPaymentMethod(
      key: readString(json['key']),
      label: readString(json['label'], fallback: 'Payment Method'),
      provider: readString(json['provider'], fallback: 'geidea'),
      enabled: readBool(json['enabled']),
      setupRequired: readBool(json['setup_required']),
      sdk: PaymentMethodSdk.fromJson(asMap(json['sdk'])),
    );
  }

  bool get isCard => key == 'geidea_card';
  bool get isApplePay => key == 'geidea_apple_pay';
  bool get isDemoCheckout => key == 'demo_checkout';
  bool get isStripePaymentSheet => key == 'stripe_payment_sheet';

  bool get isAllowedCheckoutMethod {
    return isCard || isApplePay || isDemoCheckout || isStripePaymentSheet;
  }
}

class PaymentMethodSdk {
  final String provider;
  final bool configured;
  final bool isSandbox;
  final String region;
  final String language;
  final String? applePayMerchantId;
  final bool callbackUrlConfigured;
  final bool createSessionUrlConfigured;

  const PaymentMethodSdk({
    required this.provider,
    required this.configured,
    required this.isSandbox,
    required this.region,
    required this.language,
    required this.applePayMerchantId,
    required this.callbackUrlConfigured,
    required this.createSessionUrlConfigured,
  });

  factory PaymentMethodSdk.fromJson(Map<String, dynamic> json) {
    return PaymentMethodSdk(
      provider: readString(json['provider'], fallback: 'geidea'),
      configured: readBool(json['configured']),
      isSandbox: readBool(json['is_sandbox'], fallback: true),
      region: readString(json['region'], fallback: 'egy'),
      language: readString(json['language'], fallback: 'en'),
      applePayMerchantId: nullableString(json['apple_pay_merchant_id']),
      callbackUrlConfigured: readBool(json['callback_url_configured']),
      createSessionUrlConfigured: readBool(
        json['create_session_url_configured'],
      ),
    );
  }
}

class CheckoutValidation {
  final bool canPlaceOrder;
  final List<String> blockingReasons;

  const CheckoutValidation({
    required this.canPlaceOrder,
    required this.blockingReasons,
  });

  factory CheckoutValidation.fromJson(Map<String, dynamic> json) {
    return CheckoutValidation(
      canPlaceOrder: readBool(json['can_place_order'] ?? json['can_checkout']),
      blockingReasons: readStringList(json['blocking_reasons']),
    );
  }

  String? get firstBlockingReason {
    if (blockingReasons.isEmpty) return null;
    return blockingReasons.first;
  }
}

class CheckoutQuoteResponse {
  final CheckoutQuote quote;

  const CheckoutQuoteResponse({required this.quote});

  factory CheckoutQuoteResponse.fromJson(Map<String, dynamic> json) {
    return CheckoutQuoteResponse(
      quote: CheckoutQuote.fromJson(asMap(json['quote'])),
    );
  }
}

class CheckoutQuote {
  final String cartId;
  final String locationId;
  final String fulfillmentType;
  final String? addressText;
  final String? promoCode;
  final CheckoutPromotion? promotion;
  final CheckoutSummary summary;
  final CheckoutValidation validation;

  const CheckoutQuote({
    required this.cartId,
    required this.locationId,
    required this.fulfillmentType,
    required this.addressText,
    required this.promoCode,
    required this.promotion,
    required this.summary,
    required this.validation,
  });

  factory CheckoutQuote.fromJson(Map<String, dynamic> json) {
    final promotionMap = asMap(json['promotion']);

    return CheckoutQuote(
      cartId: readString(json['cart_id']),
      locationId: readString(json['location_id']),
      fulfillmentType: readString(
        json['fulfillment_type'],
        fallback: FulfillmentTypes.pickupAtCart,
      ),
      addressText: nullableString(json['address_text']),
      promoCode: nullableString(json['promo_code']),
      promotion: promotionMap.isEmpty
          ? null
          : CheckoutPromotion.fromJson(promotionMap),
      summary: CheckoutSummary.fromJson(asMap(json['totals'])),
      validation: CheckoutValidation.fromJson(asMap(json['validation'])),
    );
  }
}

class PlaceOrderResponse {
  final CheckoutOrder order;
  final CheckoutPayment payment;
  final String nextScreen;

  /// The lines the order was written with, as the backend stored them.
  ///
  /// Only place-order carries these — the payment-status poll a gateway order
  /// finishes through does not — so confirmation has to hold on to the copy
  /// from here rather than re-reading it later.
  final List<PlacedOrderItem> items;

  const PlaceOrderResponse({
    required this.order,
    required this.payment,
    required this.nextScreen,
    required this.items,
  });

  factory PlaceOrderResponse.fromJson(Map<String, dynamic> json) {
    return PlaceOrderResponse(
      order: CheckoutOrder.fromJson(asMap(json['order'])),
      payment: CheckoutPayment.fromJson(asMap(json['payment'])),
      nextScreen: readString(json['nextScreen'] ?? json['next_screen']),
      items: readMapList(json['items']).map(PlacedOrderItem.fromJson).toList(),
    );
  }
}

/// One line of a placed order.
///
/// These come straight off the inserted `order_items` rows, so the field names
/// are the stored snapshots rather than the `checkout` payload's shorter ones —
/// the price the customer paid, not today's price.
class PlacedOrderItem {
  final String id;
  final String productName;
  final String? variantName;
  final int quantity;
  final double unitPriceIncVat;
  final double lineTotal;
  final String? customizationSummary;

  const PlacedOrderItem({
    required this.id,
    required this.productName,
    required this.variantName,
    required this.quantity,
    required this.unitPriceIncVat,
    required this.lineTotal,
    required this.customizationSummary,
  });

  factory PlacedOrderItem.fromJson(Map<String, dynamic> json) {
    return PlacedOrderItem(
      id: readString(json['id']),
      productName: readString(
        json['product_name_snapshot'] ?? json['product_name'],
        fallback: 'Item',
      ),
      variantName: nullableString(
        json['variant_name_snapshot'] ?? json['variant_name'],
      ),
      quantity: readInt(json['quantity']),
      unitPriceIncVat:
          readDouble(
            json['unit_price_inc_vat_snapshot'] ?? json['unit_price_inc_vat'],
          ) ??
          0,
      lineTotal: readDouble(json['line_total']) ?? 0,
      customizationSummary: nullableString(json['customization_summary']),
    );
  }

  bool get hasVariant => (variantName ?? '').trim().isNotEmpty;
  bool get hasCustomization =>
      (customizationSummary ?? '').trim().isNotEmpty;

  String lineTotalLabel(String currency) => formatMoney(lineTotal, currency);
}

class CheckoutOrder {
  final String id;
  final String orderNumber;
  final String status;
  final String paymentStatus;
  final String fulfillmentType;
  final String? createdAt;

  /// When the cart expects to have this order ready, in UTC. Null on orders the
  /// customer did not schedule — those are made as soon as the cart can.
  final String? requestedFulfillmentAt;
  final String? customerPhone;
  final String? address;

  /// The beach cart the order was placed against, as the backend resolved it.
  /// Confirmation prefers this over the location the checkout screen was drawn
  /// with, since this one is what the order actually recorded.
  final CheckoutLocation? location;
  final CheckoutSummary totals;
  final bool hasTotals;
  final CheckoutPromotion? promotion;

  const CheckoutOrder({
    required this.id,
    required this.orderNumber,
    required this.status,
    required this.paymentStatus,
    required this.fulfillmentType,
    required this.createdAt,
    required this.requestedFulfillmentAt,
    required this.customerPhone,
    required this.address,
    required this.location,
    required this.totals,
    required this.hasTotals,
    required this.promotion,
  });

  factory CheckoutOrder.fromJson(Map<String, dynamic> json) {
    final promotionMap = asMap(json['promotion']);
    final totalsMap = asMap(json['totals']);
    final locationMap = asMap(json['location']);

    return CheckoutOrder(
      id: readString(json['id']),
      orderNumber: readString(json['order_number'], fallback: 'EBTL Order'),
      status: readString(json['status']),
      paymentStatus: readString(json['payment_status']),
      fulfillmentType: readString(json['fulfillment_type']),
      createdAt: nullableString(json['created_at']),
      requestedFulfillmentAt: nullableString(json['requested_fulfillment_at']),
      customerPhone: nullableString(json['customer_phone']),
      address: nullableString(json['address']),
      location: locationMap.isEmpty
          ? null
          : CheckoutLocation.fromJson(locationMap),
      totals: CheckoutSummary.fromJson(totalsMap),
      hasTotals: totalsMap.isNotEmpty,
      promotion: promotionMap.isEmpty
          ? null
          : CheckoutPromotion.fromJson(promotionMap),
    );
  }

  bool get isDelivery => fulfillmentType == FulfillmentTypes.deliveryToUnit;

  /// Matches [PaymentStatusResponse.isPaid]: demo orders come back already
  /// settled from place-order, gateway orders only reach this through polling.
  bool get isPaid => paymentStatus == 'paid' && status == 'confirmed';
}

class CheckoutPayment {
  final bool requiredPayment;
  final String provider;
  final String paymentId;
  final String paymentMethod;
  final String status;
  final double amount;
  final String currency;
  final GeideaPaymentSession geidea;
  final StripePaymentSession stripe;
  final String orderReference;

  const CheckoutPayment({
    required this.requiredPayment,
    required this.provider,
    required this.paymentId,
    required this.paymentMethod,
    required this.status,
    required this.amount,
    required this.currency,
    required this.geidea,
    required this.stripe,
    required this.orderReference,
  });

  factory CheckoutPayment.fromJson(Map<String, dynamic> json) {
    return CheckoutPayment(
      requiredPayment: readBool(json['required'], fallback: true),
      provider: readString(json['provider'], fallback: 'geidea'),
      paymentId: readString(json['payment_id']),
      paymentMethod: readString(json['payment_method']),
      status: readString(json['status'], fallback: 'pending'),
      amount: readDouble(json['amount']) ?? 0,
      currency: readString(json['currency'], fallback: 'EGP'),
      geidea: GeideaPaymentSession.fromJson(asMap(json['geidea'])),
      stripe: StripePaymentSession.fromJson(asMap(json['stripe'])),
      orderReference: readString(json['order_reference']),
    );
  }

  bool get isStripe => provider == 'stripe';
}

class GeideaPaymentSession {
  final bool configured;
  final bool isSandbox;
  final String region;
  final String language;
  final String sessionId;
  final String? applePayMerchantId;

  const GeideaPaymentSession({
    required this.configured,
    required this.isSandbox,
    required this.region,
    required this.language,
    required this.sessionId,
    required this.applePayMerchantId,
  });

  factory GeideaPaymentSession.fromJson(Map<String, dynamic> json) {
    return GeideaPaymentSession(
      configured: readBool(json['configured'], fallback: true),
      isSandbox: readBool(json['is_sandbox'], fallback: true),
      region: readString(json['region'], fallback: 'egy'),
      language: readString(json['language'], fallback: 'en'),
      sessionId: readString(json['session_id']),
      applePayMerchantId: nullableString(json['apple_pay_merchant_id']),
    );
  }
}

class StripePaymentSession {
  final bool configured;
  final bool isTest;
  final String? publishableKey;
  final String merchantDisplayName;
  final String merchantCountry;
  final String? applePayMerchantId;
  final bool googlePayEnabled;
  final String paymentIntentId;
  final String clientSecret;
  final String customerId;
  final String ephemeralKeySecret;

  const StripePaymentSession({
    required this.configured,
    required this.isTest,
    required this.publishableKey,
    required this.merchantDisplayName,
    required this.merchantCountry,
    required this.applePayMerchantId,
    required this.googlePayEnabled,
    required this.paymentIntentId,
    required this.clientSecret,
    required this.customerId,
    required this.ephemeralKeySecret,
  });

  factory StripePaymentSession.fromJson(Map<String, dynamic> json) {
    return StripePaymentSession(
      configured: readBool(json['configured']),
      isTest: readBool(json['is_test'], fallback: true),
      publishableKey: nullableString(json['publishable_key']),
      merchantDisplayName: readString(
        json['merchant_display_name'],
        fallback: 'EBTL',
      ),
      merchantCountry: readString(json['merchant_country'], fallback: 'US'),
      applePayMerchantId: nullableString(json['apple_pay_merchant_id']),
      googlePayEnabled: readBool(json['google_pay_enabled']),
      paymentIntentId: readString(json['payment_intent_id']),
      clientSecret: readString(json['client_secret']),
      customerId: readString(json['customer_id']),
      ephemeralKeySecret: readString(json['ephemeral_key_secret']),
    );
  }

  bool get hasClientSecret => clientSecret.isNotEmpty;
  bool get hasCustomer => customerId.isNotEmpty && ephemeralKeySecret.isNotEmpty;
}

class PaymentStatusResponse {
  final String orderId;
  final String orderNumber;
  final String orderStatus;
  final String paymentStatus;
  final String? updatedAt;
  final CheckoutPayment payment;

  const PaymentStatusResponse({
    required this.orderId,
    required this.orderNumber,
    required this.orderStatus,
    required this.paymentStatus,
    required this.updatedAt,
    required this.payment,
  });

  factory PaymentStatusResponse.fromJson(Map<String, dynamic> json) {
    return PaymentStatusResponse(
      orderId: readString(json['order_id']),
      orderNumber: readString(json['order_number'], fallback: 'EBTL Order'),
      orderStatus: readString(json['order_status']),
      paymentStatus: readString(json['payment_status']),
      updatedAt: nullableString(json['updated_at']),
      payment: CheckoutPayment.fromJson(asMap(json['payment'])),
    );
  }

  bool get isPaid {
    return paymentStatus == 'paid' && orderStatus == 'confirmed';
  }

  bool get isFailed {
    return paymentStatus == 'failed';
  }

  bool get isFinal {
    return isPaid || isFailed || paymentStatus == 'refunded';
  }
}
