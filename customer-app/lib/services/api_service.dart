import 'dart:async';
import 'dart:convert';

import 'package:flutter/foundation.dart';
import 'package:flutter_secure_storage/flutter_secure_storage.dart';
import 'package:http/http.dart' as http;

import '../core/constants/fulfillment_types.dart';
import '../core/network/api_config.dart';
import '../core/network/api_exception.dart';
import '../core/utils/json_helpers.dart';
import '../models/address_models.dart';
import '../models/app_data.dart';
import '../models/cart_action_models.dart';
import '../models/cart_models.dart';
import '../models/checkout_models.dart';
import '../models/cocktail_detail_models.dart';
import '../models/cocktail_models.dart';
import '../models/common_models.dart';
import '../models/favorite_models.dart';
import '../models/notification_models.dart';
import '../models/order_detail_models.dart';
import '../models/profile_models.dart';
import '../models/referral_models.dart';
import '../models/shop_models.dart';
import '../models/spirit_models.dart';
import '../models/spotlight_models.dart';
import 'cart_revision.dart';

class ApiService {
  static const _storage = FlutterSecureStorage();

  static const _tokenKey = 'customer_session_token';
  static const _customerIdKey = 'customer_id';
  static const _selectedLocationIdKey = 'selected_location_id';
  static const _selectedLocationNameKey = 'selected_location_name';
  static const _onboardingCompletedKey = 'onboarding_completed_v1';
  static const _recentlyViewedKey = 'recently_viewed_slugs_v1';
  static const _goldenHourSeenKey = 'golden_hour_seen_v1';

  /// How many product slugs the "Recently viewed" rail remembers.
  static const int recentlyViewedLimit = 10;

  /// How many Golden Hour windows are remembered as shown.
  ///
  /// There are four modes, so eight covers today and yesterday and the oldest
  /// key falls off on its own. That is the whole of the daily reset: a new day
  /// writes dates nothing in the list carries, so every window is unseen again
  /// without a stored "last reset" to compare against — which the app could not
  /// compare honestly anyway, since the business day is Cairo's and the device
  /// clock may be set anywhere.
  static const int _goldenHourSeenLimit = 8;

  static const Duration _defaultRequestTimeout = Duration(seconds: 45);
  static const Duration _sessionRequestTimeout = Duration(seconds: 90);

  /// The client every request goes through.
  ///
  /// Exists so tests can answer requests without a network: the guarantees this
  /// class carries — a cart write invalidating loaded carts, a 401 replaying
  /// exactly once — are properties of [_request], and there is no way to assert
  /// them against the top-level `http.get`/`http.post` functions.
  static http.Client _client = http.Client();

  @visibleForTesting
  static set client(http.Client client) => _client = client;

  @visibleForTesting
  static void resetClient() => _client = http.Client();

  static Duration _timeoutFor(String method, String path) {
    if (method.toUpperCase() == 'POST' && path == '/api/customer/session') {
      return _sessionRequestTimeout;
    }

    return _defaultRequestTimeout;
  }

  /// Loads everything the app shell needs.
  ///
  /// Pass [previous] on a refresh that only needs live data (cart totals,
  /// availability). The cocktail-finder options are effectively static for the
  /// lifetime of a session, so they are carried over instead of refetched,
  /// which halves the request count on every cart change.
  static Future<AppData> fetchAppData({AppData? previous}) async {
    await ensureSession();

    final selectedLocationId = await getSelectedLocationId();
    final selectedLocationName = await getSelectedLocationName();

    final homeJson = await _request(
      method: 'GET',
      path: '/api/customer/home',
      query: {'location_id': selectedLocationId},
      attachToken: true,
    );

    if (previous != null) {
      return AppData.fromApi(
        homeJson: homeJson,
        reusedOptions: previous.finderOptions,
        selectedLocationId: selectedLocationId,
        selectedLocationName: selectedLocationName,
      );
    }

    final optionsJson = await _request(
      method: 'GET',
      path: '/api/customer/cocktail-finder/options',
      attachToken: false,
    );

    return AppData.fromApi(
      homeJson: homeJson,
      optionsJson: optionsJson,
      selectedLocationId: selectedLocationId,
      selectedLocationName: selectedLocationName,
    );
  }

  /// Guards the one-time session bootstrap so concurrent callers share a single
  /// POST instead of racing each other.
  static Future<void>? _sessionBootstrap;

  /// Ensures a customer session token exists before a request goes out.
  ///
  /// This runs ahead of every API call, so it must stay cheap: once a token is
  /// stored there is nothing to do. Tokens are refreshed passively — [_request]
  /// picks up both the `x-ebtl-customer-token` header and any `session` object
  /// in a response body — and a token the backend has since rejected is
  /// recovered from by the 401 handler in [_request].
  static Future<void> ensureSession() async {
    final existingToken = await getCustomerToken();
    if (existingToken != null && existingToken.trim().isNotEmpty) return;

    final inFlight = _sessionBootstrap;
    if (inFlight != null) return inFlight;

    final bootstrap = _createSession();
    _sessionBootstrap = bootstrap;

    try {
      await bootstrap;
    } finally {
      _sessionBootstrap = null;
    }
  }

  static Future<CustomerSession> _createSession() async {
    final existingToken = await getCustomerToken();

    final sessionJson = await _request(
      method: 'POST',
      path: '/api/customer/session',
      body: const {},
      attachToken: existingToken != null && existingToken.trim().isNotEmpty,
    );

    final session = CustomerSession.fromJson(asMap(sessionJson['session']));
    await _persistSession(session);
    return session;
  }

  static Future<CocktailSearchResult> fetchCocktails({
    String? locationId,
    Set<String> liquorTypeIds = const {},
    Set<String> tagNames = const {},
    String? categoryId,
    String? searchText,
    String sort = 'featured',
    int page = 1,
    int pageSize = 50,
  }) async {
    await ensureSession();

    final json = await _request(
      method: 'GET',
      path: '/api/customer/cocktails',
      query: {
        'location_id': locationId,
        'liquor_type_ids': liquorTypeIds.isEmpty
            ? null
            : liquorTypeIds.join(','),
        'tags': tagNames.isEmpty ? null : tagNames.join(','),
        'category_id': categoryId,
        'q': searchText,
        'sort': sort,
        'page': page.toString(),
        'page_size': pageSize.toString(),
      },
      attachToken: true,
    );

    return CocktailSearchResult.fromJson(json);
  }

  static Future<CocktailDetailResponse> fetchCocktailDetail({
    required String slug,
    String? locationId,
    String? liquorTypeId,
  }) async {
    await ensureSession();

    final json = await _request(
      method: 'GET',
      path: '/api/customer/cocktails/${Uri.encodeComponent(slug)}',
      query: {'location_id': locationId, 'liquor_type_id': liquorTypeId},
      attachToken: true,
    );

    return CocktailDetailResponse.fromJson(json);
  }

  static Future<ShopResponse> fetchShop({String? locationId}) async {
    await ensureSession();

    final json = await _request(
      method: 'GET',
      path: '/api/customer/shop',
      query: {'location_id': locationId},
      attachToken: true,
    );

    return ShopResponse.fromJson(json);
  }

  /// The products behind a Spotlight banner, resolved from the loose products
  /// and whole categories marketing selected for it in the dashboard.
  static Future<SpotlightProductsResponse> fetchSpotlightProducts({
    required String bannerId,
    String? locationId,
  }) async {
    await ensureSession();

    final json = await _request(
      method: 'GET',
      path:
          '/api/customer/spotlight/${Uri.encodeComponent(bannerId)}/products',
      query: {'location_id': locationId},
      attachToken: true,
    );

    return SpotlightProductsResponse.fromJson(json);
  }

  static Future<ShopCategoryProductsResponse> fetchShopCategoryProducts({
    required String identifier,
    String? locationId,
    int page = 1,
    int pageSize = 24,
    String sort = 'display_order',
  }) async {
    await ensureSession();

    final json = await _request(
      method: 'GET',
      path:
          '/api/customer/shop/categories/${Uri.encodeComponent(identifier)}/products',
      query: {
        'location_id': locationId,
        'page': page.toString(),
        'page_size': pageSize.toString(),
        'sort': sort,
      },
      attachToken: true,
    );

    return ShopCategoryProductsResponse.fromJson(json);
  }

  static Future<AddToCartResult> addShopProductToCart({
    required String productId,
    required String variantId,
    required int quantity,
    required String locationId,
  }) async {
    await ensureSession();

    final json = await _request(
      method: 'POST',
      path: '/api/customer/cart/items',
      body: {
        'product_id': productId,
        'variant_id': variantId,
        'quantity': quantity.clamp(1, 99),
        'location_id': locationId,
      },
      attachToken: true,
    );

    return AddToCartResult.fromJson(json);
  }

  static Future<AddToCartResult> addCocktailToCart({
    required String cocktailId,
    required String variantId,
    required int selectedQuantity,
    required String locationId,
    String? selectedLiquorTypeId,
    Set<String> removedRecipeItemIds = const {},
    List<SelectedAddition> selectedAdditions = const [],
  }) async {
    await ensureSession();

    final cleanSelectedLiquorTypeId = selectedLiquorTypeId?.trim();

    final json = await _request(
      method: 'POST',
      path: '/api/customer/cart/items',
      body: {
        'cocktail_id': cocktailId,
        'variant_id': variantId,
        'selected_quantity': selectedQuantity.clamp(1, 99),
        'location_id': locationId,
        if (cleanSelectedLiquorTypeId != null &&
            cleanSelectedLiquorTypeId.isNotEmpty)
          'selected_liquor_type_id': cleanSelectedLiquorTypeId,
        'customization': {
          'removed_recipe_item_ids': removedRecipeItemIds.toList(),
          'additions': selectedAdditions
              .map((addition) => addition.toCartJson())
              .toList(),
        },
      },
      attachToken: true,
    );

    return AddToCartResult.fromJson(json);
  }

  static Future<CartPageResponse> fetchCart({
    String? locationId,
    String fulfillmentType = FulfillmentTypes.pickupAtCart,
  }) async {
    await ensureSession();

    final json = await _request(
      method: 'GET',
      path: '/api/customer/cart',
      query: {'location_id': locationId, 'fulfillment_type': fulfillmentType},
      attachToken: true,
    );

    return CartPageResponse.fromJson(json);
  }

  /// The cart summary a cart write answers with, or null if the response
  /// carried none. Callers hand it to the shell so the bottom-nav badge updates
  /// from this response instead of a follow-up `/home` fetch.
  static CartSummary? _cartSummaryFrom(Map<String, dynamic> json) {
    final summaryMap = asMap(json['cartSummary'] ?? json['cart_summary']);
    return summaryMap.isEmpty ? null : CartSummary.fromJson(summaryMap);
  }

  static Future<CartSummary?> updateCartItemQuantity({
    required String itemId,
    required int quantity,
  }) async {
    await ensureSession();

    final json = await _request(
      method: 'PATCH',
      path: '/api/customer/cart/items/${Uri.encodeComponent(itemId)}',
      body: {'quantity': quantity.clamp(0, 99)},
      attachToken: true,
    );

    return _cartSummaryFrom(json);
  }

  static Future<CartSummary?> deleteCartItem({required String itemId}) async {
    await ensureSession();

    final json = await _request(
      method: 'DELETE',
      path: '/api/customer/cart/items/${Uri.encodeComponent(itemId)}',
      attachToken: true,
    );

    return _cartSummaryFrom(json);
  }

  static Future<CartSummary?> clearCart() async {
    await ensureSession();

    final json = await _request(
      method: 'DELETE',
      path: '/api/customer/cart',
      attachToken: true,
    );

    // This endpoint answers with `{cart_id, cleared: true}` rather than a
    // summary: an emptied cart has only one shape.
    final cartId = readString(json['cart_id']);
    return cartId.isEmpty ? null : CartSummary.emptied(cartId);
  }

  static Future<CheckoutPageResponse> fetchCheckout({
    required String locationId,
    required String fulfillmentType,
    String? promoCode,
  }) async {
    await ensureSession();

    final json = await _request(
      method: 'GET',
      path: '/api/customer/checkout',
      query: {
        'location_id': locationId,
        'fulfillment_type': fulfillmentType,
        'promo_code': promoCode,
      },
      attachToken: true,
    );

    return CheckoutPageResponse.fromJson(json);
  }

  static Future<CheckoutQuoteResponse> quoteCheckout({
    required String cartId,
    required String locationId,
    required String fulfillmentType,
    required String address,
    required String promoCode,
    String? customerNotes,
  }) async {
    await ensureSession();

    final json = await _request(
      method: 'POST',
      path: '/api/customer/checkout/quote',
      body: {
        'cart_id': cartId,
        'location_id': locationId,
        'fulfillment_type': fulfillmentType,
        'address': address.trim(),
        'promo_code': promoCode.trim().isEmpty ? null : promoCode.trim(),
        'customer_notes': customerNotes?.trim().isEmpty == true
            ? null
            : customerNotes?.trim(),
      },
      attachToken: true,
    );

    return CheckoutQuoteResponse.fromJson(json);
  }

  static Future<PlaceOrderResponse> placeCheckoutOrder({
    required String cartId,
    required String locationId,
    required String fulfillmentType,
    required String address,
    required String customerName,
    required String customerPhone,
    required String paymentMethod,
    required String idempotencyKey,
    String? promoCode,
    String? customerNotes,
  }) async {
    await ensureSession();

    final cleanName = customerName.trim();

    final json = await _request(
      method: 'POST',
      path: '/api/customer/checkout/place-order',
      body: {
        'cart_id': cartId,
        'location_id': locationId,
        'fulfillment_type': fulfillmentType,
        'address': address.trim(),
        'customer_phone': customerPhone.trim(),
        if (cleanName.isNotEmpty) 'customer_name': cleanName,
        'requested_fulfillment_at': null,
        'promo_code': promoCode?.trim().isEmpty == true
            ? null
            : promoCode?.trim(),
        'customer_notes': customerNotes?.trim().isEmpty == true
            ? null
            : customerNotes?.trim(),
        'payment_method': paymentMethod,
        'idempotency_key': idempotencyKey,
      },
      attachToken: true,
    );

    final response = PlaceOrderResponse.fromJson(json);
    _noteOrderPaid(response.order.id, isPaid: response.order.isPaid);
    return response;
  }

  /// The backend empties the cart once an order is paid — immediately for demo
  /// orders, from the payment webhook for gateway ones. That is a cart change
  /// the app never made itself, so a paid order invalidates loaded carts too.
  /// Deduplicated per order because the payment status is polled.
  static final Set<String> _paidOrders = <String>{};

  static void _noteOrderPaid(String orderId, {required bool isPaid}) {
    if (!isPaid || orderId.isEmpty) return;
    if (!_paidOrders.add(orderId)) return;

    CartRevision.bump();
  }

  static Future<PaymentStatusResponse> fetchOrderPaymentStatus({
    required String orderId,
  }) async {
    await ensureSession();

    final json = await _request(
      method: 'GET',
      path:
          '/api/customer/orders/${Uri.encodeComponent(orderId)}/payment-status',
      attachToken: true,
    );

    final response = PaymentStatusResponse.fromJson(json);
    _noteOrderPaid(response.orderId, isPaid: response.isPaid);
    return response;
  }

  static Future<CustomerNotificationsResponse> fetchCustomerNotifications({
    int limit = 50,
    bool unreadOnly = false,
  }) async {
    await ensureSession();

    final json = await _request(
      method: 'GET',
      path: '/api/customer/notifications',
      query: {
        'limit': limit.toString(),
        'unread_only': unreadOnly ? 'true' : null,
      },
      attachToken: true,
    );

    return CustomerNotificationsResponse.fromJson(json);
  }

  static Future<CustomerNotification> markCustomerNotificationRead({
    required String notificationId,
  }) async {
    await ensureSession();

    final json = await _request(
      method: 'PATCH',
      path:
          '/api/customer/notifications/${Uri.encodeComponent(notificationId)}/read',
      attachToken: true,
    );

    return CustomerNotification.fromJson(asMap(json['notification']));
  }

  static Future<int> markAllCustomerNotificationsRead() async {
    await ensureSession();

    final json = await _request(
      method: 'POST',
      path: '/api/customer/notifications/read-all',
      attachToken: true,
    );

    return readInt(json['unread_count']);
  }

  static Future<void> registerCustomerPushToken({
    required String token,
    required String platform,
    String? deviceId,
  }) async {
    await ensureSession();

    await _request(
      method: 'POST',
      path: '/api/customer/push-tokens',
      body: {
        'token': token,
        'platform': platform,
        if (deviceId?.trim().isNotEmpty == true) 'device_id': deviceId!.trim(),
      },
      attachToken: true,
    );
  }

  static Future<CustomerProfileResponse> fetchCustomerProfile() async {
    await ensureSession();

    final json = await _request(
      method: 'GET',
      path: '/api/customer/profile',
      attachToken: true,
    );

    return CustomerProfileResponse.fromJson(json);
  }

  static Future<ReferralHub> fetchReferralHub() async {
    await ensureSession();

    final json = await _request(
      method: 'GET',
      path: '/api/customer/referrals',
      attachToken: true,
    );

    return ReferralHub.fromJson(asMap(json['referral']));
  }

  static Future<ReferralHub> applyReferralCode(String code) async {
    await ensureSession();

    final json = await _request(
      method: 'POST',
      path: '/api/customer/referrals/apply',
      body: {'code': code.trim()},
      attachToken: true,
    );

    return ReferralHub.fromJson(asMap(json['referral']));
  }

  static Future<CustomerProfileUpdateResponse> updateCustomerProfile({
    String? fullName,
    String? phone,
    String? email,
    String? birthday,
    String? gender,
    bool includeGender = false,
    bool? marketingOptIn,
  }) async {
    await ensureSession();

    final body = <String, dynamic>{};

    if (fullName != null) body['full_name'] = fullName.trim();
    if (phone != null) body['phone'] = phone.trim();
    if (email != null) body['email'] = email.trim();
    if (birthday != null) body['birthday'] = birthday.trim();

    if (includeGender) {
      final cleanGender = gender?.trim();

      if (cleanGender == null || cleanGender.isEmpty) {
        body['gender'] = null;
      } else {
        final normalizedGender = CustomerProfile.normalizeGender(cleanGender);

        if (normalizedGender == null) {
          throw ArgumentError('Invalid customer gender: $gender');
        }

        body['gender'] = normalizedGender;
      }
    }

    if (marketingOptIn != null) body['marketing_opt_in'] = marketingOptIn;

    final json = await _request(
      method: 'PATCH',
      path: '/api/customer/profile',
      body: body,
      attachToken: true,
    );

    return CustomerProfileUpdateResponse.fromJson(json);
  }

  static Future<CustomerOrdersResponse> fetchCustomerOrders({
    int limit = 20,
    int offset = 0,
  }) async {
    await ensureSession();

    final json = await _request(
      method: 'GET',
      path: '/api/customer/orders',
      query: {'limit': limit.toString(), 'offset': offset.toString()},
      attachToken: true,
    );

    return CustomerOrdersResponse.fromJson(json);
  }

  static Future<OrderDetailResponse> fetchCustomerOrderDetail({
    required String orderId,
  }) async {
    await ensureSession();

    final json = await _request(
      method: 'GET',
      path: '/api/customer/orders/${Uri.encodeComponent(orderId)}',
      attachToken: true,
    );

    return OrderDetailResponse.fromJson(json);
  }

  static Future<FavoriteCocktailsResponse> fetchFavoriteCocktails({
    String? locationId,
    int page = 1,
    int pageSize = 50,
  }) async {
    await ensureSession();

    final json = await _request(
      method: 'GET',
      path: '/api/customer/favorites',
      query: {
        'location_id': locationId,
        'page': page.toString(),
        'page_size': pageSize.toString(),
      },
      attachToken: true,
    );

    return FavoriteCocktailsResponse.fromJson(json);
  }

  static Future<void> addFavoriteCocktail({required String productId}) async {
    await ensureSession();

    await _request(
      method: 'POST',
      path: '/api/customer/favorites/${Uri.encodeComponent(productId)}',
      attachToken: true,
    );
  }

  static Future<void> removeFavoriteCocktail({
    required String productId,
  }) async {
    await ensureSession();

    await _request(
      method: 'DELETE',
      path: '/api/customer/favorites/${Uri.encodeComponent(productId)}',
      attachToken: true,
    );
  }

  static Future<ProfileSpirits> fetchCustomerSpirits() async {
    await ensureSession();

    final json = await _request(
      method: 'GET',
      path: '/api/customer/spirits',
      attachToken: true,
    );

    return ProfileSpirits.fromJson(json);
  }

  /// Adds a spirit to the customer's favorites. Like the remove below, the
  /// backend answers with the whole spirits payload, so callers render the
  /// result rather than patching local state.
  static Future<ProfileSpirits> addFavoriteSpirit({
    required String liquorTypeId,
  }) async {
    await ensureSession();

    final json = await _request(
      method: 'POST',
      path: '/api/customer/spirits/favorites/${Uri.encodeComponent(liquorTypeId)}',
      attachToken: true,
    );

    return ProfileSpirits.fromJson(json);
  }

  static Future<ProfileSpirits> removeFavoriteSpirit({
    required String liquorTypeId,
  }) async {
    await ensureSession();

    final json = await _request(
      method: 'DELETE',
      path: '/api/customer/spirits/favorites/${Uri.encodeComponent(liquorTypeId)}',
      attachToken: true,
    );

    return ProfileSpirits.fromJson(json);
  }

  static Future<CustomerAddressesResponse> fetchCustomerAddresses() async {
    await ensureSession();

    final json = await _request(
      method: 'GET',
      path: '/api/customer/addresses',
      attachToken: true,
    );

    return CustomerAddressesResponse.fromJson(json);
  }

  /// Creates a new address, or updates the one identified by [id]. Empty text
  /// fields are sent as null so the backend clears the corresponding column.
  static Future<CustomerAddress> saveCustomerAddress({
    String? id,
    String? label,
    String? compoundName,
    String? beachName,
    String? unitNumber,
    String? building,
    String? floor,
    String? deliveryNotes,
    bool isDefault = false,
  }) async {
    await ensureSession();

    String? nullIfBlank(String? value) {
      final text = value?.trim();
      return text == null || text.isEmpty ? null : text;
    }

    final body = <String, dynamic>{
      'label': nullIfBlank(label),
      'compound_name': nullIfBlank(compoundName),
      'beach_name': nullIfBlank(beachName),
      'unit_number': nullIfBlank(unitNumber),
      'building': nullIfBlank(building),
      'floor': nullIfBlank(floor),
      'delivery_notes': nullIfBlank(deliveryNotes),
      'is_default': isDefault,
    };

    final addressId = id?.trim();
    final isUpdate = addressId != null && addressId.isNotEmpty;

    final json = await _request(
      method: isUpdate ? 'PATCH' : 'POST',
      path: isUpdate
          ? '/api/customer/addresses/${Uri.encodeComponent(addressId)}'
          : '/api/customer/addresses',
      body: body,
      attachToken: true,
    );

    return CustomerAddress.fromJson(asMap(json['address']));
  }

  static Future<void> deleteCustomerAddress({required String id}) async {
    await ensureSession();

    await _request(
      method: 'DELETE',
      path: '/api/customer/addresses/${Uri.encodeComponent(id)}',
      attachToken: true,
    );
  }

  static Future<void> clearCustomerSession() async {
    await _storage.delete(key: _tokenKey);
    await _storage.delete(key: _customerIdKey);
  }

  static Future<String?> getCustomerToken() async {
    return _storage.read(key: _tokenKey);
  }

  static Future<bool> hasCompletedOnboarding() async {
    final value = await _storage.read(key: _onboardingCompletedKey);
    return value == 'true';
  }

  static Future<void> markOnboardingCompleted() async {
    await _storage.write(key: _onboardingCompletedKey, value: 'true');
  }

  static Future<String?> getSelectedLocationId() async {
    return _storage.read(key: _selectedLocationIdKey);
  }

  static Future<String?> getSelectedLocationName() async {
    return _storage.read(key: _selectedLocationNameKey);
  }

  static Future<void> saveSelectedLocation(ServiceLocation location) async {
    await _storage.write(key: _selectedLocationIdKey, value: location.id);
    await _storage.write(key: _selectedLocationNameKey, value: location.name);
  }

  /// Product slugs the customer opened, most recent first.
  ///
  /// Only slugs are stored — the Explore screen resolves them against the
  /// catalog it has already loaded, so prices and availability stay live and
  /// products that disappear from the catalog simply drop out of the rail.
  static Future<List<String>> loadRecentlyViewedSlugs() async {
    final raw = await _storage.read(key: _recentlyViewedKey);
    if (raw == null || raw.trim().isEmpty) return const [];

    try {
      final decoded = jsonDecode(raw);
      if (decoded is! List) return const [];

      return decoded
          .map((value) => value is String ? value.trim() : '')
          .where((slug) => slug.isNotEmpty)
          .take(recentlyViewedLimit)
          .toList();
    } on FormatException {
      // A malformed cache is not worth surfacing — drop it and start over.
      await _storage.delete(key: _recentlyViewedKey);
      return const [];
    }
  }

  /// Records a viewed product, moving it to the front and capping the list.
  static Future<void> recordRecentlyViewed(String slug) async {
    final cleanSlug = slug.trim();
    if (cleanSlug.isEmpty) return;

    final existing = await loadRecentlyViewedSlugs();
    final updated = <String>[
      cleanSlug,
      ...existing.where((value) => value != cleanSlug),
    ].take(recentlyViewedLimit).toList();

    await _storage.write(key: _recentlyViewedKey, value: jsonEncode(updated));
  }

  static Future<void> clearRecentlyViewed() async {
    await _storage.delete(key: _recentlyViewedKey);
  }

  /// The Golden Hour windows whose card has already been shown, most recent
  /// first, as backend occurrence keys (`'sunset:2026-08-10'`).
  static Future<List<String>> _loadSeenGoldenHourKeys() async {
    final raw = await _storage.read(key: _goldenHourSeenKey);
    if (raw == null || raw.trim().isEmpty) return const [];

    try {
      final decoded = jsonDecode(raw);
      if (decoded is! List) return const [];

      return decoded
          .map((value) => value is String ? value.trim() : '')
          .where((key) => key.isNotEmpty)
          .take(_goldenHourSeenLimit)
          .toList();
    } on FormatException {
      // A malformed record is not worth surfacing. Dropping it costs one extra
      // showing of the current card, which is the harmless direction to fail.
      await _storage.delete(key: _goldenHourSeenKey);
      return const [];
    }
  }

  /// Has the Golden Hour card for this window already been shown?
  ///
  /// An empty key answers false: a payload from a backend that predates the key
  /// carries no window identity, and refusing to show the card at all would be a
  /// worse answer than showing it once a launch as before.
  static Future<bool> hasSeenGoldenHour(String occurrenceKey) async {
    final key = occurrenceKey.trim();
    if (key.isEmpty) return false;

    return (await _loadSeenGoldenHourKeys()).contains(key);
  }

  /// Records that this window's card has been shown.
  ///
  /// Called when the card opens, not when it is acted on: dismissing it is an
  /// answer, and asking again an hour later would be asking twice.
  static Future<void> recordGoldenHourSeen(String occurrenceKey) async {
    final key = occurrenceKey.trim();
    if (key.isEmpty) return;

    final existing = await _loadSeenGoldenHourKeys();
    final updated = <String>[
      key,
      ...existing.where((value) => value != key),
    ].take(_goldenHourSeenLimit).toList();

    await _storage.write(key: _goldenHourSeenKey, value: jsonEncode(updated));
  }

  static Future<void> _persistSession(CustomerSession session) async {
    if (session.customerSessionToken.trim().isNotEmpty) {
      await _storage.write(key: _tokenKey, value: session.customerSessionToken);
    }
    if (session.customerId.trim().isNotEmpty) {
      await _storage.write(key: _customerIdKey, value: session.customerId);
    }
  }

  static Future<Map<String, dynamic>> _request({
    required String method,
    required String path,
    Map<String, String?>? query,
    Map<String, dynamic>? body,
    bool attachToken = true,
    bool allowSessionRetry = true,
  }) async {
    final uri = ApiConfig.endpoint(path, query);
    final headers = <String, String>{
      'Accept': 'application/json',
      'Content-Type': 'application/json',
    };

    if (attachToken) {
      final token = await getCustomerToken();
      if (token != null && token.trim().isNotEmpty) {
        headers['Authorization'] = 'Bearer $token';
      }
    }

    late http.Response response;
    final requestTimeout = _timeoutFor(method, path);

    try {
      switch (method.toUpperCase()) {
        case 'GET':
          response = await _client
              .get(uri, headers: headers)
              .timeout(requestTimeout);
          break;
        case 'POST':
          response = await _client
              .post(uri, headers: headers, body: jsonEncode(body ?? const {}))
              .timeout(requestTimeout);
          break;
        case 'PATCH':
          response = await _client
              .patch(uri, headers: headers, body: jsonEncode(body ?? const {}))
              .timeout(requestTimeout);
          break;
        case 'DELETE':
          response = await _client
              .delete(uri, headers: headers)
              .timeout(requestTimeout);
          break;
        default:
          throw ApiException(
            message: 'Unsupported HTTP method: $method',
            endpoint: '$method $path',
          );
      }
    } catch (error) {
      if (error is ApiException) rethrow;

      if (error is TimeoutException) {
        throw ApiException(
          message: 'Network request timed out.',
          endpoint: '$method $path',
          responseBody:
              'Timed out after ${requestTimeout.inSeconds} seconds. If this is the first request after the backend has been idle, wait for Render to wake up and try again. If it keeps happening, the backend route is hanging and should be checked in Render logs.',
        );
      }

      throw ApiException(
        message: 'Network request failed.',
        endpoint: '$method $path',
        responseBody: error.toString(),
      );
    }

    final headerToken =
        response.headers['x-ebtl-customer-token'] ??
        response.headers['X-EBTL-Customer-Token'];

    if (headerToken != null && headerToken.trim().isNotEmpty) {
      await _storage.write(key: _tokenKey, value: headerToken.trim());
    }

    // A stored token the backend no longer accepts is recoverable: drop it,
    // mint a fresh session, and replay the request once. Without this, skipping
    // the per-call session POST would turn an expired token into a dead end.
    if (response.statusCode == 401 &&
        attachToken &&
        allowSessionRetry &&
        path != '/api/customer/session') {
      await clearCustomerSession();
      await _createSession();

      return _request(
        method: method,
        path: path,
        query: query,
        body: body,
        attachToken: attachToken,
        allowSessionRetry: false,
      );
    }

    final decoded = decodeJsonObject(response.body, endpoint: '$method $path');

    if (response.statusCode < 200 || response.statusCode >= 300) {
      throw ApiException(
        message: readString(
          decoded['error'],
          fallback: 'Backend request failed.',
        ),
        endpoint: '$method $path',
        statusCode: response.statusCode,
        errorCode: nullableString(decoded['error_code']),
        blockingReasons: readApiErrorDetails(
          decoded['blocking_reasons'],
          decoded['details'],
        ),
        responseBody: response.body,
      );
    }

    final rawSession = decoded['session'];
    if (rawSession is Map<String, dynamic>) {
      await _persistSession(CustomerSession.fromJson(rawSession));
    }

    _noteCartWrite(method: method, path: path);

    return decoded;
  }

  /// Invalidates loaded carts once a request that changed the cart is known to
  /// have succeeded.
  ///
  /// This sits in [_request], past the error check, rather than in the
  /// individual cart methods: every cart write goes through here, so the
  /// invalidation cannot be left off a new one, and a request that threw never
  /// reaches it. That is the guarantee the cart tab leans on — an item that
  /// made it into the cart is an item the cart tab knows to reload.
  static void _noteCartWrite({required String method, required String path}) {
    if (!isCartWriteRequest(method: method, path: path)) return;

    CartRevision.bump();
  }
}
