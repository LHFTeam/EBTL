import 'package:facebook_app_events/facebook_app_events.dart';
import 'package:firebase_analytics/firebase_analytics.dart';
import 'package:flutter/foundation.dart';

import 'clarity_service.dart';
import 'firebase_bootstrap.dart';

/// A provider-neutral analytics boundary for the customer experience.
///
/// Firebase Analytics and Meta App Events receive structured product/funnel
/// data, while Clarity receives matching screen names and PII-free event
/// markers. Screens should not call vendor SDKs directly.
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
  static const String _metaAppId = '1611789933929380';
  static const bool _enableInDebug = bool.fromEnvironment(
    'ANALYTICS_ENABLE_DEBUG',
  );

  static FirebaseAnalytics? _firebase;
  static final FacebookAppEvents _meta = FacebookAppEvents();
  static bool _metaReady = false;
  static String? _currentScreen;
  static final Set<String> _loggedPurchaseIds = <String>{};

  static bool get _shouldCollect => !kDebugMode || _enableInDebug;

  /// Safe to call on every build. Analytics stays inert when Firebase platform
  /// config is absent, and debug collection is disabled unless explicitly
  /// enabled with --dart-define=ANALYTICS_ENABLE_DEBUG=true.
  static Future<void> initialize() async {
    await _initializeMeta();
    await _initializeFirebase();
  }

  static Future<void> _initializeMeta() async {
    try {
      await _meta.setAutoLogAppEventsEnabled(_shouldCollect);
      await _meta.setAdvertiserIdCollectionEnabled(_shouldCollect);
      if (!_shouldCollect) return;

      await _meta.activateApp(applicationId: _metaAppId);
      _metaReady = true;
    } catch (_) {
      // Meta tracking is best-effort and must never block app startup.
    }
  }

  static Future<void> _initializeFirebase() async {
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
    _sendMeta(
      (events) => events.logEvent(
        name: 'screen_view',
        parameters: {'screen_name': cleanName},
      ),
    );
  }

  static void logOnboardingCompleted() {
    ClarityService.recordEvent('tutorial_complete');
    _sendFirebase((analytics) => analytics.logTutorialComplete());
    _sendMeta(
      (events) => events.logCompletedTutorial(contentId: 'customer_onboarding'),
    );
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
    _sendMeta(
      (events) => events.logFindLocation(parameters: {'location_id': cleanId}),
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
    _sendMeta(
      (events) => events.logSearched(
        searchString: hasQuery ? 'query_provided' : null,
        contentType: surface,
        parameters: {'has_query': hasQuery},
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
    _sendMeta(
      (events) => events.logViewContent(
        id: item.id,
        type: item.category,
        currency: item.currency,
        price: item.price * item.quantity,
        parameters: _metaItemParameters(item),
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
    _sendMeta(
      (events) => events.logAddToCart(
        id: item.id,
        type: item.category,
        currency: item.currency,
        price: item.price * item.quantity,
        parameters: _metaItemParameters(item),
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
      _sendMeta(
        (events) => events.logAddToWishlist(
          id: item.id,
          type: item.category,
          currency: item.currency,
          price: item.price * item.quantity,
          parameters: _metaItemParameters(item),
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
    _sendMeta(
      (events) => events.logEvent(
        name: 'remove_from_wishlist',
        parameters: {
          'content_id': item.id,
          'content_type': item.category,
          ..._metaItemParameters(item),
        },
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

    final cleanCoupon = _cleanOptional(coupon);
    _sendMeta(
      (events) => events.logInitiatedCheckout(
        totalPrice: value,
        currency: currency,
        contentType: 'product',
        contentId: items.map((item) => item.id).join(','),
        numItems: items.fold<int>(0, (total, item) => total + item.quantity),
        parameters: {
          'fulfillment_type': fulfillmentType,
          'coupon': ?cleanCoupon,
        },
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
    final cleanCoupon = _cleanOptional(coupon);
    _sendMeta(
      (events) => events.logPurchase(
        amount: value,
        currency: currency,
        parameters: {
          'transaction_id': cleanId,
          'tax': tax,
          'shipping': shipping,
          'coupon': ?cleanCoupon,
        },
      ),
    );
  }

  static String? _cleanOptional(String? value) {
    final cleanValue = value?.trim();
    return cleanValue == null || cleanValue.isEmpty ? null : cleanValue;
  }

  static Map<String, dynamic> _metaItemParameters(AnalyticsItem item) {
    final parameters = <String, dynamic>{
      'content_name': item.name,
      'quantity': item.quantity,
    };
    final variant = _cleanOptional(item.variant);
    if (variant != null) parameters['content_variant'] = variant;
    return parameters;
  }

  static void _sendFirebase(
    Future<void> Function(FirebaseAnalytics analytics) operation,
  ) {
    final analytics = _firebase;
    if (analytics == null) return;
    operation(analytics).catchError((_) {});
  }

  static void _sendMeta(
    Future<void> Function(FacebookAppEvents events) operation,
  ) {
    if (!_metaReady) return;
    operation(_meta).catchError((_) {});
  }
}
