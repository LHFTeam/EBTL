import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';

import 'shared/widgets/app_state_widgets.dart';

import 'core/theme/ebtl_colors.dart';

/* -------------------------------- MODELS -------------------------------- */
import 'models/common_models.dart';
import 'models/cocktail_models.dart';
import 'models/app_data.dart';

/* -------------------------------- SCREENS -------------------------------- */
import 'features/home/home_screen.dart';
import 'features/finder/finder_screen.dart';
import 'features/shop/shop_screen.dart';
import 'features/cocktail_detail/cocktail_detail_screen.dart';
import 'features/cart/cart_screen.dart';
import 'features/checkout/checkout_screen.dart';
import 'features/profile/profile_screen.dart';

/* -------------------------------- SHARED WIDGETS -------------------------------- */
import 'shared/widgets/ebtl_bottom_nav.dart';

/* --------------------------------- FEATURE WIDGETS --------------------------------- */

/* --------------------------------- SERVICES --------------------------------- */
import 'services/api_service.dart';

void main() {
  WidgetsFlutterBinding.ensureInitialized();
  runApp(const EbtlApp());
}

/*
  EBTL CUSTOMER APP - CUSTOMER API VERSION

  Screens included in this file:
  1. Home
  2. Cocktail Finder
  3. Cart

  Backend customer API namespace:
  - /api/customer/session
  - /api/customer/home
  - /api/customer/cocktail-finder/options
  - /api/customer/cocktails
  - /api/customer/cart
  - /api/customer/cart/items

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
      home: const RootShell(),
    );
  }
}

class RootShell extends StatefulWidget {
  const RootShell({super.key});

  @override
  State<RootShell> createState() => _RootShellState();
}

class _RootShellState extends State<RootShell> {
  int selectedIndex = 0;
  String? finderInitialLiquorTypeId;
  late Future<AppData> appDataFuture;

  @override
  void initState() {
    super.initState();
    appDataFuture = ApiService.fetchAppData();
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
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text('This cocktail is missing a detail link.'),
        ),
      );
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
                      ),
                    ),
                  );
                },
          ),
          ProfileScreen(
            selectedLocationId: data.selectedLocationId,
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
          ),
        );
      },
    );
  }
}
