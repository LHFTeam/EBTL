// The guarantees ApiService carries live in _request, not in the individual
// endpoint methods: a cart write invalidates every loaded cart, a request that
// failed invalidates nothing, and a rejected token is recovered from exactly
// once. None of that could be asserted while requests went through the
// top-level http functions — these tests exist because the client is injectable.

import 'dart:convert';

import 'package:flutter_secure_storage/flutter_secure_storage.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';

import 'package:ebtl_customer_app/core/network/api_exception.dart';
import 'package:ebtl_customer_app/services/api_service.dart';
import 'package:ebtl_customer_app/services/cart_revision.dart';

/// Records every request the service makes, so a test can assert how many went
/// out rather than only what came back.
class RecordingClient {
  final List<http.Request> requests = <http.Request>[];
  late final MockClient client;

  RecordingClient(http.Response Function(http.Request request) respond) {
    client = MockClient((request) async {
      requests.add(request);
      return respond(request);
    });
  }

  List<String> get paths =>
      requests.map((request) => request.url.path).toList();
}

http.Response json(Map<String, dynamic> body, {int status = 200}) {
  return http.Response(
    jsonEncode(body),
    status,
    headers: const {'content-type': 'application/json'},
  );
}

const _cartSummaryJson = {
  'cart_id': 'cart-1',
  'item_count': 2,
  'total_quantity': 3,
  'subtotal_inc_vat': 250.0,
  'currency': 'EGP',
};

void main() {
  setUp(() {
    // A stored token keeps ensureSession() from bootstrapping, so each test
    // sees only the requests it is about.
    FlutterSecureStorage.setMockInitialValues({
      'customer_session_token': 'token-1',
      'customer_id': 'customer-1',
    });
    CartRevision.reset();
  });

  tearDown(ApiService.resetClient);

  group('cart writes and CartRevision', () {
    test('a write that succeeds invalidates loaded carts', () async {
      final recorder = RecordingClient(
        (_) => json({
          'action': {'type': 'item_added'},
          'cartSummary': _cartSummaryJson,
        }),
      );
      ApiService.client = recorder.client;

      final before = CartRevision.current;

      await ApiService.addShopProductToCart(
        productId: 'product-1',
        variantId: 'variant-1',
        quantity: 1,
        locationId: 'location-1',
      );

      expect(CartRevision.current, isNot(before));
    });

    test('a write that fails invalidates nothing', () async {
      final recorder = RecordingClient(
        (_) => json({'error': 'Item is not available.'}, status: 400),
      );
      ApiService.client = recorder.client;

      final before = CartRevision.current;

      await expectLater(
        ApiService.addShopProductToCart(
          productId: 'product-1',
          variantId: 'variant-1',
          quantity: 1,
          locationId: 'location-1',
        ),
        throwsA(isA<ApiException>()),
      );

      expect(CartRevision.current, before);
    });

    test('reading the cart invalidates nothing', () async {
      final recorder = RecordingClient(
        (_) => json({
          'cart': {'id': 'cart-1'},
          'items': [],
        }),
      );
      ApiService.client = recorder.client;

      final before = CartRevision.current;
      await ApiService.fetchCart(locationId: 'location-1');

      expect(CartRevision.current, before);
    });

    test('a write outside the cart namespace invalidates nothing', () async {
      final recorder = RecordingClient((_) => json({'favorite': true}));
      ApiService.client = recorder.client;

      final before = CartRevision.current;
      await ApiService.addFavoriteCocktail(productId: 'product-1');

      expect(CartRevision.current, before);
    });
  });

  group('cart writes answer with the new summary', () {
    test('a quantity change returns the summary from its own response', () async {
      final recorder = RecordingClient(
        (_) => json({'cartSummary': _cartSummaryJson}),
      );
      ApiService.client = recorder.client;

      final summary = await ApiService.updateCartItemQuantity(
        itemId: 'item-1',
        quantity: 3,
      );

      expect(summary?.totalQuantity, 3);
      expect(summary?.itemCount, 2);
      // The badge is updated from this one response — no follow-up /home fetch.
      expect(recorder.paths, ['/api/customer/cart/items/item-1']);
    });

    test('deleting an item returns the summary', () async {
      final recorder = RecordingClient(
        (_) => json({
          'removed_item_id': 'item-1',
          'cartSummary': _cartSummaryJson,
        }),
      );
      ApiService.client = recorder.client;

      final summary = await ApiService.deleteCartItem(itemId: 'item-1');

      expect(summary?.totalQuantity, 3);
    });

    test('clearing the cart stands in an emptied summary', () async {
      // This endpoint answers `{cart_id, cleared: true}` and no summary.
      final recorder = RecordingClient(
        (_) => json({'cart_id': 'cart-1', 'cleared': true}),
      );
      ApiService.client = recorder.client;

      final summary = await ApiService.clearCart();

      expect(summary?.cartId, 'cart-1');
      expect(summary?.totalQuantity, 0);
      expect(summary?.itemCount, 0);
    });
  });

  group('cart quantity bounds', () {
    test('cocktail additions clamp quantities to the supported range', () async {
      final recorder = RecordingClient(
        (_) => json({
          'action': {'type': 'item_added'},
          'cartSummary': _cartSummaryJson,
        }),
      );
      ApiService.client = recorder.client;

      await ApiService.addCocktailToCart(
        cocktailId: 'cocktail-1',
        variantId: 'variant-1',
        selectedQuantity: 0,
        locationId: 'location-1',
      );
      await ApiService.addCocktailToCart(
        cocktailId: 'cocktail-1',
        variantId: 'variant-1',
        selectedQuantity: 120,
        locationId: 'location-1',
      );

      final quantities = recorder.requests
          .map((request) => jsonDecode(request.body) as Map<String, dynamic>)
          .map((body) => body['selected_quantity'])
          .toList();
      expect(quantities, [1, 99]);
    });
  });

  group('a rejected token', () {
    test('is re-minted and the request replayed exactly once', () async {
      var cartAttempts = 0;

      final recorder = RecordingClient((request) {
        if (request.url.path == '/api/customer/session') {
          return json({
            'session': {
              'customer_session_token': 'token-2',
              'customer_id': 'customer-1',
            },
          });
        }

        cartAttempts++;
        // The stored token is stale on the first attempt and fine on the replay.
        return cartAttempts == 1
            ? json({'error': 'Unauthorized.'}, status: 401)
            : json({
                'action': {'type': 'item_added'},
                'cartSummary': _cartSummaryJson,
              });
      });
      ApiService.client = recorder.client;

      final before = CartRevision.current;

      final result = await ApiService.addShopProductToCart(
        productId: 'product-1',
        variantId: 'variant-1',
        quantity: 1,
        locationId: 'location-1',
      );

      expect(result.totals?.totalQuantity, 3);
      expect(cartAttempts, 2);
      expect(recorder.paths, [
        '/api/customer/cart/items',
        '/api/customer/session',
        '/api/customer/cart/items',
      ]);
      // The replay is what succeeded, so the cart is invalidated once, not twice.
      expect(CartRevision.current, before + 1);
    });

    test('is given up on after one replay', () async {
      final recorder = RecordingClient((request) {
        if (request.url.path == '/api/customer/session') {
          return json({
            'session': {
              'customer_session_token': 'token-2',
              'customer_id': 'customer-1',
            },
          });
        }

        return json({'error': 'Unauthorized.'}, status: 401);
      });
      ApiService.client = recorder.client;

      final before = CartRevision.current;

      await expectLater(
        ApiService.addShopProductToCart(
          productId: 'product-1',
          variantId: 'variant-1',
          quantity: 1,
          locationId: 'location-1',
        ),
        throwsA(isA<ApiException>()),
      );

      // Two attempts at the write, one session mint — not a retry loop.
      expect(
        recorder.paths
            .where((path) => path == '/api/customer/cart/items')
            .length,
        2,
      );
      expect(CartRevision.current, before);
    });
  });
}
