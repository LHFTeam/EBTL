// The cart tab stays mounted while other tabs are used, so it no longer
// refetches by being remounted. It has to notice on its own that items were
// added elsewhere — otherwise the bottom-nav badge counts them while the cart
// page still shows the empty state it loaded earlier.

import 'package:flutter_test/flutter_test.dart';

import 'package:ebtl_customer_app/features/cart/cart_screen.dart';
import 'package:ebtl_customer_app/models/common_models.dart';

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
      String loaded = 'empty',
      String current = 'empty',
      bool isFetching = false,
      bool isActive = true,
    }) {
      return cartRefreshDecision(
        loadedSignature: loaded,
        currentSignature: current,
        isFetching: isFetching,
        isActive: isActive,
      );
    }

    test('does nothing while the cart on screen is up to date', () {
      expect(decide(), CartRefreshDecision.keep);
    });

    test('refetches when the visible cart is behind the summary', () {
      expect(
        decide(loaded: 'empty', current: 'filled'),
        CartRefreshDecision.reload,
      );
    });

    test('leaves a background tab stale instead of refetching', () {
      expect(
        decide(loaded: 'empty', current: 'filled', isActive: false),
        CartRefreshDecision.keep,
      );
    });

    test('refetches when a stale background tab becomes visible', () {
      // Same state as the test above, only now the cart tab is on screen: this
      // is the tap on the cart icon after adding items from the shop.
      expect(
        decide(loaded: 'empty', current: 'filled', isActive: true),
        CartRefreshDecision.reload,
      );
    });

    test('adopts an in-flight fetch instead of firing a second request', () {
      // The screen's own +/- buttons refetch the cart and refresh the app data.
      // The summary landing afterwards must not queue another cart request.
      expect(
        decide(loaded: 'one', current: 'two', isFetching: true),
        CartRefreshDecision.adopt,
      );
    });
  });
}
