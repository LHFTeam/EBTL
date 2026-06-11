import 'dart:async';
import 'dart:convert';

import 'package:flutter_secure_storage/flutter_secure_storage.dart';
import 'package:http/http.dart' as http;

import '../core/constants/fulfillment_types.dart';
import '../core/network/api_config.dart';
import '../core/network/api_exception.dart';
import '../core/utils/json_helpers.dart';
import '../models/app_data.dart';
import '../models/cart_action_models.dart';
import '../models/cart_models.dart';
import '../models/checkout_models.dart';
import '../models/cocktail_detail_models.dart';
import '../models/cocktail_models.dart';
import '../models/common_models.dart';
import '../models/favorite_models.dart';
import '../models/profile_models.dart';
import '../models/shop_models.dart';

class ApiService {
  static const _storage = FlutterSecureStorage();

  static const _tokenKey = 'customer_session_token';
  static const _customerIdKey = 'customer_id';
  static const _selectedLocationIdKey = 'selected_location_id';
  static const _selectedLocationNameKey = 'selected_location_name';

  static const Duration _defaultRequestTimeout = Duration(seconds: 45);
  static const Duration _sessionRequestTimeout = Duration(seconds: 90);

  static Duration _timeoutFor(String method, String path) {
    if (method.toUpperCase() == 'POST' && path == '/api/customer/session') {
      return _sessionRequestTimeout;
    }

    return _defaultRequestTimeout;
  }

  static Future<AppData> fetchAppData() async {
    await ensureSession();

    final selectedLocationId = await getSelectedLocationId();
    final selectedLocationName = await getSelectedLocationName();

    final homeJson = await _request(
      method: 'GET',
      path: '/api/customer/home',
      query: {'location_id': selectedLocationId},
      attachToken: true,
    );

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

  static Future<CustomerSession> ensureSession() async {
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
        'selected_quantity': selectedQuantity,
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

  static Future<void> updateCartItemQuantity({
    required String itemId,
    required int quantity,
  }) async {
    await ensureSession();

    await _request(
      method: 'PATCH',
      path: '/api/customer/cart/items/${Uri.encodeComponent(itemId)}',
      body: {'quantity': quantity.clamp(0, 99)},
      attachToken: true,
    );
  }

  static Future<void> deleteCartItem({required String itemId}) async {
    await ensureSession();

    await _request(
      method: 'DELETE',
      path: '/api/customer/cart/items/${Uri.encodeComponent(itemId)}',
      attachToken: true,
    );
  }

  static Future<void> clearCart() async {
    await ensureSession();

    await _request(
      method: 'DELETE',
      path: '/api/customer/cart',
      attachToken: true,
    );
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

    return PlaceOrderResponse.fromJson(json);
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

    return PaymentStatusResponse.fromJson(json);
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

  static Future<CustomerProfileUpdateResponse> updateCustomerGender(
    String? gender,
  ) async {
    return updateCustomerProfile(gender: gender, includeGender: true);
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

  static Future<void> clearCustomerSession() async {
    await _storage.delete(key: _tokenKey);
    await _storage.delete(key: _customerIdKey);
  }

  static Future<String?> getCustomerToken() async {
    return _storage.read(key: _tokenKey);
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
          response = await http
              .get(uri, headers: headers)
              .timeout(requestTimeout);
          break;
        case 'POST':
          response = await http
              .post(uri, headers: headers, body: jsonEncode(body ?? const {}))
              .timeout(requestTimeout);
          break;
        case 'PATCH':
          response = await http
              .patch(uri, headers: headers, body: jsonEncode(body ?? const {}))
              .timeout(requestTimeout);
          break;
        case 'DELETE':
          response = await http
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

    final decoded = decodeJsonObject(response.body, endpoint: '$method $path');

    if (response.statusCode < 200 || response.statusCode >= 300) {
      throw ApiException(
        message: readString(
          decoded['error'],
          fallback: 'Backend request failed.',
        ),
        endpoint: '$method $path',
        statusCode: response.statusCode,
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

    return decoded;
  }
}
