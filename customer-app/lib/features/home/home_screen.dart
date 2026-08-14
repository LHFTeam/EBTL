import 'dart:async';

import 'package:flutter/material.dart';

import '../../core/network/api_exception.dart';
import '../../core/theme/home_screen_visuals.dart';
import '../../models/app_data.dart';
import '../../models/cocktail_models.dart';
import '../../models/common_models.dart';
import '../../models/profile_models.dart';
import '../../models/recently_viewed.dart';
import '../../models/shop_models.dart';
import '../../models/spotlight_models.dart';
import '../../services/analytics_service.dart';
import '../../services/api_service.dart';
import '../../shared/widgets/app_state_widgets.dart';
import '../../shared/widgets/bottle_widgets.dart';
import '../../shared/widgets/cocktail_card_widgets.dart';
import '../../shared/widgets/section_block.dart';
import '../search/catalog_search.dart';
import '../search/search_collection_screen.dart';
import '../search/widgets/catalog_search_field.dart';
import '../search/widgets/search_results_panel.dart';
import 'widgets/beach_cart_picker_sheet.dart';
import 'widgets/home_context_header.dart';
import 'widgets/home_hero_carousel.dart';
import 'widgets/home_modules.dart';
import 'widgets/home_spotlight_rail.dart';
import 'widgets/spotlight_markdown_sheet.dart';
import 'widgets/spotlight_sheet.dart';

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

  /// Whether Home is the visible tab. The shell keeps every visited tab
  /// mounted, so this is how Home learns to re-read the "Recently viewed" list
  /// after a product was opened from Explore or from search.
  final bool isActive;

  final int unreadNotificationCount;
  final VoidCallback onOpenNotifications;

  /// The search text, shared with Explore through the shell so a query
  /// survives a tab switch.
  final String searchQuery;
  final ValueChanged<String> onSearchQueryChanged;
  final VoidCallback onOpenCart;
  final VoidCallback onOpenShop;

  /// Opens the live order's own detail screen. The card tracks one order, so
  /// it goes straight there rather than by way of the active-orders list.
  final ValueChanged<ProfileOrder> onOpenLiveOrder;
  final VoidCallback onOpenOrderHistory;
  final VoidCallback onOpenFinder;
  final ValueChanged<LiquorType> onOpenFinderWithBottle;
  final OpenCocktailCallback onOpenCocktail;

  /// Opens a cocktail the screen only knows the slug of — the "Recently
  /// viewed" rail, which is drawn from an on-device snapshot rather than from
  /// a loaded catalog.
  final OpenCocktailBySlugCallback onOpenCocktailBySlug;

  /// Follows a hero banner's deep link. Only called for banners that carry one.
  final ValueChanged<HomeHeroBanner> onOpenHeroBanner;
  final ValueChanged<ServiceLocation> onLocationSelected;
  final CartChangedCallback onCartChanged;

  const HomeScreen({
    super.key,
    required this.data,
    required this.liveOrder,
    required this.pastOrders,
    this.isActive = true,
    required this.unreadNotificationCount,
    required this.onOpenNotifications,
    required this.searchQuery,
    required this.onSearchQueryChanged,
    required this.onOpenCart,
    required this.onOpenShop,
    required this.onOpenLiveOrder,
    required this.onOpenOrderHistory,
    required this.onOpenFinder,
    required this.onOpenFinderWithBottle,
    required this.onOpenCocktail,
    required this.onOpenCocktailBySlug,
    required this.onOpenHeroBanner,
    required this.onLocationSelected,
    required this.onCartChanged,
  });

  @override
  State<HomeScreen> createState() => _HomeScreenState();
}

class _HomeScreenState extends State<HomeScreen> {
  /// How many past orders the "Order It Again" rail offers.
  static const int _orderAgainLimit = 6;

  /// The order whose "add again" request is in flight, if any.
  String? reorderingOrderId;

  /// The recently-viewed product whose add-to-cart request is in flight, keyed
  /// by slug — the only id the on-device snapshot carries.
  String? addingRecentSlug;

  /// What the customer opened last, newest first, as stored on-device.
  List<RecentlyViewedProduct> recentlyViewed = const [];

  late final TextEditingController searchController;
  final FocusNode searchFocusNode = FocusNode();

  /// Anchors the results dropdown to the search field in the header.
  final LayerLink searchFieldLink = LayerLink();

  /// The field and its dropdown, as one thing to tap: a tap anywhere else on
  /// the page puts the keyboard away.
  final SearchTapGroup searchTapGroup = SearchTapGroup();
  Timer? searchDebounce;

  /// The query the results below the header are showing. Empty means Home is
  /// showing its modules instead.
  String appliedQuery = '';

  /// The catalog the query is matched against. It is only fetched once the
  /// customer actually searches — Home itself does not need it, and paging
  /// every category is not something startup should pay for.
  Future<SearchCatalog>? catalogFuture;

  /// The same catalog once it has arrived, so the keyboard's search key can
  /// act on it without waiting on the future again.
  SearchCatalog? loadedCatalog;

  @override
  void initState() {
    super.initState();
    searchController = TextEditingController(text: widget.searchQuery);
    appliedQuery = widget.searchQuery.trim();
    if (appliedQuery.isNotEmpty) ensureCatalog();
    refreshRecentlyViewed();
  }

  /// Re-reads the on-device "Recently viewed" list. Cheap — no network — so it
  /// runs whenever a product screen this tab opened comes back.
  Future<void> refreshRecentlyViewed() async {
    final products = await ApiService.loadRecentlyViewed();
    if (!mounted) return;

    setState(() => recentlyViewed = products);
  }

  @override
  void didUpdateWidget(covariant HomeScreen oldWidget) {
    super.didUpdateWidget(oldWidget);

    // Coming back to Home: a cocktail opened from another tab belongs on the
    // rail. Only on the transition — this runs on every shell rebuild.
    if (widget.isActive && !oldWidget.isActive) {
      refreshRecentlyViewed();
    }

    // A beach cart carries its own prices and availability, so the catalog is
    // re-fetched rather than reused across carts.
    if (oldWidget.data.selectedLocationId != widget.data.selectedLocationId &&
        catalogFuture != null) {
      loadCatalog();
    }

    // The query is shell state shared with Explore; a search typed there is
    // already applied by the time Home is looked at again.
    if (widget.searchQuery.trim() != searchController.text.trim()) {
      searchDebounce?.cancel();
      searchController.text = widget.searchQuery;
      appliedQuery = widget.searchQuery.trim();
      if (appliedQuery.isNotEmpty) ensureCatalog();
    }
  }

  @override
  void dispose() {
    searchDebounce?.cancel();
    searchController.dispose();
    searchFocusNode.dispose();
    super.dispose();
  }

  /// Fetches the catalog the first time a search needs it.
  void ensureCatalog() {
    catalogFuture ??= fetchCatalog();
  }

  /// Fetches it again — after a beach-cart change, or a retry.
  void loadCatalog() {
    catalogFuture = fetchCatalog();
  }

  Future<SearchCatalog> fetchCatalog() async {
    loadedCatalog = null;
    final catalog = await SearchCatalog.load(
      locationId: widget.data.selectedLocationId,
    );

    loadedCatalog = catalog;
    return catalog;
  }

  /// Debounced so a fast typist searches once, not once per keystroke — the
  /// same 250ms Explore uses.
  void updateSearch(String value) {
    widget.onSearchQueryChanged(value);
    if (value.trim().isNotEmpty) ensureCatalog();

    searchDebounce?.cancel();
    searchDebounce = Timer(const Duration(milliseconds: 250), () {
      if (!mounted) return;
      setState(() => appliedQuery = value.trim());
      AnalyticsService.logSearch(
        surface: 'home',
        hasQuery: value.trim().isNotEmpty,
      );
    });
  }

  void clearSearch() {
    searchDebounce?.cancel();
    searchController.clear();
    widget.onSearchQueryChanged('');
    setState(() => appliedQuery = '');
    searchFocusNode.requestFocus();
  }

  /// The keyboard's search key opens everything the query matched as its own
  /// screen. With nothing behind it — no catalog yet, or no products — it just
  /// puts the keyboard away and leaves the dropdown up.
  void submitSearch(String value) {
    final query = value.trim();
    final products = query.isEmpty
        ? const <ShopProduct>[]
        : loadedCatalog?.search(query).products ?? const <ShopProduct>[];

    searchFocusNode.unfocus();
    if (products.isEmpty) return;

    openSearchCollection(query, products);
  }

  Future<void> openSearchProduct(ShopProduct product) async {
    await openCatalogProduct(
      context,
      product: product,
      locationId: widget.data.selectedLocationId,
      onCartChanged: widget.onCartChanged,
      onOpenCocktail: widget.onOpenCocktail,
    );

    if (!mounted) return;
    await refreshRecentlyViewed();
  }

  void openSearchCollection(String title, List<ShopProduct> products) {
    Navigator.of(context).push(
      MaterialPageRoute(
        builder: (_) => SearchCollectionScreen(
          title: title,
          products: products,
          onOpenProduct: openSearchProduct,
        ),
      ),
    );
  }

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
          source: AnalyticsSource.orderAgain,
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
          searchController: searchController,
          searchFocusNode: searchFocusNode,
          searchFieldLink: searchFieldLink,
          searchTapGroup: searchTapGroup,
          onSearchChanged: updateSearch,
          onSubmitSearch: submitSearch,
          onClearSearch: clearSearch,
        ),
        // The modules stay put while a search is typed — the results hang off
        // the field, over them, rather than taking their place.
        Expanded(
          child: Stack(
            children: [
              ListView(
                padding: const EdgeInsets.only(top: 18, bottom: 100),
                children: buildModules(),
              ),
              if (appliedQuery.isNotEmpty)
                SearchResultsDropdown(
                  link: searchFieldLink,
                  tapGroup: searchTapGroup,
                  child: buildSearchResults(),
                ),
            ],
          ),
        ),
      ],
    );
  }

  /// What hangs under the field while a query is applied: the same results
  /// Explore shows, from the same catalog, plus the states of fetching it.
  Widget buildSearchResults() {
    return FutureBuilder<SearchCatalog>(
      future: catalogFuture,
      builder: (context, snapshot) {
        if (snapshot.connectionState == ConnectionState.waiting) {
          return const SearchDropdownCard(
            child: EbtlLoadingSection(
              padding: EdgeInsets.symmetric(vertical: 18),
              size: 56,
              showLabel: false,
            ),
          );
        }

        if (snapshot.hasError) {
          return SearchDropdownCard(
            child: SearchDropdownMessage(
              message: apiErrorMessage(snapshot.error!),
              actionLabel: 'Try again',
              onAction: () => setState(loadCatalog),
            ),
          );
        }

        final catalog = snapshot.data;
        if (catalog == null) {
          return const SearchDropdownCard(
            child: SearchDropdownMessage(
              message: 'No matches found. Try a different search.',
            ),
          );
        }

        return SearchResultsPanel(
          catalog: catalog,
          results: catalog.search(appliedQuery),
          onOpenProduct: openSearchProduct,
          onOpenCollection: openSearchCollection,
        );
      },
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
          onTap: () => widget.onOpenLiveOrder(liveOrder),
        ),
      ...buildCartResumeBar(),
      // The carousel stays on Home in every state except a live order, where
      // the tracker is what the customer came back for.
      if (liveOrder == null) ...[
        HomeHeroCarousel(
          banners: widget.data.heroBanners,
          rotationInterval: widget.data.heroRotation,
          onOpenBanner: widget.onOpenHeroBanner,
        ),
        const SizedBox(height: 10),
      ],
      if (currentMode == HomeMode.liveOrder) ...buildOrderAgain(),
      ...buildSpotlight(),
      ...buildRecentlyViewed(),
      ...buildBottleRail(),
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

  /// The Spotlight rail. No banners, no section — unlike the hero carousel there
  /// is nothing bundled to fall back to.
  List<Widget> buildSpotlight() {
    final banners = widget.data.spotlightBanners;
    if (banners.isEmpty) return const [];

    return [
      const HomeSectionHeader(title: 'The Spotlight'),
      HomeSpotlightRail(banners: banners, onOpenBanner: openSpotlightBanner),
      const SizedBox(height: 26),
    ];
  }

  /// A markdown-slide banner opens its own read-only slide; every other
  /// banner keeps opening the curated product grid, same as before this
  /// destination existed.
  void openSpotlightBanner(SpotlightBanner banner) {
    AnalyticsService.logPromotionSelected(
      promotionId: banner.id,
      promotionName: banner.title,
      slot: AnalyticsPromotionSlot.spotlightRail,
      destination: banner.isMarkdownSlide ? 'markdown' : 'products',
    );

    if (banner.isMarkdownSlide) {
      showSpotlightMarkdownSheet(context: context, banner: banner);
      return;
    }

    showSpotlightSheet(
      context: context,
      banner: banner,
      locationId: widget.data.selectedLocationId,
      onCartChanged: widget.onCartChanged,
      onOpenCocktail: (product) => widget.onOpenCocktail(
        Cocktail.fromShopProduct(product),
        source: AnalyticsSource.spotlight,
        sourceDetail: banner.title,
      ),
    );
  }

  /// The "Recently viewed" rail, moved here from Explore so it sits directly
  /// under the Spotlight.
  ///
  /// Only cocktails are offered: a card opens its product again, and the
  /// cocktail detail screen loads from a slug alone, while the sheet the other
  /// shop products use is built from a catalog entry Home does not hold.
  List<Widget> buildRecentlyViewed() {
    final recents = recentlyViewed
        .where((product) => product.isCocktail)
        .toList(growable: false);

    if (recents.isEmpty) return const [];

    return [
      const HomeSectionHeader(title: 'Recently viewed'),
      SizedBox(
        height: HomeScreenVisuals.recentlyViewedRailHeight,
        child: ListView.separated(
          scrollDirection: Axis.horizontal,
          padding: const EdgeInsets.fromLTRB(22, 0, 22, 4),
          itemCount: recents.length,
          separatorBuilder: (_, _) => const SizedBox(width: 12),
          itemBuilder: (context, index) {
            final product = recents[index];

            return HomeRecentlyViewedCard(
              product: product,
              onTap: () => openRecentlyViewed(product),
              onAdd: () => addRecentlyViewedToCart(product),
              isAdding: addingRecentSlug == product.slug,
            );
          },
        ),
      ),
      const SizedBox(height: 26),
    ];
  }

  Future<void> openRecentlyViewed(RecentlyViewedProduct product) async {
    await widget.onOpenCocktailBySlug(
      product.slug,
      source: AnalyticsSource.recentlyViewed,
    );
    if (!mounted) return;
    await refreshRecentlyViewed();
  }

  /// Puts a recently-viewed cocktail back in the cart from the rail itself.
  ///
  /// The snapshot is display-only — no product id, no variant, no availability
  /// — so the cocktail is looked up again by slug and added at today's price and
  /// availability, the same way [orderAgain] does it. Customizations are not
  /// offered here; the card's tap target opens the detail screen for those.
  Future<void> addRecentlyViewedToCart(RecentlyViewedProduct product) async {
    if (addingRecentSlug != null) return;

    final locationId = widget.data.selectedLocationId?.trim();
    if (locationId == null || locationId.isEmpty) {
      showMessage('Choose a beach cart before adding items.');
      return;
    }

    setState(() => addingRecentSlug = product.slug);

    try {
      final detail = await ApiService.fetchCocktailDetail(
        slug: product.slug,
        locationId: locationId,
      );
      final cocktail = detail.cocktail;
      final variant = cocktail.variant;

      if (variant == null || !cocktail.canAddToCart) {
        if (!mounted) return;
        setState(() => addingRecentSlug = null);
        showMessage(cocktail.availabilityMessage);
        return;
      }

      final result = await ApiService.addCocktailToCart(
        cocktailId: cocktail.id,
        variantId: variant.id,
        selectedQuantity: 1,
        locationId: locationId,
      );

      AnalyticsService.logAddToCart(
        AnalyticsItem(
          id: cocktail.id,
          name: cocktail.name,
          category: cocktail.category?.name ?? 'cocktail',
          variant: variant.name,
          price: variant.priceIncVat,
          quantity: 1,
          currency: variant.currency,
        ),
      );

      if (!mounted) return;

      setState(() => addingRecentSlug = null);
      widget.onCartChanged(result.totals);
      showMessage(result.successMessage);
    } catch (error) {
      if (!mounted) return;

      setState(() => addingRecentSlug = null);
      showMessage(
        apiErrorMessage(
          error,
          fallback: 'Could not add this item to your cart.',
        ),
      );
    }
  }

  Future<void> openFeaturedCocktail(Cocktail cocktail) async {
    await widget.onOpenCocktail(cocktail, source: AnalyticsSource.home);
    if (!mounted) return;
    await refreshRecentlyViewed();
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
      Padding(
        padding: const EdgeInsets.fromLTRB(22, 0, 22, 4),
        // A fixed 3-column grid, laid out inside the vertical page scroll, so
        // every bottle is visible at once instead of tucked into a carousel.
        // The cards keep the delivered `liquorTypes` order — grid children fill
        // row by row, top to bottom, the same order the carousel iterated.
        child: GridView.count(
          crossAxisCount: 3,
          shrinkWrap: true,
          physics: const NeverScrollableScrollPhysics(),
          padding: EdgeInsets.zero,
          crossAxisSpacing: 10,
          mainAxisSpacing: 10,
          childAspectRatio: HomeScreenVisuals.homeLiquorBottleCardAspectRatio,
          children: [
            for (final liquor in liquorTypes)
              BottleCard(
                liquor: liquor,
                onTap: () => widget.onOpenFinderWithBottle(liquor),
              ),
          ],
        ),
      ),
      const SizedBox(height: 26),
    ];
  }

  /// The featured rail, carried over unchanged from the previous Home: the
  /// shared [SectionBlock] header over a rail of [CocktailSmallCard]s.
  List<Widget> buildFeaturedRail() {
    final featured = widget.data.featuredCocktails;

    return [
      SectionBlock(
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
                      onTap: () => openFeaturedCocktail(featured[index]),
                    );
                  },
                ),
              ),
      ),
    ];
  }
}
