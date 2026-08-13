import 'package:facebook_app_events/facebook_app_events.dart';
import 'package:firebase_analytics/firebase_analytics.dart';
import 'package:flutter/foundation.dart';

import 'clarity_service.dart';
import 'firebase_bootstrap.dart';

/// A provider-neutral analytics boundary for the customer experience.
///
/// Firebase Analytics and Meta App Events receive structured product/funnel
/// data, while Clarity receives matching screen names, PII-free event markers
/// and session tags. Screens should not call vendor SDKs directly.
///
/// The two are answering different questions and both are wired on purpose:
/// Firebase counts (how many people opened Negroni, how many added it),
/// Clarity shows (the recordings of the sessions that did). A funnel step
/// worth counting is worth being able to watch, so a new event here should
/// normally set a Clarity marker as well.
///
/// Where a surface names itself. Sent as GA4's `item_list_name` on the item
/// and as a `source` parameter on the event, which is what makes
/// "Finder → detail → cart" answerable in one report rather than three.
class AnalyticsSource {
  static const String home = 'home';
  static const String heroBanner = 'home_hero_banner';
  static const String spotlight = 'spotlight_banner';
  static const String goldenHour = 'golden_hour';
  static const String orderAgain = 'order_again';
  static const String recentlyViewed = 'recently_viewed';
  static const String explore = 'explore';
  static const String search = 'catalog_search';
  static const String shop = 'shop';
  static const String shopCategory = 'shop_category';
  static const String cocktailFinder = 'cocktail_finder';
  static const String relatedCocktail = 'related_cocktail';
  static const String favorites = 'favorites';

  const AnalyticsSource._();
}

/// Which banner surface a promotion tap came from — GA4's `creative_slot`.
class AnalyticsPromotionSlot {
  static const String heroCarousel = 'home_hero_carousel';
  static const String spotlightRail = 'home_spotlight_rail';
  static const String goldenHourModal = 'golden_hour_modal';

  const AnalyticsPromotionSlot._();
}

class AnalyticsItem {
  final String id;
  final String name;
  final String category;
  final String? variant;
  final double price;
  final int quantity;
  final String currency;

  /// The surface the customer was on when they viewed or added this — an
  /// [AnalyticsSource] constant.
  final String? source;

  /// Which instance of that surface: the Finder bottle that was selected, or
  /// the banner whose sheet this was opened from. Reported as `source_detail`.
  final String? sourceDetail;

  const AnalyticsItem({
    required this.id,
    required this.name,
    required this.category,
    required this.price,
    required this.quantity,
    required this.currency,
    this.variant,
    this.source,
    this.sourceDetail,
  });

  AnalyticsEventItem toFirebaseItem() {
    return AnalyticsEventItem(
      itemId: id,
      itemName: name,
      itemBrand: 'EBTL',
      itemCategory: category,
      itemVariant: variant,
      itemListName: AnalyticsService._cleanOptional(source),
      price: price,
      quantity: quantity,
      currency: currency,
    );
  }

  /// The origin repeated as event-scoped parameters. GA4 reports on those
  /// without the item-scoped custom dimensions the `items` array needs, so
  /// both carry it.
  Map<String, Object>? get sourceParameters {
    final cleanSource = AnalyticsService._cleanOptional(source);
    final cleanDetail = AnalyticsService._cleanOptional(sourceDetail);
    if (cleanSource == null && cleanDetail == null) return null;

    return <String, Object>{
      'source': ?cleanSource,
      'source_detail': ?cleanDetail,
    };
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

  /// A product detail page open — the cocktail detail screen or the shop
  /// product sheet. Reported by name and category on both providers.
  static void logViewItem(AnalyticsItem item) {
    ClarityService.recordEvent('view_item');
    _tagClarityItem(item, nameKey: 'product_viewed');

    _sendFirebase(
      (analytics) => analytics.logViewItem(
        currency: item.currency,
        value: item.price * item.quantity,
        items: [item.toFirebaseItem()],
        parameters: item.sourceParameters,
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
    _tagClarityItem(item, nameKey: 'product_added');

    _sendFirebase(
      (analytics) => analytics.logAddToCart(
        currency: item.currency,
        value: item.price * item.quantity,
        items: [item.toFirebaseItem()],
        parameters: item.sourceParameters,
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

  /// A tap on a merchandising banner: a Home hero slide, a Spotlight rail card,
  /// or the Golden Hour card's call to action.
  ///
  /// [promotionName] is the banner as marketing named it, which is what makes
  /// one banner comparable against another; [slot] is which rail it sat in (an
  /// [AnalyticsPromotionSlot]), and [destination] the deep link or sheet it
  /// opened. Everything the tap leads to is then tagged with a matching
  /// [AnalyticsSource], so the click and the sale it produced join up.
  static void logPromotionSelected({
    required String promotionId,
    required String promotionName,
    required String slot,
    String? destination,
  }) {
    final cleanId = _cleanOptional(promotionId);
    final cleanName = _cleanOptional(promotionName);

    // A banner with neither a name nor an id says nothing a report could use.
    if (cleanId == null && cleanName == null) return;

    final reportedName = cleanName ?? cleanId!;
    final cleanDestination = _cleanOptional(destination);

    ClarityService.recordEvent('select_promotion');
    ClarityService.setTag('banner_clicked', reportedName);

    _sendFirebase(
      (analytics) => analytics.logSelectPromotion(
        promotionId: cleanId,
        promotionName: reportedName,
        creativeSlot: slot,
        parameters: {'banner_destination': ?cleanDestination},
      ),
    );
    _sendMeta(
      (events) => events.logEvent(
        name: 'select_promotion',
        parameters: {
          'promotion_id': ?cleanId,
          'promotion_name': reportedName,
          'creative_slot': slot,
          'banner_destination': ?cleanDestination,
        },
      ),
    );
  }

  /// The Cocktail Finder's opening question: which bottle the customer already
  /// has. [selectionCount] is how many bottles are selected once the change has
  /// landed, which separates "picked one bottle" from "widened the net" —
  /// and, at zero, marks the customer backing all the way out.
  ///
  /// The steps after this one are ordinary product events carrying
  /// [AnalyticsSource.cocktailFinder]: which cocktails were opened from the
  /// results, and which of those were added.
  static void logFinderBottleChanged({
    required String bottleName,
    required bool isSelected,
    required int selectionCount,
  }) {
    final cleanName = _cleanOptional(bottleName);
    if (cleanName == null) return;

    final eventName = isSelected
        ? 'finder_bottle_selected'
        : 'finder_bottle_deselected';

    ClarityService.recordEvent(eventName);
    if (isSelected) ClarityService.setTag('finder_bottle', cleanName);

    _sendFirebase(
      (analytics) => analytics.logEvent(
        name: eventName,
        parameters: {
          'bottle_name': cleanName,
          'selected_bottle_count': selectionCount,
        },
      ),
    );
    _sendMeta(
      (events) => events.logEvent(
        name: eventName,
        parameters: {
          'bottle_name': cleanName,
          'selected_bottle_count': selectionCount,
        },
      ),
    );
  }

  /// Mirrors a product event into Clarity as session tags, so a count in
  /// Firebase can be turned into the recordings behind it. Names only — the
  /// price and id would be noise on a replay filter.
  static void _tagClarityItem(AnalyticsItem item, {required String nameKey}) {
    ClarityService.setTag(nameKey, item.name);
    ClarityService.setTag('product_category', item.category);

    final source = _cleanOptional(item.source);
    if (source != null) ClarityService.setTag('product_source', source);
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
