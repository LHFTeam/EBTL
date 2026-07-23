import 'dart:async';

import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';

import 'shared/widgets/app_state_widgets.dart';

import 'core/theme/ebtl_colors.dart';

/* -------------------------------- MODELS -------------------------------- */
import 'models/common_models.dart';
import 'models/cocktail_models.dart';
import 'models/app_data.dart';
import 'models/notification_models.dart';

/* -------------------------------- SCREENS -------------------------------- */
import 'features/home/home_screen.dart';
import 'features/finder/finder_screen.dart';
import 'features/shop/shop_screen.dart';
import 'features/cocktail_detail/cocktail_detail_screen.dart';
import 'features/cart/cart_screen.dart';
import 'features/checkout/checkout_screen.dart';
import 'features/profile/profile_screen.dart';
import 'features/profile/customer_notifications_screen.dart';
import 'features/onboarding/onboarding_screen.dart';

/* -------------------------------- SHARED WIDGETS -------------------------------- */
import 'shared/widgets/ebtl_bottom_nav.dart';

/* --------------------------------- SERVICES --------------------------------- */
import 'services/api_service.dart';
import 'services/clarity_service.dart';
import 'services/push_notification_service.dart';

void main() {
  WidgetsFlutterBinding.ensureInitialized();
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

  int selectedIndex = 0;
  String? finderInitialLiquorTypeId;
  late Future<AppData> appDataFuture;

  Timer? _notificationsTimer;
  int unreadNotificationCount = 0;
  String? _latestUnreadNotificationId;
  bool _notificationsBaselineSeeded = false;
  bool _isPollingNotifications = false;

  @override
  void initState() {
    super.initState();
    appDataFuture = ApiService.fetchAppData();
    WidgetsBinding.instance.addObserver(this);
    PushNotificationService.initialize();
    _startNotificationsPolling(notifyImmediately: false);
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    _notificationsTimer?.cancel();
    super.dispose();
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    // Dart timers keep firing while the app is paused, so stop polling in
    // the background and pick it back up (with an immediate check) on resume.
    if (state == AppLifecycleState.resumed) {
      _startNotificationsPolling(notifyImmediately: true);
    } else if (state == AppLifecycleState.paused) {
      _notificationsTimer?.cancel();
      _notificationsTimer = null;
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

      if (isNew && canNotify) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text('${latest.title}: ${latest.body}'),
            action: SnackBarAction(
              label: 'View',
              onPressed: () {
                if (mounted) openNotifications();
              },
            ),
          ),
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
    ScaffoldMessenger.of(context).hideCurrentSnackBar();
    Navigator.of(context).push(
      MaterialPageRoute(
        builder: (_) => CustomerNotificationsScreen(
          onUnreadCountChanged: _handleUnreadCountChanged,
        ),
      ),
    );
  }

  void reloadAppData() {
    setState(() {
      appDataFuture = ApiService.fetchAppData();
    });
  }

  void openCart() {
    setState(() => selectedIndex = 3);
  }

  void openFinder({String? liquorTypeId}) {
    final cleanLiquorTypeId = liquorTypeId?.trim();

    setState(() {
      finderInitialLiquorTypeId =
          cleanLiquorTypeId == null || cleanLiquorTypeId.isEmpty
          ? null
          : cleanLiquorTypeId;
      selectedIndex = 1;
    });
  }

  void handleBottomNavTap(int index) {
    setState(() {
      if (index == 1) {
        finderInitialLiquorTypeId = null;
      }

      // Active bottom tabs:
      // 0 Home, 1 Cocktail Finder, 2 Shop, 3 Cart, 4 Profile.
      selectedIndex = index.clamp(0, 4).toInt();
    });
  }

  Future<void> selectLocation(ServiceLocation location) async {
    await ApiService.saveSelectedLocation(location);
    reloadAppData();
  }

  void openCocktailDetail(
    AppData data,
    Cocktail cocktail, {
    String? liquorTypeId,
  }) {
    if (cocktail.slug.trim().isEmpty) {
      showAppSnackBar(context, 'This cocktail is missing a detail link.');
      return;
    }

    Navigator.of(context).push(
      MaterialPageRoute(
        builder: (_) => CocktailDetailScreen(
          slug: cocktail.slug,
          locationId: data.selectedLocationId,
          locationName: data.selectedLocationName,
          liquorTypeId: liquorTypeId,
          selectedNavIndex: selectedIndex,
          initialCartQuantity: data.cartSummary?.totalQuantity ?? 0,
          onCartChanged: reloadAppData,
          onBottomNavTap: (index) {
            Navigator.of(context).pop();
            handleBottomNavTap(index);
          },
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    return FutureBuilder<AppData>(
      future: appDataFuture,
      builder: (context, snapshot) {
        if (snapshot.connectionState == ConnectionState.waiting) {
          return theLoadingScaffold();
        }

        if (snapshot.hasError) {
          return AppErrorScreen(
            message: snapshot.error.toString(),
            onRetry: reloadAppData,
          );
        }

        if (!snapshot.hasData) {
          return AppErrorScreen(
            message: 'The backend returned no data.',
            onRetry: reloadAppData,
          );
        }

        final data = snapshot.data!;

        final pages = [
          HomeScreen(
            data: data,
            onOpenFinder: () => openFinder(),
            onOpenFinderWithBottle: (liquor) =>
                openFinder(liquorTypeId: liquor.id),
            onOpenCart: openCart,
            onLocationSelected: selectLocation,
            onOpenCocktail: (cocktail) => openCocktailDetail(data, cocktail),
          ),
          FinderScreen(
            data: data,
            initialLiquorTypeId: finderInitialLiquorTypeId,
            onOpenCocktail: (cocktail, liquorTypeId) =>
                openCocktailDetail(data, cocktail, liquorTypeId: liquorTypeId),
          ),
          ShopScreen(
            data: data,
            onOpenCart: openCart,
            onCartChanged: reloadAppData,
            onSwitchTab: (index) => setState(() => selectedIndex = index),
            onOpenProduct: (product) {
              openCocktailDetail(data, Cocktail.fromShopProduct(product));
            },
          ),
          CartScreen(
            data: data,
            onOpenFinder: () => openFinder(),
            onGoHome: () => setState(() => selectedIndex = 0),
            onCartChanged: reloadAppData,
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
                          setState(() => selectedIndex = 0);
                          reloadAppData();
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
              setState(() => selectedIndex = 0);
              reloadAppData();
            },
          ),
        ];

        final safeSelectedIndex = selectedIndex
            .clamp(0, pages.length - 1)
            .toInt();

        return Scaffold(
          body: pages[safeSelectedIndex],
          bottomNavigationBar: EbtlBottomNav(
            selectedIndex: safeSelectedIndex,
            onTap: handleBottomNavTap,
            showProfileDot: unreadNotificationCount > 0,
          ),
        );
      },
    );
  }
}
