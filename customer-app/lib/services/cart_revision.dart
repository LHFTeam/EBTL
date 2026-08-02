import 'package:flutter/foundation.dart';

/// Counter bumped by [ApiService] the moment a request that changed the cart
/// comes back successful.
///
/// The cart tab keeps its State while other tabs are used, so nothing remounts
/// it when an item is added from a shop sheet or a cocktail detail. It could
/// watch the refreshed app-level cart summary instead — but that summary only
/// arrives if the calling screen wired up an `onCartChanged` callback, so a
/// screen that adds to the cart without one leaves the cart tab showing
/// contents that are silently out of date.
///
/// Bumping here, in the same code path that received the successful response,
/// ties the two together: the write and the invalidation happen as one, and a
/// write that fails invalidates nothing.
class CartRevision {
  const CartRevision._();

  static final ValueNotifier<int> notifier = ValueNotifier<int>(0);

  /// The revision a screen should record when it loads the cart, and compare
  /// against later to find out whether what it is showing still holds.
  static int get current => notifier.value;

  /// Marks every loaded cart as out of date.
  ///
  /// Only ever call this after the backend confirmed the change. A bump the
  /// backend did not earn costs a needless refetch; a missing one shows the
  /// customer a cart that is wrong.
  static void bump() => notifier.value++;

  @visibleForTesting
  static void reset() => notifier.value = 0;
}

/// Whether a request that just succeeded changed the cart, and so has to bump
/// [CartRevision]. Written as a property of the request rather than of the
/// calling method so that a cart endpoint added later is covered by default.
bool isCartWriteRequest({required String method, required String path}) {
  if (method.toUpperCase() == 'GET') return false;

  const cartPath = '/api/customer/cart';
  return path == cartPath || path.startsWith('$cartPath/');
}
