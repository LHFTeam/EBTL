import 'dart:async';

import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';

import 'shared/widgets/app_state_widgets.dart';

import 'core/network/api_exception.dart';
import 'core/theme/ebtl_colors.dart';

/* -------------------------------- MODELS -------------------------------- */
import 'models/common_models.dart';
import 'models/cocktail_models.dart';
import 'models/app_data.dart';
import 'models/notification_models.dart';
import 'models/profile_models.dart';
import 'models/shop_models.dart';

/* -------------------------------- SCREENS -------------------------------- */
import 'features/home/home_screen.dart';
import 'features/finder/finder_screen.dart';
import 'features/explore/explore_screen.dart';
import 'features/cocktail_detail/cocktail_detail_screen.dart';
import 'features/cart/cart_screen.dart';
import 'features/checkout/checkout_screen.dart';
import 'features/profile/profile_screen.dart';
import 'features/profile/active_orders_screen.dart';
import 'features/profile/customer_orders_screen.dart';
import 'features/profile/order_detail_screen.dart';
import 'features/profile/customer_notifications_screen.dart';
import 'features/shop/shop_category_products_screen.dart';
import 'features/onboarding/onboarding_screen.dart';

/* -------------------------------- SHARED WIDGETS -------------------------------- */
import 'shared/widgets/ebtl_bottom_nav.dart';

/* --------------------------------- SERVICES --------------------------------- */
import 'services/api_service.dart';
import 'services/analytics_service.dart';
import 'services/clarity_service.dart';
import 'services/crash_reporting_service.dart';
import 'services/push_notification_service.dart';

Future<void> main() async {
  WidgetsFlutterBinding.ensureInitialized();
  // Install global crash/error handlers before the first frame so startup
  // failures are captured too. No-op when Firebase is not configured.
  await CrashReportingService.initialize();
  await AnalyticsService.initialize();
  runApp(ClarityService.wrap(const EbtlApp()));
}

/*
  EBTL CUSTOMER APP - CUSTOMER API VERSION

  This file holds the app shell: EbtlApp (theme), AppStartupGate
  (onboarding gate), and RootShell (bottom-nav tab host). Screens live
  in lib/features/; all backend access goes through ApiService
  (the /api/customer namespace).

  Important:
  - No demo fallback data.
  - No customer login.
  - Anonymous customer session token is stored locally.
  - Selected beach cart/location is stored locally.
  - location_id is sent to the backend whenever product availability is needed.
*/

class EbtlApp extends StatelessWidget {
  const EbtlApp({super.key});

  @override
  Widget build(BuildContext context) {
    final baseText = GoogleFonts.manropeTextTheme();

    return MaterialApp(
      debugShowCheckedModeBanner: false,
      title: 'EBTL',
      theme: ThemeData(
        useMaterial3: true,
        scaffoldBackgroundColor: EbtlColors.cream,
        colorScheme: ColorScheme.fromSeed(
          seedColor: EbtlColors.coral,
          primary: EbtlColors.coral,
          secondary: EbtlColors.teal,
          surface: EbtlColors.white,
        ),
        textTheme: baseText.apply(
          bodyColor: EbtlColors.ink,
          displayColor: EbtlColors.navy,
        ),
      ),
      home: const AppStartupGate(),
    );
  }
}

class AppStartupGate extends StatefulWidget {
  const AppStartupGate({super.key});

  @override
  State<AppStartupGate> createState() => _AppStartupGateState();
}

class _AppStartupGateState extends State<AppStartupGate> {
  late Future<bool> _hasCompletedOnboardingFuture;

  @override
  void initState() {
    super.initState();
    _hasCompletedOnboardingFuture = ApiService.hasCompletedOnboarding();
  }

  Future<void> _completeOnboarding() async {
    await ApiService.markOnboardingCompleted();
    AnalyticsService.logOnboardingCompleted();
    if (!mounted) return;

    setState(() {
      _hasCompletedOnboardingFuture = Future.value(true);
    });
  }

  @override
  Widget build(BuildContext context) {
    return FutureBuilder<bool>(
      future: _hasCompletedOnboardingFuture,
      builder: (context, snapshot) {
        if (snapshot.connectionState == ConnectionState.waiting) {
          return theLoadingScaffold();
        }

        if (snapshot.data == true) {
          return const RootShell();
        }

        return OnboardingScreen(onCompleted: _completeOnboarding);
      },
    );
  }
}

class RootShell extends StatefulWidget {
  const RootShell({super.key});

  @override
  State<RootShell> createState() => _RootShellState();
}

class _RootShellState extends State<RootShell> with WidgetsBindingObserver {
  static const Duration _notificationsPollInterval = Duration(seconds: 30);

  /// How often the orders behind Home's live-order card are re-fetched while
  /// an order is still being made, so the card follows the kitchen without the
  /// customer pulling to refresh.
  static const Duration _liveOrderPollInterval = Duration(seconds: 20);

  int selectedIndex = EbtlBottomNav.homeIndex;

  /// The last successfully loaded payload. Kept across refreshes so a reload
  /// never unmounts the tab subtree — screens hold their own fetched state, and
  /// tearing them down is what made every cart change refetch the whole app.
  AppData? appData;
  Object? appDataError;
  bool isLoadingAppData = false;

  /// Tabs that have been opened at least once. The [IndexedStack] keeps these
  /// mounted so switching back to one does not re-run its `initState` (and its
  /// fetch); unvisited tabs stay unbuilt so startup still pays for Home only.
  final Set<int> visitedTabs = {EbtlBottomNav.homeIndex};

  Timer? _notificationsTimer;
  int unreadNotificationCount = 0;
  String? _latestUnreadNotificationId;
  bool _notificationsBaselineSeeded = false;
  bool _isPollingNotifications = false;
  StreamSubscription<void>? _pushSubscription;

  /// The customer's orders, newest first, as last loaded. Home reads the
  /// order still being made and the finished ones behind "Order It Again" from
  /// here; the top-bar shortcut reads the active count.
  List<ProfileOrder> customerOrders = const [];
  int activeOrdersCount = 0;
  bool _isRefreshingActiveOrders = false;
  Timer? _liveOrderTimer;
  String? _lastOrdersSignature;

  @override
  void initState() {
    super.initState();
    AnalyticsService.logScreenView('home');
    loadAppData();
    WidgetsBinding.instance.addObserver(this);
    PushNotificationService.initialize();
    _pushSubscription = PushNotificationService.onMessage.listen(
      (_) => _handlePushMessage(),
    );
    _startNotificationsPolling(notifyImmediately: false);
    _startLiveOrderPolling();
    _refreshActiveOrders();
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    _notificationsTimer?.cancel();
    _liveOrderTimer?.cancel();
    _pushSubscription?.cancel();
    super.dispose();
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    // Dart timers keep firing while the app is paused, so stop polling in
    // the background and pick it back up (with an immediate check) on resume.
    if (state == AppLifecycleState.resumed) {
      _startNotificationsPolling(notifyImmediately: true);
      _startLiveOrderPolling();
      _refreshActiveOrders();
    } else if (state == AppLifecycleState.paused) {
      _notificationsTimer?.cancel();
      _notificationsTimer = null;
      _liveOrderTimer?.cancel();
      _liveOrderTimer = null;
    }
  }

  void _startNotificationsPolling({required bool notifyImmediately}) {
    _pollNotifications(canNotify: notifyImmediately);
    _notificationsTimer?.cancel();
    _notificationsTimer = Timer.periodic(
      _notificationsPollInterval,
      (_) => _pollNotifications(canNotify: true),
    );
  }

  /// Keeps Home's live-order card in step with the order as staff move it
  /// along. Only orders still in flight are worth re-fetching for — a new
  /// order arrives through checkout or a push/notification, both of which
  /// refresh on their own.
  void _startLiveOrderPolling() {
    _liveOrderTimer?.cancel();
    _liveOrderTimer = Timer.periodic(_liveOrderPollInterval, (_) {
      if (activeOrdersCount > 0) _refreshActiveOrders();
    });
  }

  /// A push landing while the app is open means something moved server-side:
  /// pull the orders (and the unread badge) straight away instead of waiting
  /// for the next poll.
  void _handlePushMessage() {
    if (!mounted) return;
    _refreshActiveOrders();
    _pollNotifications(canNotify: true);
  }

  Future<void> _pollNotifications({required bool canNotify}) async {
    if (_isPollingNotifications) return;
    _isPollingNotifications = true;

    try {
      final response = await ApiService.fetchCustomerNotifications(
        limit: 1,
        unreadOnly: true,
      );
      if (!mounted) return;

      final CustomerNotification? latest = response.notifications.isEmpty
          ? null
          : response.notifications.first;
      final isNew =
          _notificationsBaselineSeeded &&
          latest != null &&
          latest.id != _latestUnreadNotificationId;

      _notificationsBaselineSeeded = true;
      _latestUnreadNotificationId = latest?.id;

      if (response.unreadCount != unreadNotificationCount) {
        setState(() => unreadNotificationCount = response.unreadCount);
      }

      // A fresh notification is the signal that an order moved on: re-fetch so
      // Home's live-order card follows it without waiting to be reopened.
      if (isNew && latest.orderId != null) {
        unawaited(_refreshActiveOrders());
      }

      if (isNew && canNotify) {
        showAppToast(
          context,
          type: latest.orderId != null ? AppToastType.order : AppToastType.info,
          title: latest.title,
          message: latest.body,
          actionText: 'View',
          onAction: () {
            if (mounted) openNotifications();
          },
        );
      }
    } catch (_) {
      // Best-effort polling: never surface errors from the background check.
    } finally {
      _isPollingNotifications = false;
    }
  }

  void _handleUnreadCountChanged(int count) {
    if (!mounted || count == unreadNotificationCount) return;
    setState(() => unreadNotificationCount = count);
  }

  void openNotifications() {
    hideAppToast();
    Navigator.of(context).push(
      MaterialPageRoute(
        builder: (_) => CustomerNotificationsScreen(
          onUnreadCountChanged: _handleUnreadCountChanged,
        ),
      ),
    );
  }

  /// Everything the orders drive on screen — the live-order card, the
  /// "Order It Again" rail, the active-orders shortcut — in one comparable
  /// string, so a poll that changed nothing costs no rebuild.
  static String _ordersSignature(List<ProfileOrder> orders) => orders
      .map(
        (order) => [
          order.id,
          order.status,
          order.paymentStatus,
          order.updatedAt ?? '',
          order.displayFulfillmentAt ?? '',
        ].join('|'),
      )
      .join(';');

  /// Best-effort refresh of the active-orders count that drives the top-bar
  /// shortcut. Active orders are paid but not yet completed; there is no
  /// dedicated endpoint, so we derive the count from the orders list.
  Future<void> _refreshActiveOrders() async {
    if (_isRefreshingActiveOrders) return;
    _isRefreshingActiveOrders = true;

    try {
      final response = await ApiService.fetchCustomerOrders(limit: 100);
      if (!mounted) return;

      final count = response.orders.where((order) => order.isActive).length;

      // Polled every few seconds while an order is live, so only rebuild when
      // the orders actually moved.
      final signature = _ordersSignature(response.orders);
      if (signature == _lastOrdersSignature) return;
      _lastOrdersSignature = signature;

      setState(() {
        customerOrders = response.orders;
        activeOrdersCount = count;
      });
    } catch (_) {
      // Never surface errors from this background refresh.
    } finally {
      _isRefreshingActiveOrders = false;
    }
  }

  void openActiveOrders() {
    Navigator.of(context)
        .push(MaterialPageRoute(builder: (_) => const ActiveOrdersScreen()))
        // The set of active orders may have changed while the screen was open.
        .then((_) => _refreshActiveOrders());
  }

  void openOrderHistory() {
    Navigator.of(context)
        .push(MaterialPageRoute(builder: (_) => const CustomerOrdersScreen()))
        .then((_) => _refreshActiveOrders());
  }

  /// Opens one order's detail screen from the tab it was tapped in. Home's
  /// live-order card comes through here, so "Track order" lands on the order
  /// itself and backing out of it returns to Home — not to a list the
  /// customer never asked for.
  void openOrderDetail(ProfileOrder order) {
    Navigator.of(context)
        .push(
          MaterialPageRoute(
            builder: (_) => OrderDetailScreen(
              orderId: order.id,
              orderNumber: order.orderNumber,
            ),
          ),
        )
        // The order may have moved on (or finished) while it was open.
        .then((_) => _refreshActiveOrders());
  }

  /// Opens a Home category chip in the Shop's category listing. The home
  /// payload and the shop read the same `product_categories` rows, so the id
  /// carried by the chip is enough to page the category.
  void openShopCategory(AppData data, Category category) {
    Navigator.of(context).push(
      MaterialPageRoute(
        builder: (_) => ShopCategoryProductsScreen(
          category: ShopCategory(
            id: category.id,
            name: category.name,
            slug: null,
            imageUrl: null,
            sortOrder: category.sortOrder,
            productCount: 0,
          ),
          locationId: data.selectedLocationId,
          locationName: data.selectedLocationName,
          onCartChanged: handleCartChanged,
          onSwitchTab: (index) {
            Navigator.of(context).popUntil((route) => route.isFirst);
            handleBottomNavTap(index);
          },
          onOpenProduct: (product) =>
              openCocktailDetail(data, Cocktail.fromShopProduct(product)),
        ),
      ),
    );
  }

  /// Loads app data, keeping whatever is already on screen visible while the
  /// request is in flight.
  ///
  /// [reuseStatic] carries the cocktail-finder options over from the current
  /// payload, turning a refresh into a single request. Only a cold start or a
  /// location change needs the full load.
  Future<void> loadAppData({bool reuseStatic = false}) async {
    if (isLoadingAppData) return;
    setState(() => isLoadingAppData = true);

    try {
      final data = await ApiService.fetchAppData(
        previous: reuseStatic ? appData : null,
      );
      if (!mounted) return;

      setState(() {
        appData = data;
        appDataError = null;
      });
    } catch (error) {
      if (!mounted) return;

      // A failed background refresh must not replace a working screen with an
      // error page — only surface it when there is nothing to show.
      setState(() {
        if (appData == null) appDataError = error;
      });
    } finally {
      if (mounted) setState(() => isLoadingAppData = false);
    }
  }

  /// Full reload: use when the underlying catalog may have changed (location
  /// switch, logout).
  void reloadAppData() {
    loadAppData();
  }

  /// The cart changed somewhere in the app.
  ///
  /// Cart writes answer with the new summary, so the badge is updated straight
  /// from that response — no request at all. Callers that only know the cart
  /// moved pass nothing and pay for a refresh of the live data.
  void handleCartChanged([CartSummary? summary]) {
    final data = appData;

    if (summary == null || data == null) {
      loadAppData(reuseStatic: true);
      return;
    }

    setState(() => appData = data.withCartSummary(summary));
  }

  void openCart() {
    setState(() => selectedIndex = EbtlBottomNav.cartIndex);
    AnalyticsService.logScreenView('cart');
  }

  /// The Cocktail Finder no longer has a tab of its own — it is pushed on top
  /// of whatever is showing, most often from the Explore hero.
  void openFinder({String? liquorTypeId}) {
    final cleanLiquorTypeId = liquorTypeId?.trim();

    AnalyticsService.logScreenView('cocktail_finder');

    // Only reachable from screens that render behind loaded app data.
    final data = appData;
    if (data == null) return;

    Navigator.of(context)
        .push(
          MaterialPageRoute(
            builder: (_) => Scaffold(
              backgroundColor: EbtlColors.cream,
              body: FinderScreen(
                data: data,
                initialLiquorTypeId:
                    cleanLiquorTypeId == null || cleanLiquorTypeId.isEmpty
                    ? null
                    : cleanLiquorTypeId,
                onBack: () => Navigator.of(context).pop(),
                onOpenCocktail: (cocktail, liquorTypeId) => openCocktailDetail(
                  data,
                  cocktail,
                  liquorTypeId: liquorTypeId,
                ),
              ),
            ),
          ),
        )
        .then((_) {
          if (!mounted) return;
          AnalyticsService.logScreenView(_screenNames[selectedIndex]);
        });
  }

  static const List<String> _screenNames = [
    'home',
    'explore',
    'cart',
    'profile',
  ];

  void handleBottomNavTap(int index) {
    final safeIndex = index.clamp(0, EbtlBottomNav.tabCount - 1).toInt();

    // Active bottom tabs: 0 Home, 1 Explore, 2 Cart, 3 Profile.
    setState(() => selectedIndex = safeIndex);
    AnalyticsService.logScreenView(_screenNames[safeIndex]);
  }

  Future<void> selectLocation(ServiceLocation location) async {
    await ApiService.saveSelectedLocation(location);
    AnalyticsService.logLocationSelected(location.id);
    reloadAppData();
  }

  Future<void> openCocktailDetail(
    AppData data,
    Cocktail cocktail, {
    String? liquorTypeId,
  }) {
    if (cocktail.slug.trim().isEmpty) {
      showAppSnackBar(context, 'This cocktail is missing a detail link.');
      return Future.value();
    }

    return Navigator.of(context).push(
      MaterialPageRoute(
        builder: (_) => CocktailDetailScreen(
          slug: cocktail.slug,
          locationId: data.selectedLocationId,
          locationName: data.selectedLocationName,
          liquorTypeId: liquorTypeId,
          selectedNavIndex: selectedIndex,
          initialCartQuantity: data.cartSummary?.totalQuantity ?? 0,
          onCartChanged: handleCartChanged,
          onBottomNavTap: (index) {
            // The Finder may also be on the stack, so unwind back to the shell
            // rather than popping a single route.
            Navigator.of(context).popUntil((route) => route.isFirst);
            handleBottomNavTap(index);
          },
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final data = appData;

    if (data == null) {
      final error = appDataError;
      if (error != null) {
        return AppErrorScreen(
          message: apiErrorMessage(error),
          onRetry: reloadAppData,
        );
      }

      return theLoadingScaffold();
    }

    final safeSelectedIndex = selectedIndex
        .clamp(0, EbtlBottomNav.tabCount - 1)
        .toInt();
    visitedTabs.add(safeSelectedIndex);

    // Home resolves its layout from what the customer has in flight: the order
    // still being made, and the finished ones it can offer to repeat.
    final liveOrder = customerOrders.where((order) => order.isActive).firstOrNull;
    final pastOrders = customerOrders
        .where((order) => !order.isActive)
        .toList(growable: false);

    final pages = [
      HomeScreen(
        data: data,
        liveOrder: liveOrder,
        pastOrders: pastOrders,
        unreadNotificationCount: unreadNotificationCount,
        onOpenNotifications: openNotifications,
        onOpenSearch: () => handleBottomNavTap(EbtlBottomNav.exploreIndex),
        onOpenCart: openCart,
        onOpenShop: () => handleBottomNavTap(EbtlBottomNav.exploreIndex),
        onOpenLiveOrder: openOrderDetail,
        onOpenOrderHistory: openOrderHistory,
        onOpenFinder: () => openFinder(),
        onOpenFinderWithBottle: (liquor) => openFinder(liquorTypeId: liquor.id),
        onOpenCocktail: (cocktail) => openCocktailDetail(data, cocktail),
        onOpenCategory: (category) => openShopCategory(data, category),
        onLocationSelected: selectLocation,
        onCartChanged: handleCartChanged,
      ),
      ExploreScreen(
        data: data,
        onCartChanged: handleCartChanged,
        onOpenFinder: () => openFinder(),
        onOpenProduct: (product) =>
            openCocktailDetail(data, Cocktail.fromShopProduct(product)),
        unreadNotificationCount: unreadNotificationCount,
        onOpenNotifications: openNotifications,
        activeOrdersCount: activeOrdersCount,
        onOpenActiveOrders: openActiveOrders,
      ),
      CartScreen(
        data: data,
        // The cart tab stays mounted once opened, so it has to be told when it
        // is the visible tab to refetch a cart that changed while it was in
        // the background.
        isActive: safeSelectedIndex == EbtlBottomNav.cartIndex,
        onOpenFinder: () => openFinder(),
        onGoHome: () => setState(() => selectedIndex = EbtlBottomNav.homeIndex),
        onCartChanged: handleCartChanged,
        onOpenCheckout:
            ({
              required locationId,
              required fulfillmentType,
              required onCartChanged,
            }) {
              Navigator.of(context).push(
                MaterialPageRoute(
                  builder: (_) => CheckoutScreen(
                    locationId: locationId,
                    fulfillmentType: fulfillmentType,
                    onEditCart: () => Navigator.of(context).pop(),
                    onCartChanged: onCartChanged,
                    onOrderCompleted: () {
                      Navigator.of(context).pop();
                      if (!mounted) return;
                      setState(() => selectedIndex = EbtlBottomNav.homeIndex);
                      reloadAppData();
                      _refreshActiveOrders();
                    },
                  ),
                ),
              );
            },
      ),
      ProfileScreen(
        selectedLocationId: data.selectedLocationId,
        unreadNotificationCount: unreadNotificationCount,
        onOpenNotifications: openNotifications,
        onLoggedOut: () {
          setState(() => selectedIndex = EbtlBottomNav.homeIndex);
          reloadAppData();
        },
      ),
    ];

    return Scaffold(
      // IndexedStack keeps every visited tab mounted, so switching tabs shows
      // the screen exactly as it was left instead of remounting it and
      // refetching. Unvisited tabs render as empty placeholders until first
      // opened, so startup cost is unchanged.
      body: IndexedStack(
        index: safeSelectedIndex,
        children: List<Widget>.generate(
          pages.length,
          (index) => visitedTabs.contains(index)
              ? pages[index]
              : const SizedBox.shrink(),
        ),
      ),
      bottomNavigationBar: EbtlBottomNav(
        selectedIndex: safeSelectedIndex,
        onTap: handleBottomNavTap,
        showProfileDot: unreadNotificationCount > 0,
        cartItemCount: data.cartSummary?.totalQuantity ?? 0,
      ),
    );
  }
}
