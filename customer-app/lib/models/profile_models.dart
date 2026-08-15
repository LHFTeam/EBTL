import '../core/constants/fulfillment_types.dart';
import '../core/utils/formatters.dart';
import '../core/utils/json_helpers.dart';
import 'spirit_models.dart';

class CustomerProfileResponse {
  final CustomerProfile customer;
  final ProfileRecentOrders recentOrders;
  final ProfileSpirits spirits;
  final List<ProfileQuickLink> quickLinks;
  final ProfileBrandMessage brandMessage;

  const CustomerProfileResponse({
    required this.customer,
    required this.recentOrders,
    required this.spirits,
    required this.quickLinks,
    required this.brandMessage,
  });

  factory CustomerProfileResponse.fromJson(Map<String, dynamic> json) {
    return CustomerProfileResponse(
      customer: CustomerProfile.fromJson(asMap(json['customer'])),
      recentOrders: ProfileRecentOrders.fromJson(asMap(json['recent_orders'])),
      spirits: ProfileSpirits.fromJson(asMap(json['spirits'])),
      quickLinks: readMapList(
        json['quick_links'],
      ).map(ProfileQuickLink.fromJson).toList(),
      brandMessage: ProfileBrandMessage.fromJson(asMap(json['brand_message'])),
    );
  }
}

class CustomerProfileUpdateResponse {
  final CustomerProfile customer;

  const CustomerProfileUpdateResponse({required this.customer});

  factory CustomerProfileUpdateResponse.fromJson(Map<String, dynamic> json) {
    return CustomerProfileUpdateResponse(
      customer: CustomerProfile.fromJson(asMap(json['customer'])),
    );
  }
}

class CustomerProfile {
  final String id;
  final String? fullName;
  final String? phone;
  final String? email;
  final String? birthday;
  final String? gender;
  final bool marketingOptIn;
  final CustomerAvatar avatar;
  final CustomerProfileCompletion completion;

  const CustomerProfile({
    required this.id,
    required this.fullName,
    required this.phone,
    required this.email,
    required this.birthday,
    required this.gender,
    required this.marketingOptIn,
    required this.avatar,
    required this.completion,
  });

  factory CustomerProfile.fromJson(Map<String, dynamic> json) {
    return CustomerProfile(
      id: readString(json['id']),
      fullName: nullableString(json['full_name'] ?? json['name']),
      phone: nullableString(json['phone']),
      email: nullableString(json['email']),
      birthday: nullableString(json['birthday']),
      gender: normalizeGender(json['gender']),
      marketingOptIn: readBool(json['marketing_opt_in']),
      avatar: CustomerAvatar.fromJson(asMap(json['avatar'])),
      completion: CustomerProfileCompletion.fromJson(asMap(json['completion'])),
    );
  }

  static String? normalizeGender(dynamic value) {
    if (value == null) return null;

    final normalized = value.toString().trim().toLowerCase();

    if (normalized == 'male') return 'male';
    if (normalized == 'female') return 'female';

    return null;
  }

  String get displayName =>
      fullName?.trim().isNotEmpty == true ? fullName!.trim() : 'Add your name';

  String get displayEmail =>
      email?.trim().isNotEmpty == true ? email!.trim() : 'Add your email';

  String get displayPhone =>
      phone?.trim().isNotEmpty == true ? phone!.trim() : 'Add your phone';
}

class CustomerAvatar {
  static const String defaultAssetPath = 'assets/profile/default-profile.webp';

  final String type;
  final String? assetPath;
  final String? imageUrl;

  const CustomerAvatar({
    required this.type,
    required this.assetPath,
    required this.imageUrl,
  });

  factory CustomerAvatar.fromJson(Map<String, dynamic> json) {
    return CustomerAvatar(
      type: readString(json['type'], fallback: 'local_asset'),
      assetPath: nullableString(json['asset_path']),
      imageUrl: nullableString(json['image_url']),
    );
  }

  String get effectiveAssetPath {
    final path = assetPath?.trim();
    if (path != null && path.isNotEmpty) return path;
    return defaultAssetPath;
  }
}

class CustomerProfileCompletion {
  final bool hasFullName;
  final bool hasPhone;
  final bool hasEmail;
  final bool hasGender;
  final List<String> missingFields;

  const CustomerProfileCompletion({
    required this.hasFullName,
    required this.hasPhone,
    required this.hasEmail,
    required this.hasGender,
    required this.missingFields,
  });

  factory CustomerProfileCompletion.fromJson(Map<String, dynamic> json) {
    return CustomerProfileCompletion(
      hasFullName: readBool(json['has_full_name']),
      hasPhone: readBool(json['has_phone']),
      hasEmail: readBool(json['has_email']),
      hasGender: readBool(json['has_gender']),
      missingFields: readStringList(json['missing_fields']),
    );
  }
}

class ProfileRecentOrders {
  final String title;
  final int limit;
  final bool hasMore;
  final String? viewAllEndpoint;
  final List<ProfileOrder> items;

  const ProfileRecentOrders({
    required this.title,
    required this.limit,
    required this.hasMore,
    required this.viewAllEndpoint,
    required this.items,
  });

  factory ProfileRecentOrders.fromJson(Map<String, dynamic> json) {
    return ProfileRecentOrders(
      title: readString(json['title'], fallback: 'My Orders'),
      limit: readInt(json['limit'], fallback: 5),
      hasMore: readBool(json['has_more']),
      viewAllEndpoint: nullableString(json['view_all_endpoint']),
      items: readMapList(json['items']).map(ProfileOrder.fromJson).toList(),
    );
  }
}

class CustomerOrdersResponse {
  final List<ProfileOrder> orders;
  final CustomerOrdersMeta meta;

  const CustomerOrdersResponse({required this.orders, required this.meta});

  factory CustomerOrdersResponse.fromJson(Map<String, dynamic> json) {
    return CustomerOrdersResponse(
      orders: readMapList(json['orders']).map(ProfileOrder.fromJson).toList(),
      meta: CustomerOrdersMeta.fromJson(asMap(json['meta'])),
    );
  }
}

class CustomerOrdersMeta {
  final int limit;
  final int offset;
  final bool hasMore;

  const CustomerOrdersMeta({
    required this.limit,
    required this.offset,
    required this.hasMore,
  });

  factory CustomerOrdersMeta.fromJson(Map<String, dynamic> json) {
    return CustomerOrdersMeta(
      limit: readInt(json['limit'], fallback: 20),
      offset: readInt(json['offset']),
      hasMore: readBool(json['has_more']),
    );
  }
}

class ProfileOrder {
  final String id;
  final String? orderNumber;
  final String status;
  final String statusLabel;
  final String paymentStatus;
  final String paymentStatusLabel;
  final String fulfillmentType;
  final String? requestedFulfillmentAt;
  final String? displayFulfillmentAt;
  final String? createdAt;
  final String? updatedAt;
  final double totalAmount;
  final String currency;
  final String? orderImageUrl;
  final ProfileOrderPrimaryItem? primaryItem;
  final int itemCount;
  final int totalQuantity;
  final CustomerLocation? location;
  final String? locationName;

  const ProfileOrder({
    required this.id,
    required this.orderNumber,
    required this.status,
    required this.statusLabel,
    required this.paymentStatus,
    required this.paymentStatusLabel,
    required this.fulfillmentType,
    required this.requestedFulfillmentAt,
    required this.displayFulfillmentAt,
    required this.createdAt,
    required this.updatedAt,
    required this.totalAmount,
    required this.currency,
    required this.orderImageUrl,
    required this.primaryItem,
    required this.itemCount,
    required this.totalQuantity,
    required this.location,
    required this.locationName,
  });

  factory ProfileOrder.fromJson(Map<String, dynamic> json) {
    final locationMap = asMap(json['location']);
    final primaryItemMap = asMap(json['primary_item']);

    return ProfileOrder(
      id: readString(json['id']),
      orderNumber: nullableString(json['order_number']),
      status: readString(json['status']),
      statusLabel: readString(json['status_label'], fallback: 'Order'),
      paymentStatus: readString(json['payment_status']),
      paymentStatusLabel: readString(json['payment_status_label']),
      fulfillmentType: readString(
        json['fulfillment_type'],
        fallback: FulfillmentTypes.pickupAtCart,
      ),
      requestedFulfillmentAt: nullableString(json['requested_fulfillment_at']),
      displayFulfillmentAt: nullableString(json['display_fulfillment_at']),
      createdAt: nullableString(json['created_at']),
      updatedAt: nullableString(json['updated_at']),
      totalAmount: readDouble(json['total_amount']) ?? 0,
      currency: readString(json['currency'], fallback: 'EGP'),
      orderImageUrl: nullableString(json['order_image_url']),
      primaryItem: primaryItemMap.isEmpty
          ? null
          : ProfileOrderPrimaryItem.fromJson(primaryItemMap),
      itemCount: readInt(json['item_count']),
      totalQuantity: readInt(json['total_quantity']),
      location: locationMap.isEmpty
          ? null
          : CustomerLocation.fromJson(locationMap),
      locationName: nullableString(json['location_name']),
    );
  }

  /// An order is "active" once the customer has paid for it but before it has
  /// been completed (or cancelled/refunded). These are the orders still being
  /// prepared/fulfilled that the customer is likely tracking.
  bool get isActive {
    final normalizedPayment = paymentStatus.trim().toLowerCase();
    if (normalizedPayment != 'paid') return false;

    final normalizedStatus = status.trim().toLowerCase();
    // `expired` is terminal too. It normally carries an unpaid payment status
    // and is filtered out above, but an expired order that received a late
    // payment is marked paid while staying expired — it is flagged for a human,
    // not being prepared, so it must never show as an order to track.
    const finishedStatuses = {
      'completed',
      'cancelled',
      'canceled',
      'refunded',
      'expired',
    };
    return !finishedStatuses.contains(normalizedStatus);
  }

  /// Bagged and waiting at the cart, with a pickup code to show for it. This is
  /// the one moment the customer needs to be somewhere, so it is called out
  /// above the list rather than left to be found inside an order.
  bool get isWaitingForCollection =>
      isActive &&
      fulfillmentType.trim().toLowerCase() == 'pickup_at_cart' &&
      status.trim().toLowerCase() == 'ready';

  String get displayOrderNumber {
    final number = orderNumber?.trim();
    if (number == null || number.isEmpty) return 'Order';
    return number;
  }

  String get displayLocation {
    final name = locationName?.trim();
    if (name != null && name.isNotEmpty) return name;
    final locationValue = location?.name.trim();
    if (locationValue != null && locationValue.isNotEmpty) return locationValue;
    return 'Beach Cart';
  }

  String get displayTotal => formatMoney(totalAmount, currency);

  String get displayTime {
    return formatProfileDateTime(
      displayFulfillmentAt ?? requestedFulfillmentAt ?? createdAt,
    );
  }

  /// The four stages the Home live-order tracker draws:
  /// Paid → Mixing → Ready → Collected. Returns how many of them this order
  /// has reached, 1–4.
  int get liveProgressStep {
    switch (status.trim().toLowerCase()) {
      case 'preparing':
        return 2;
      case 'ready':
      case 'out_for_delivery':
        return 3;
      case 'completed':
        return 4;
      default:
        // Anything paid but not yet started reads as "Paid".
        return 1;
    }
  }

  /// The uppercase status accent on the live-order card.
  String get liveStatusLabel {
    switch (status.trim().toLowerCase()) {
      case 'confirmed':
        return 'ORDER CONFIRMED';
      case 'preparing':
        return 'BEING MIXED NOW';
      case 'ready':
        return 'READY FOR COLLECTION';
      case 'out_for_delivery':
        return 'ON ITS WAY';
      default:
        return statusLabel.toUpperCase();
    }
  }

  /// "Ready ~8 min" when the order carries a fulfillment time still ahead of
  /// us, falling back to the plain status label when it does not.
  String get liveEtaLabel {
    final parsed = DateTime.tryParse(
      displayFulfillmentAt ?? requestedFulfillmentAt ?? '',
    );

    if (parsed != null) {
      final minutes = parsed.toLocal().difference(DateTime.now()).inMinutes;

      if (minutes > 0 && minutes < 60) return 'Ready ~$minutes min';
      if (minutes >= 60 && minutes < 24 * 60) {
        return 'Ready ~${(minutes / 60).round()} h';
      }
    }

    return statusLabel;
  }

  /// The order as one line: its main item plus how many other items rode
  /// along, e.g. "Piña Colada Kit + 2".
  String get displayItemsSummary {
    final name = primaryItem?.name?.trim();
    final label = name == null || name.isEmpty ? 'Your order' : name;
    final extras = totalQuantity - (primaryItem?.quantity ?? 0);

    return extras > 0 ? '$label + $extras' : label;
  }

  /// "Ordered 3 days ago", or just "Previous order" when the date is missing.
  String get orderedAgoLabel {
    final relative = formatRelativeDay(createdAt);
    return relative == null ? 'Previous order' : 'Ordered $relative';
  }
}

class ProfileOrderPrimaryItem {
  final String? productId;
  final String? slug;
  final String? name;
  final String? variantName;
  final int quantity;

  const ProfileOrderPrimaryItem({
    required this.productId,
    required this.slug,
    required this.name,
    required this.variantName,
    required this.quantity,
  });

  factory ProfileOrderPrimaryItem.fromJson(Map<String, dynamic> json) {
    return ProfileOrderPrimaryItem(
      productId: nullableString(json['product_id']),
      slug: nullableString(json['slug']),
      name: nullableString(json['name']),
      variantName: nullableString(json['variant_name']),
      quantity: readInt(json['quantity'], fallback: 1),
    );
  }
}

class CustomerLocation {
  final String id;
  final String name;
  final String type;
  final String? compoundName;
  final String? beachName;
  final String? bannerImageUrl;
  final double deliveryFee;
  final bool isActive;

  const CustomerLocation({
    required this.id,
    required this.name,
    required this.type,
    required this.compoundName,
    required this.beachName,
    required this.bannerImageUrl,
    required this.deliveryFee,
    required this.isActive,
  });

  factory CustomerLocation.fromJson(Map<String, dynamic> json) {
    return CustomerLocation(
      id: readString(json['id']),
      name: readString(json['name'], fallback: 'Beach Cart'),
      type: readString(json['type']),
      compoundName: nullableString(json['compound_name']),
      beachName: nullableString(json['beach_name']),
      bannerImageUrl: nullableString(json['banner_image_url']),
      deliveryFee: readDouble(json['delivery_fee']) ?? 0,
      isActive: readBool(json['is_active'], fallback: true),
    );
  }
}

class ProfileQuickLink {
  final String key;
  final String title;
  final String? subtitle;
  final String? endpoint;
  final bool enabled;
  final bool placeholder;
  final int? count;

  const ProfileQuickLink({
    required this.key,
    required this.title,
    required this.subtitle,
    required this.endpoint,
    required this.enabled,
    required this.placeholder,
    required this.count,
  });

  factory ProfileQuickLink.fromJson(Map<String, dynamic> json) {
    return ProfileQuickLink(
      key: readString(json['key']),
      title: readString(json['title'], fallback: 'Link'),
      subtitle: nullableString(json['subtitle']),
      endpoint: nullableString(json['endpoint']),
      enabled: readBool(json['enabled'], fallback: true),
      placeholder: readBool(json['placeholder']),
      count: json['count'] == null ? null : readInt(json['count']),
    );
  }
}

class ProfileBrandMessage {
  final String title;
  final String accent;

  const ProfileBrandMessage({required this.title, required this.accent});

  factory ProfileBrandMessage.fromJson(Map<String, dynamic> json) {
    return ProfileBrandMessage(
      title: readString(json['title'], fallback: 'You bring the bottle.'),
      accent: readString(json['accent'], fallback: 'We bring the magic.'),
    );
  }
}
