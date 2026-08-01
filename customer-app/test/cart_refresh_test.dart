// The cart tab stays mounted while other tabs are used, so it no longer
// refetches by being remounted. It has to notice on its own that the cart
// changed — otherwise the bottom-nav badge counts items the cart page below it
// still does not show.
//
// The signal it trusts is CartRevision, which ApiService bumps in the same code
// path that received the successful write. These tests pin that pairing: a
// write that succeeded always leaves the cart tab knowing it must reload, and a
// write that failed leaves nothing to reload.

import 'package:flutter_test/flutter_test.dart';

import 'package:ebtl_customer_app/features/cart/cart_screen.dart';
import 'package:ebtl_customer_app/models/common_models.dart';
import 'package:ebtl_customer_app/services/cart_revision.dart';

CartSummary summary({
  String cartId = 'cart-1',
  int itemCount = 0,
  int totalQuantity = 0,
}) {
  return CartSummary(
    cartId: cartId,
    itemCount: itemCount,
    totalQuantity: totalQuantity,
    subtotalIncVat: 0,
    currency: 'EGP',
  );
}

void main() {
  group('CartRevision', () {
    setUp(CartRevision.reset);

    test('a bump moves the revision past what a screen loaded', () {
      final loaded = CartRevision.current;
      CartRevision.bump();

      expect(CartRevision.current, isNot(loaded));
    });

    test('every bump is seen, so back-to-back writes cannot cancel out', () {
      final loaded = CartRevision.current;
      CartRevision.bump();
      CartRevision.bump();

      expect(CartRevision.current, isNot(loaded));
    });

    test('notifies listeners so a visible cart tab reloads without a rebuild', () {
      var notifications = 0;
      void listener() => notifications++;

      CartRevision.notifier.addListener(listener);
      addTearDown(() => CartRevision.notifier.removeListener(listener));

      CartRevision.bump();
      CartRevision.bump();

      expect(notifications, 2);
    });
  });

  group('isCartWriteRequest', () {
    test('covers every request that changes the cart', () {
      // These are the four cart writes the app makes today. The rule is written
      // against the request, not the calling method, so a fifth one added later
      // invalidates loaded carts without anyone remembering to wire it up.
      expect(
        isCartWriteRequest(method: 'POST', path: '/api/customer/cart/items'),
        isTrue,
      );
      expect(
        isCartWriteRequest(
          method: 'PATCH',
          path: '/api/customer/cart/items/item-1',
        ),
        isTrue,
      );
      expect(
        isCartWriteRequest(
          method: 'DELETE',
          path: '/api/customer/cart/items/item-1',
        ),
        isTrue,
      );
      expect(
        isCartWriteRequest(method: 'DELETE', path: '/api/customer/cart'),
        isTrue,
      );
    });

    test('reading the cart changes nothing', () {
      expect(
        isCartWriteRequest(method: 'GET', path: '/api/customer/cart'),
        isFalse,
      );
    });

    test('leaves requests to other endpoints alone', () {
      expect(
        isCartWriteRequest(method: 'POST', path: '/api/customer/session'),
        isFalse,
      );
      expect(
        isCartWriteRequest(
          method: 'POST',
          path: '/api/customer/checkout/place-order',
        ),
        isFalse,
      );
      expect(
        isCartWriteRequest(method: 'POST', path: '/api/customer/cartons'),
        isFalse,
      );
    });
  });

  group('cartSummarySignature', () {
    test('changes when items are added to the cart', () {
      final empty = cartSummarySignature(summary());
      final filled = cartSummarySignature(
        summary(itemCount: 1, totalQuantity: 2),
      );

      expect(empty, isNot(filled));
    });

    test('changes when quantity moves but the item count does not', () {
      expect(
        cartSummarySignature(summary(itemCount: 1, totalQuantity: 1)),
        isNot(cartSummarySignature(summary(itemCount: 1, totalQuantity: 2))),
      );
    });

    test('changes when checkout replaces the cart', () {
      expect(
        cartSummarySignature(summary(cartId: 'cart-1')),
        isNot(cartSummarySignature(summary(cartId: 'cart-2'))),
      );
    });

    test('is stable for the same cart', () {
      expect(
        cartSummarySignature(summary(itemCount: 2, totalQuantity: 3)),
        cartSummarySignature(summary(itemCount: 2, totalQuantity: 3)),
      );
    });

    test('handles a missing summary', () {
      expect(cartSummarySignature(null), isNot(cartSummarySignature(summary())));
    });
  });

  group('cartRefreshDecision', () {
    CartRefreshDecision decide({
      bool revisionChanged = false,
      bool summaryChanged = false,
      bool isFetching = false,
      bool isActive = true,
    }) {
      return cartRefreshDecision(
        revisionChanged: revisionChanged,
        summaryChanged: summaryChanged,
        isFetching: isFetching,
        isActive: isActive,
      );
    }

    test('does nothing while the cart on screen is up to date', () {
      expect(decide(), CartRefreshDecision.keep);
    });

    test('refetches once a write has landed', () {
      // The add succeeded, so the revision moved: the cart tab reloads even if
      // no app-level refresh ever arrives to tell it what changed.
      expect(
        decide(revisionChanged: true, summaryChanged: false),
        CartRefreshDecision.reload,
      );
    });

    test('leaves a background tab stale instead of refetching', () {
      expect(
        decide(revisionChanged: true, isActive: false),
        CartRefreshDecision.keep,
      );
    });

    test('refetches when a stale background tab becomes visible', () {
      // Same state as the test above, only now the cart tab is on screen: this
      // is the tap on the cart icon after adding items from the shop.
      expect(
        decide(revisionChanged: true, isActive: true),
        CartRefreshDecision.reload,
      );
    });

    test('a landed write outranks an in-flight fetch that predates it', () {
      expect(
        decide(revisionChanged: true, isFetching: true),
        CartRefreshDecision.reload,
      );
    });

    test('adopts an in-flight fetch when only the summary caught up', () {
      // The screen's own +/- buttons write, refetch, then refresh the app data.
      // No write landed after that refetch went out, so the summary arriving
      // afterwards must not queue a second request.
      expect(
        decide(revisionChanged: false, summaryChanged: true, isFetching: true),
        CartRefreshDecision.adopt,
      );
    });

    test('refetches on a summary that drifted with no write of ours', () {
      // Nothing this app did moved the cart, so the change came from the
      // backend — an expired cart, or another device.
      expect(
        decide(revisionChanged: false, summaryChanged: true),
        CartRefreshDecision.reload,
      );
    });
  });
}
