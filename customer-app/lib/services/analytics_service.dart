import 'package:firebase_analytics/firebase_analytics.dart';
import 'package:flutter/foundation.dart';

import 'clarity_service.dart';
import 'firebase_bootstrap.dart';

/// A provider-neutral analytics boundary for the customer experience.
///
/// Firebase Analytics receives structured product/funnel data and Clarity
/// receives matching screen names and PII-free event markers. Meta App Events
/// will plug into this same class after the Meta Developer App ID and Client
/// Token are available; screens should not call vendor SDKs directly.
class AnalyticsItem {
  final String id;
  final String name;
  final String category;
  final String? variant;
  final double price;
  final int quantity;
  final String currency;

  const AnalyticsItem({
    required this.id,
    required this.name,
    required this.category,
    required this.price,
    required this.quantity,
    required this.currency,
    this.variant,
  });

  AnalyticsEventItem toFirebaseItem() {
    return AnalyticsEventItem(
      itemId: id,
      itemName: name,
      itemBrand: 'EBTL',
      itemCategory: category,
      itemVariant: variant,
      price: price,
      quantity: quantity,
      currency: currency,
    );
  }
}

class AnalyticsService {
  static const bool _enableInDebug = bool.fromEnvironment(
    'ANALYTICS_ENABLE_DEBUG',
  );

  static FirebaseAnalytics? _firebase;
  static String? _currentScreen;
  static final Set<String> _loggedPurchaseIds = <String>{};

  static bool get _shouldCollect => !kDebugMode || _enableInDebug;

  /// Safe to call on every build. Analytics stays inert when Firebase platform
  /// config is absent, and debug collection is disabled unless explicitly
  /// enabled with --dart-define=ANALYTICS_ENABLE_DEBUG=true.
  static Future<void> initialize() async {
    final ready = await FirebaseBootstrap.ensureInitialized();
    if (!ready) return;

    try {
      final analytics = FirebaseAnalytics.instance;
      await analytics.setAnalyticsCollectionEnabled(_shouldCollect);
      if (!_shouldCollect) return;

      await analytics.setDefaultEventParameters({
        'app_surface': 'customer_app',
      });
      _firebase = analytics;
    } catch (_) {
      // Analytics is best-effort and must never block app startup.
    }
  }

  static void logScreenView(String screenName) {
    final cleanName = screenName.trim();
    if (cleanName.isEmpty || cleanName == _currentScreen) return;

    _currentScreen = cleanName;
    ClarityService.setScreenName(cleanName);
    _sendFirebase(
      (analytics) => analytics.logScreenView(
        screenName: cleanName,
        screenClass: cleanName,
      ),
    );
  }

  static void logOnboardingCompleted() {
    ClarityService.recordEvent('tutorial_complete');
    _sendFirebase((analytics) => analytics.logTutorialComplete());
  }

  static void logLocationSelected(String locationId) {
    final cleanId = locationId.trim();
    if (cleanId.isEmpty) return;

    ClarityService.recordEvent('select_location');
    _sendFirebase(
      (analytics) => analytics.logEvent(
        name: 'select_location',
        parameters: {'location_id': cleanId},
      ),
    );
  }

  static void logSearch({required String surface, required bool hasQuery}) {
    ClarityService.recordEvent('search');
    _sendFirebase(
      (analytics) => analytics.logEvent(
        name: 'search_submitted',
        parameters: {'search_surface': surface, 'has_query': hasQuery ? 1 : 0},
      ),
    );
  }

  static void logViewItem(AnalyticsItem item) {
    ClarityService.recordEvent('view_item');
    _sendFirebase(
      (analytics) => analytics.logViewItem(
        currency: item.currency,
        value: item.price * item.quantity,
        items: [item.toFirebaseItem()],
      ),
    );
  }

  static void logAddToCart(AnalyticsItem item) {
    ClarityService.recordEvent('add_to_cart');
    _sendFirebase(
      (analytics) => analytics.logAddToCart(
        currency: item.currency,
        value: item.price * item.quantity,
        items: [item.toFirebaseItem()],
      ),
    );
  }

  static void logFavoriteChanged({
    required AnalyticsItem item,
    required bool isFavorite,
  }) {
    ClarityService.recordEvent(
      isFavorite ? 'add_to_wishlist' : 'remove_from_wishlist',
    );

    if (isFavorite) {
      _sendFirebase(
        (analytics) => analytics.logAddToWishlist(
          currency: item.currency,
          value: item.price * item.quantity,
          items: [item.toFirebaseItem()],
        ),
      );
      return;
    }

    _sendFirebase(
      (analytics) => analytics.logEvent(
        name: 'remove_from_wishlist',
        items: [item.toFirebaseItem()],
      ),
    );
  }

  static void logBeginCheckout({
    required double value,
    required String currency,
    required List<AnalyticsItem> items,
    String? coupon,
    required String fulfillmentType,
  }) {
    ClarityService.recordEvent('begin_checkout');
    _sendFirebase(
      (analytics) => analytics.logBeginCheckout(
        value: value,
        currency: currency,
        items: items.map((item) => item.toFirebaseItem()).toList(),
        coupon: _cleanOptional(coupon),
        parameters: {'fulfillment_type': fulfillmentType},
      ),
    );
  }

  static void logPurchase({
    required String transactionId,
    required double value,
    required String currency,
    required double tax,
    required double shipping,
    String? coupon,
  }) {
    final cleanId = transactionId.trim();
    if (cleanId.isEmpty || !_loggedPurchaseIds.add(cleanId)) return;

    ClarityService.recordEvent('purchase');
    _sendFirebase(
      (analytics) => analytics.logPurchase(
        transactionId: cleanId,
        value: value,
        currency: currency,
        tax: tax,
        shipping: shipping,
        coupon: _cleanOptional(coupon),
        affiliation: 'EBTL Customer App',
      ),
    );
  }

  static String? _cleanOptional(String? value) {
    final cleanValue = value?.trim();
    return cleanValue == null || cleanValue.isEmpty ? null : cleanValue;
  }

  static void _sendFirebase(
    Future<void> Function(FirebaseAnalytics analytics) operation,
  ) {
    final analytics = _firebase;
    if (analytics == null) return;
    operation(analytics).catchError((_) {});
  }
}
