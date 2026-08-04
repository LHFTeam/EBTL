import 'package:flutter/material.dart';

import '../../core/network/api_exception.dart';
import '../../core/theme/home_screen_visuals.dart';
import '../../models/app_data.dart';
import '../../models/cocktail_models.dart';
import '../../models/common_models.dart';
import '../../models/profile_models.dart';
import '../../services/analytics_service.dart';
import '../../services/api_service.dart';
import '../../shared/widgets/app_state_widgets.dart';
import '../../shared/widgets/bottle_widgets.dart';
import '../../shared/widgets/cocktail_card_widgets.dart';
import '../../shared/widgets/section_block.dart';
import 'widgets/beach_cart_picker_sheet.dart';
import 'widgets/home_context_header.dart';
import 'widgets/home_hero_carousel.dart';
import 'widgets/home_modules.dart';

/// Which of the three Home layouts the customer gets. Resolved from their
/// state on every build — never chosen by hand.
enum HomeMode {
  /// Nothing in flight and nothing behind them: lead with the education
  /// carousel and close on the shop-only path.
  firstRun,

  /// They have shopped before or have a cart open: lead with the cart.
  browsing,

  /// An order is being made right now: lead with the tracker.
  liveOrder,
}

/// The Home tab.
///
/// A context-first stack: a fixed header carrying the beach-cart chip and
/// search, then modules whose order changes with [HomeMode]. The previous
/// hero-banner Home is kept, disconnected, in `legacy_home_screen.dart`.
class HomeScreen extends StatefulWidget {
  final AppData data;

  /// The order currently being made, if any — drives the live-order module and
  /// the [HomeMode.liveOrder] layout.
  final ProfileOrder? liveOrder;

  /// Finished orders, newest first, behind the "Order It Again" rail.
  final List<ProfileOrder> pastOrders;

  final int unreadNotificationCount;
  final VoidCallback onOpenNotifications;
  final VoidCallback onOpenSearch;
  final VoidCallback onOpenCart;
  final VoidCallback onOpenShop;
  final VoidCallback onOpenActiveOrders;
  final VoidCallback onOpenOrderHistory;
  final VoidCallback onOpenFinder;
  final ValueChanged<LiquorType> onOpenFinderWithBottle;
  final ValueChanged<Cocktail> onOpenCocktail;
  final ValueChanged<Category> onOpenCategory;
  final ValueChanged<ServiceLocation> onLocationSelected;
  final CartChangedCallback onCartChanged;

  const HomeScreen({
    super.key,
    required this.data,
    required this.liveOrder,
    required this.pastOrders,
    required this.unreadNotificationCount,
    required this.onOpenNotifications,
    required this.onOpenSearch,
    required this.onOpenCart,
    required this.onOpenShop,
    required this.onOpenActiveOrders,
    required this.onOpenOrderHistory,
    required this.onOpenFinder,
    required this.onOpenFinderWithBottle,
    required this.onOpenCocktail,
    required this.onOpenCategory,
    required this.onLocationSelected,
    required this.onCartChanged,
  });

  @override
  State<HomeScreen> createState() => _HomeScreenState();
}

class _HomeScreenState extends State<HomeScreen> {
  /// How many past orders the "Order It Again" rail offers.
  static const int _orderAgainLimit = 6;

  String? selectedCategoryId;

  /// The order whose "add again" request is in flight, if any.
  String? reorderingOrderId;

  HomeMode get mode {
    if (widget.liveOrder != null) return HomeMode.liveOrder;

    final cartQuantity = widget.data.cartSummary?.totalQuantity ?? 0;
    if (cartQuantity > 0 || widget.pastOrders.isNotEmpty) {
      return HomeMode.browsing;
    }

    return HomeMode.firstRun;
  }

  void showMessage(String message) => showAppSnackBar(context, message);

  Future<void> openLocationPicker() async {
    final location = await showBeachCartPickerSheet(
      context: context,
      serviceAreas: widget.data.serviceAreas,
      selectedLocationId: widget.data.selectedLocationId,
    );

    if (location == null) return;
    widget.onLocationSelected(location);
  }

  void selectCategory(Category category) {
    setState(() => selectedCategoryId = category.id);
    widget.onOpenCategory(category);
  }

  /// Puts a previous order's kit back in the cart.
  ///
  /// The orders payload carries name snapshots rather than product and variant
  /// ids, so the kit is looked up again by its slug and added at the price and
  /// availability of today. Customizations from the original order (removed
  /// ingredients, additions) are not recoverable from the payload and are not
  /// carried over — a `/orders/:id/reorder` endpoint would fix both.
  Future<void> orderAgain(ProfileOrder order) async {
    if (reorderingOrderId != null) return;

    final locationId = widget.data.selectedLocationId?.trim();
    if (locationId == null || locationId.isEmpty) {
      showMessage('Choose a beach cart before adding items.');
      return;
    }

    final slug = order.primaryItem?.slug?.trim();
    if (slug == null || slug.isEmpty) {
      showMessage('Open this order to add it to your cart again.');
      return;
    }

    setState(() => reorderingOrderId = order.id);

    try {
      final detail = await ApiService.fetchCocktailDetail(
        slug: slug,
        locationId: locationId,
      );
      final cocktail = detail.cocktail;
      final variant = cocktail.variant;

      if (variant == null || !cocktail.canAddToCart) {
        if (!mounted) return;
        setState(() => reorderingOrderId = null);
        showMessage(cocktail.availabilityMessage);
        return;
      }

      final quantity = order.primaryItem?.quantity ?? 1;

      final result = await ApiService.addCocktailToCart(
        cocktailId: cocktail.id,
        variantId: variant.id,
        selectedQuantity: quantity,
        locationId: locationId,
      );

      AnalyticsService.logAddToCart(
        AnalyticsItem(
          id: cocktail.id,
          name: cocktail.name,
          category: cocktail.category?.name ?? 'cocktail',
          variant: variant.name,
          price: variant.priceIncVat,
          quantity: quantity,
          currency: variant.currency,
        ),
      );

      if (!mounted) return;

      setState(() => reorderingOrderId = null);
      widget.onCartChanged(result.totals);
      showMessage(result.successMessage);
    } catch (error) {
      if (!mounted) return;

      setState(() => reorderingOrderId = null);
      showMessage(
        apiErrorMessage(
          error,
          fallback: 'Could not add this order to your cart.',
        ),
      );
    }
  }

  @override
  Widget build(BuildContext context) {
    return Column(
      children: [
        HomeContextHeader(
          locationName: widget.data.selectedLocationName,
          onOpenLocationPicker: openLocationPicker,
          unreadNotificationCount: widget.unreadNotificationCount,
          onOpenNotifications: widget.onOpenNotifications,
          onOpenSearch: widget.onOpenSearch,
        ),
        Expanded(
          child: ListView(
            padding: const EdgeInsets.only(top: 18, bottom: 100),
            children: buildModules(),
          ),
        ),
      ],
    );
  }

  /// The scrolling region, in the order this state calls for.
  List<Widget> buildModules() {
    final currentMode = mode;
    final liveOrder = widget.liveOrder;

    return [
      if (liveOrder != null)
        HomeLiveOrderCard(
          order: liveOrder,
          onTap: widget.onOpenActiveOrders,
        ),
      ...buildCartResumeBar(),
      // The carousel stays on Home in every state except a live order, where
      // the tracker is what the customer came back for.
      if (liveOrder == null) ...[
        const HomeHeroCarousel(),
        const SizedBox(height: 10),
      ],
      if (currentMode == HomeMode.liveOrder) ...buildOrderAgain(),
      ...buildBottleRail(),
      ...buildCategoryChips(),
      ...buildFeaturedRail(),
      if (currentMode == HomeMode.firstRun)
        HomeNoBottlePanel(onTap: widget.onOpenShop),
    ];
  }

  List<Widget> buildCartResumeBar() {
    final cart = widget.data.cartSummary;
    if (cart == null || cart.totalQuantity <= 0) return const [];

    return [
      HomeCartResumeBar(
        itemCount: cart.totalQuantity,
        totalLabel: cart.subtotalLabel,
        onTap: widget.onOpenCart,
      ),
    ];
  }

  List<Widget> buildOrderAgain() {
    final orders = widget.pastOrders.take(_orderAgainLimit).toList();
    if (orders.isEmpty) return const [];

    return [
      HomeSectionHeader(
        title: 'Order It Again',
        actionLabel: 'View all',
        onAction: widget.onOpenOrderHistory,
      ),
      SizedBox(
        height: HomeScreenVisuals.orderAgainRailHeight,
        child: ListView.separated(
          scrollDirection: Axis.horizontal,
          padding: const EdgeInsets.fromLTRB(22, 0, 22, 4),
          itemCount: orders.length,
          separatorBuilder: (_, _) => const SizedBox(width: 12),
          itemBuilder: (context, index) {
            final order = orders[index];

            return HomeOrderAgainCard(
              order: order,
              onTap: widget.onOpenOrderHistory,
              onAddAgain: () => orderAgain(order),
              isAdding: reorderingOrderId == order.id,
            );
          },
        ),
      ),
      const SizedBox(height: 26),
    ];
  }

  List<Widget> buildBottleRail() {
    final liquorTypes = widget.data.liquorTypes;
    // No bottles, no section — the header would promise a rail that isn't
    // there.
    if (liquorTypes.isEmpty) return const [];

    return [
      const HomeSectionHeader(
        title: 'Choose Your Bottle',
        subtitle: 'Pick the liquor you already have.',
      ),
      SizedBox(
        height: HomeScreenVisuals.homeLiquorBottleCardHeight,
        child: ListView.separated(
          scrollDirection: Axis.horizontal,
          padding: const EdgeInsets.fromLTRB(22, 0, 22, 4),
          itemCount: liquorTypes.length,
          separatorBuilder: (_, _) => const SizedBox(width: 8),
          itemBuilder: (context, index) {
            final liquor = liquorTypes[index];

            return BottleCard(
              liquor: liquor,
              onTap: () => widget.onOpenFinderWithBottle(liquor),
            );
          },
        ),
      ),
      const SizedBox(height: 26),
    ];
  }

  List<Widget> buildCategoryChips() {
    final categories = widget.data.categories;
    if (categories.isEmpty) return const [];

    return [
      HomeCategoryChips(
        categories: categories,
        selectedCategoryId: selectedCategoryId ?? categories.first.id,
        onSelect: selectCategory,
      ),
      // The featured section below carries 22 of the 26pt module gutter in
      // SectionBlock's own top padding.
      const SizedBox(height: 4),
    ];
  }

  /// The featured rail, carried over unchanged from the previous Home: the
  /// shared [SectionBlock] header over a rail of [CocktailSmallCard]s.
  List<Widget> buildFeaturedRail() {
    final featured = widget.data.featuredCocktails;

    return [
      SectionBlock(
        icon: Icons.local_bar_outlined,
        title: 'Featured Cocktails',
        actionText: 'View all',
        onAction: widget.onOpenFinder,
        child: featured.isEmpty
            ? const EmptyStateCard(
                message: 'No featured cocktails are available right now.',
              )
            : SizedBox(
                height: HomeScreenVisuals.featuredProductCardHeight,
                child: ListView.separated(
                  scrollDirection: Axis.horizontal,
                  padding: const EdgeInsets.only(left: 22, right: 22),
                  itemCount: featured.length,
                  separatorBuilder: (_, _) => const SizedBox(width: 12),
                  itemBuilder: (context, index) {
                    return CocktailSmallCard(
                      cocktail: featured[index],
                      onTap: () => widget.onOpenCocktail(featured[index]),
                    );
                  },
                ),
              ),
      ),
    ];
  }
}
