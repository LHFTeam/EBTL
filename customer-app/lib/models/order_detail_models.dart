import '../core/constants/cocktail_assets.dart';
import '../core/utils/formatters.dart';
import '../core/utils/json_helpers.dart';

class OrderDetailResponse {
  final OrderDetail order;
  final List<OrderDetailItem> items;

  const OrderDetailResponse({required this.order, required this.items});

  factory OrderDetailResponse.fromJson(Map<String, dynamic> json) {
    return OrderDetailResponse(
      order: OrderDetail.fromJson(asMap(json['order'])),
      items: readMapList(json['items']).map(OrderDetailItem.fromJson).toList(),
    );
  }
}

class OrderDetail {
  final String id;
  final String? orderNumber;
  final String status;
  final String paymentStatus;
  final String fulfillmentType;
  final String? createdAt;
  final String? requestedFulfillmentAt;
  final String? customerPhone;
  final String? addressText;
  final String? customerNotes;
  final OrderDetailLocation? location;
  final OrderDetailTotals totals;

  const OrderDetail({
    required this.id,
    required this.orderNumber,
    required this.status,
    required this.paymentStatus,
    required this.fulfillmentType,
    required this.createdAt,
    required this.requestedFulfillmentAt,
    required this.customerPhone,
    required this.addressText,
    required this.customerNotes,
    required this.location,
    required this.totals,
  });

  factory OrderDetail.fromJson(Map<String, dynamic> json) {
    final locationMap = asMap(json['location']);

    return OrderDetail(
      id: readString(json['id']),
      orderNumber: nullableString(json['order_number']),
      status: readString(json['status']),
      paymentStatus: readString(json['payment_status']),
      fulfillmentType: readString(
        json['fulfillment_type'],
        fallback: 'pickup_at_cart',
      ),
      createdAt: nullableString(json['created_at']),
      requestedFulfillmentAt: nullableString(json['requested_fulfillment_at']),
      customerPhone: nullableString(json['customer_phone']),
      addressText: nullableString(json['address_text']),
      customerNotes: nullableString(json['customer_notes']),
      location: locationMap.isEmpty
          ? null
          : OrderDetailLocation.fromJson(locationMap),
      totals: OrderDetailTotals.fromJson(asMap(json['totals'])),
    );
  }

  String get displayOrderNumber {
    final number = orderNumber?.trim();
    if (number == null || number.isEmpty) return 'Order';
    return number;
  }

  String get displayTime => formatProfileDateTime(
    requestedFulfillmentAt ?? createdAt,
  );

  bool get isDelivery => fulfillmentType == 'delivery_to_unit';

  /// The order was placed but never paid for, and the backend has not expired
  /// or cancelled it yet — so the customer can still pay it, or drop it.
  ///
  /// Both halves are checked: a payment status the app does not recognise is
  /// never assumed to be unpaid.
  bool get awaitsPayment {
    const unpaidStatuses = {'unpaid', 'pending', 'failed'};

    return status.trim().toLowerCase() == 'pending_payment' &&
        unpaidStatuses.contains(paymentStatus.trim().toLowerCase());
  }

  /// Whether this order has a pickup code worth asking the backend about.
  ///
  /// Deliveries never do, and neither does an order that is finished or has
  /// not been paid for. Everything from `confirmed` onwards does, because the
  /// card also says where the code will appear once the order is bagged.
  bool get showsPickupCode {
    const activeStatuses = {'confirmed', 'preparing', 'ready'};

    return !isDelivery &&
        paymentStatus.trim().toLowerCase() == 'paid' &&
        activeStatuses.contains(status.trim().toLowerCase());
  }
}

/// The code the customer shows at the cart to collect a pickup order.
///
/// The backend answers with `available: false` and a reason rather than an
/// error for an order that simply has no code yet, so an order still being made
/// and an order already collected both arrive here as ordinary responses.
///
/// The QR arrives drawn, as an SVG string: the encoding lives on the server so
/// there is only one place it can go wrong, and the app needs no QR package to
/// show it.
class PickupCode {
  final bool available;
  final String? reason;
  final String? message;
  final String status;
  final String? qrSvg;
  final String? shortCode;
  final String? customerFirstName;
  final String? instructions;
  final int refreshAfterMs;

  const PickupCode({
    required this.available,
    required this.reason,
    required this.message,
    required this.status,
    required this.qrSvg,
    required this.shortCode,
    required this.customerFirstName,
    required this.instructions,
    required this.refreshAfterMs,
  });

  factory PickupCode.fromJson(Map<String, dynamic> json) {
    final pickup = asMap(json['pickup']);

    return PickupCode(
      available: readBool(pickup['available']),
      reason: nullableString(pickup['reason']),
      message: nullableString(pickup['message']),
      status: readString(pickup['status']),
      qrSvg: nullableString(pickup['qr_svg']),
      shortCode: nullableString(pickup['short_code']),
      customerFirstName: nullableString(pickup['customer_first_name']),
      instructions: nullableString(pickup['instructions']),
      // Falls back to half a minute, which is one rotation of the code.
      refreshAfterMs: readInt(pickup['refresh_after_ms'], fallback: 30000),
    );
  }

  /// True once the code can be shown — both halves are needed, since the QR is
  /// what gets scanned and the digits are the fallback under it.
  bool get isShowable =>
      available &&
      (qrSvg?.isNotEmpty ?? false) &&
      (shortCode?.isNotEmpty ?? false);

  /// The order is on its way but not bagged yet, which is worth saying so the
  /// customer knows where the code will appear.
  bool get isPending => !available && reason == 'not_ready';
}

class OrderDetailLocation {
  final String id;
  final String name;
  final String? compoundName;
  final String? beachName;
  final String? bannerImageUrl;

  const OrderDetailLocation({
    required this.id,
    required this.name,
    required this.compoundName,
    required this.beachName,
    required this.bannerImageUrl,
  });

  factory OrderDetailLocation.fromJson(Map<String, dynamic> json) {
    return OrderDetailLocation(
      id: readString(json['id']),
      name: readString(json['name'], fallback: 'Beach Cart'),
      compoundName: nullableString(json['compound_name']),
      beachName: nullableString(json['beach_name']),
      bannerImageUrl: nullableString(json['banner_image_url']),
    );
  }

  String get subtitle => locationSubtitle(
    compoundName,
    beachName,
    fallback: 'Selected beach cart',
  );
}

class OrderDetailTotals {
  final double subtotalExVat;
  final double vatAmount;
  final double discountAmount;
  final double deliveryFee;
  final double totalAmount;
  final String currency;

  const OrderDetailTotals({
    required this.subtotalExVat,
    required this.vatAmount,
    required this.discountAmount,
    required this.deliveryFee,
    required this.totalAmount,
    required this.currency,
  });

  factory OrderDetailTotals.fromJson(Map<String, dynamic> json) {
    return OrderDetailTotals(
      subtotalExVat: readDouble(json['subtotal_ex_vat']) ?? 0,
      vatAmount: readDouble(json['vat_amount']) ?? 0,
      discountAmount: readDouble(json['discount_amount']) ?? 0,
      deliveryFee: readDouble(json['delivery_fee']) ?? 0,
      totalAmount: readDouble(json['total_amount']) ?? 0,
      currency: readString(json['currency'], fallback: 'EGP'),
    );
  }

  double get subtotalIncVat => subtotalExVat + vatAmount;

  String get subtotalLabel => formatMoney(subtotalIncVat, currency);
  String get discountLabel => '-${formatMoney(discountAmount, currency)}';
  String get deliveryFeeLabel => formatMoney(deliveryFee, currency);
  String get totalLabel => formatMoney(totalAmount, currency);
}

class OrderDetailItem {
  final String id;
  final String? productName;
  final String? variantName;
  final int quantity;
  final double unitPriceIncVat;
  final double lineTotal;
  final String? customizationSummary;

  /// The product's artwork, from the line's joined product. Null on an order
  /// whose product has no image, in which case [imageAsset] is drawn instead.
  final String? imageUrl;
  final String imageAsset;

  const OrderDetailItem({
    required this.id,
    required this.productName,
    required this.variantName,
    required this.quantity,
    required this.unitPriceIncVat,
    required this.lineTotal,
    required this.customizationSummary,
    required this.imageUrl,
    required this.imageAsset,
  });

  factory OrderDetailItem.fromJson(Map<String, dynamic> json) {
    final name = readString(json['product_name_snapshot'], fallback: 'Item');

    return OrderDetailItem(
      id: readString(json['id']),
      productName: name,
      variantName: nullableString(json['variant_name_snapshot']),
      quantity: readInt(json['quantity'], fallback: 1),
      unitPriceIncVat: readDouble(json['unit_price_inc_vat_snapshot']) ?? 0,
      lineTotal:
          readDouble(json['line_total']) ??
          readDouble(json['unit_price_inc_vat_snapshot']) ??
          0,
      customizationSummary: nullableString(json['customization_summary']),
      imageUrl: nullableString(json['image_url']),
      imageAsset: CocktailAssets.forName(name),
    );
  }

  String get displayName => productName?.trim().isNotEmpty == true
      ? productName!.trim()
      : 'Item';

  String lineTotalLabel(String currency) => formatMoney(lineTotal, currency);

  String unitPriceLabel(String currency) =>
      formatMoney(unitPriceIncVat, currency);
}
