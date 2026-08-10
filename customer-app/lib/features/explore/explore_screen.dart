import 'dart:async';

import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';

import '../../core/network/api_exception.dart';
import '../../core/theme/ebtl_colors.dart';
import '../../models/app_data.dart';
import '../../models/cocktail_models.dart';
import '../../models/common_models.dart';
import '../../models/product_models.dart';
import '../../models/shop_models.dart';
import '../../services/analytics_service.dart';
import '../../services/api_service.dart';
import '../../shared/widgets/app_state_widgets.dart';
import '../../shared/widgets/brand_widgets.dart';
import '../../shared/widgets/section_block.dart';
import '../search/catalog_search.dart';
import '../search/search_collection_screen.dart';
import '../search/widgets/catalog_search_field.dart';
import '../search/widgets/search_results_panel.dart';
import '../shop/widgets/shop_loading_state.dart';
import '../shop/widgets/shop_product_widgets.dart';
import 'widgets/explore_category_badges.dart';
import 'widgets/explore_hero_banner.dart';

/// The Explore tab — a single browse surface that replaced the separate Shop
/// and Cocktail Finder tabs. The Finder is still reachable through the hero.
class ExploreScreen extends StatefulWidget {
  final AppData data;
  final CartChangedCallback onCartChanged;
  final VoidCallback onOpenFinder;
  final Future<void> Function(Cocktail cocktail) onOpenCocktail;
  final int unreadNotificationCount;
  final VoidCallback onOpenNotifications;
  final int activeOrdersCount;
  final VoidCallback onOpenActiveOrders;
  final String searchQuery;
  final ValueChanged<String> onSearchQueryChanged;
  final VoidCallback onSearchCollectionClosed;

  const ExploreScreen({
    super.key,
    required this.data,
    required this.onCartChanged,
    required this.onOpenFinder,
    required this.onOpenCocktail,
    required this.unreadNotificationCount,
    required this.onOpenNotifications,
    required this.activeOrdersCount,
    required this.onOpenActiveOrders,
    required this.searchQuery,
    required this.onSearchQueryChanged,
    required this.onSearchCollectionClosed,
  });

  @override
  State<ExploreScreen> createState() => _ExploreScreenState();
}

class _ExploreScreenState extends State<ExploreScreen> {
  late Future<SearchCatalog> exploreFuture;
  late final TextEditingController searchController;
  final FocusNode searchFocusNode = FocusNode();

  /// Anchors the results dropdown to the search field, which scrolls with the
  /// rest of the page here.
  final LayerLink searchFieldLink = LayerLink();
  Timer? searchDebounce;
  String appliedQuery = '';

  /// Null means the "All" badge is selected.
  String? selectedCategoryId;
  List<String> recentlyViewedSlugs = const [];
  String? addingProductId;

  @override
  void initState() {
    super.initState();
    searchController = TextEditingController(text: widget.searchQuery);
    appliedQuery = widget.searchQuery.trim();
    exploreFuture = loadExplore();
    refreshRecentlyViewed();
  }

  @override
  void didUpdateWidget(covariant ExploreScreen oldWidget) {
    super.didUpdateWidget(oldWidget);

    if (oldWidget.data.selectedLocationId != widget.data.selectedLocationId) {
      exploreFuture = loadExplore();
    }
    // The query is shell state shared with Home, so a search typed there is
    // already applied by the time this tab is opened.
    if (widget.searchQuery.trim() != searchController.text.trim()) {
      searchDebounce?.cancel();
      searchController.text = widget.searchQuery;
      appliedQuery = widget.searchQuery.trim();
    }
  }

  @override
  void dispose() {
    searchDebounce?.cancel();
    searchController.dispose();
    searchFocusNode.dispose();
    super.dispose();
  }

  void updateSearch(String value) {
    widget.onSearchQueryChanged(value);
    searchDebounce?.cancel();
    searchDebounce = Timer(const Duration(milliseconds: 250), () {
      if (!mounted) return;
      setState(() => appliedQuery = value.trim());
      AnalyticsService.logSearch(
        surface: 'explore',
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
  /// screen. With no products behind it there is nothing to open, so it just
  /// puts the keyboard away and leaves the dropdown up.
  void submitSearch(SearchCatalog catalog) {
    final query = searchController.text.trim();
    final products = query.isEmpty
        ? const <ShopProduct>[]
        : catalog.search(query).products;

    searchFocusNode.unfocus();
    if (products.isEmpty) return;

    openSearchCollection(title: query, products: products);
  }

  /// The whole catalog: what the badges filter locally, and what the search
  /// field matches against.
  Future<SearchCatalog> loadExplore() {
    return SearchCatalog.load(locationId: widget.data.selectedLocationId);
  }

  Future<void> refreshExplore() async {
    final catalog = await loadExplore();
    if (!mounted) return;

    setState(() {
      exploreFuture = Future.value(catalog);
    });

    await refreshRecentlyViewed();
  }

  Future<void> refreshRecentlyViewed() async {
    final slugs = await ApiService.loadRecentlyViewedSlugs();
    if (!mounted) return;

    setState(() => recentlyViewedSlugs = slugs);
  }

  /// Resolves stored slugs against the loaded catalog, newest first. Anything
  /// no longer in the catalog silently drops out.
  List<ShopProduct> recentlyViewedProducts(SearchCatalog catalog) {
    final bySlug = <String, ShopProduct>{};

    for (final product in catalog.allProducts) {
      final slug = product.slug.trim();
      if (slug.isNotEmpty) {
        bySlug[slug] = product;
      }
    }

    final resolved = <ShopProduct>[];

    for (final slug in recentlyViewedSlugs) {
      final product = bySlug[slug];
      if (product != null) {
        resolved.add(product);
      }
    }

    return resolved;
  }

  void showMessage(String message) {
    showAppSnackBar(context, message);
  }

  ProductVariant? orderableVariantFor(ShopProduct product) {
    final firstOrderableVariant = product.firstOrderableVariant;

    if (firstOrderableVariant != null) {
      return firstOrderableVariant;
    }

    if (!product.availability.isOrderable) {
      return null;
    }

    for (final variant in product.variants) {
      if (variant.isActive) {
        return variant;
      }
    }

    return null;
  }

  Future<void> quickAddProduct(ShopProduct product) async {
    final locationId = widget.data.selectedLocationId?.trim();
    if (locationId == null || locationId.isEmpty) {
      showMessage('Choose a beach cart before adding items.');
      return;
    }

    if (!product.availability.isOrderable) {
      showMessage(product.unavailableReason);
      return;
    }

    final variant = orderableVariantFor(product);
    if (variant == null) {
      showMessage(product.unavailableReason);
      return;
    }

    if (addingProductId != null) return;

    setState(() => addingProductId = product.id);

    try {
      final result = await ApiService.addShopProductToCart(
        productId: product.id,
        variantId: variant.id,
        quantity: 1,
        locationId: locationId,
      );

      AnalyticsService.logAddToCart(
        AnalyticsItem(
          id: product.id,
          name: product.name,
          category: product.category?.name ?? product.productType,
          variant: variant.name,
          price: variant.priceIncVat,
          quantity: 1,
          currency: variant.currency,
        ),
      );

      if (!mounted) return;

      showMessage(result.successMessage);
      widget.onCartChanged(result.totals);

      setState(() {
        addingProductId = null;
        exploreFuture = loadExplore();
      });
    } catch (error) {
      if (!mounted) return;

      setState(() => addingProductId = null);

      showMessage(
        apiErrorMessage(
          error,
          fallback: 'Could not add this item to your cart.',
        ),
      );
    }
  }

  Future<void> openProduct(ShopProduct product) async {
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

  @override
  Widget build(BuildContext context) {
    return SafeArea(
      child: RefreshIndicator(
        color: EbtlColors.coral,
        onRefresh: refreshExplore,
        child: FutureBuilder<SearchCatalog>(
          future: exploreFuture,
          builder: (context, snapshot) {
            if (snapshot.connectionState == ConnectionState.waiting) {
              return const ShopLoadingState();
            }

            if (snapshot.hasError) {
              return ListView(
                padding: const EdgeInsets.only(top: 40),
                children: [
                  InlineErrorCard(
                    message: apiErrorMessage(snapshot.error!),
                    onRetry: () =>
                        setState(() => exploreFuture = loadExplore()),
                  ),
                ],
              );
            }

            final catalog = snapshot.data;
            if (catalog == null) {
              return ListView(
                padding: const EdgeInsets.only(top: 40),
                children: const [
                  EmptyStateCard(message: 'Nothing to explore just yet.'),
                ],
              );
            }

            return buildContent(catalog);
          },
        ),
      ),
    );
  }

  /// The browse content, with the results dropdown floating over it while a
  /// query is applied — typing narrows what the dropdown offers, it does not
  /// take the page away.
  Widget buildContent(SearchCatalog catalog) {
    return Stack(
      children: [
        buildBrowse(catalog),
        if (appliedQuery.isNotEmpty)
          SearchResultsDropdown(
            link: searchFieldLink,
            child: SearchResultsPanel(
              catalog: catalog,
              results: catalog.search(appliedQuery),
              onOpenProduct: openProduct,
              onOpenCollection: (title, products) =>
                  openSearchCollection(title: title, products: products),
            ),
          ),
      ],
    );
  }

  Widget buildBrowse(SearchCatalog catalog) {
    // A category can disappear between reloads; fall back to "All".
    final activeCategoryId = catalog.categoryById(selectedCategoryId)?.id;
    final visibleProducts = catalog.productsFor(activeCategoryId);
    final recents = recentlyViewedProducts(catalog);

    return CustomScrollView(
      slivers: [
        SliverToBoxAdapter(
          child: ExploreHeader(
            unreadNotificationCount: widget.unreadNotificationCount,
            onOpenNotifications: widget.onOpenNotifications,
            activeOrdersCount: widget.activeOrdersCount,
            onOpenActiveOrders: widget.onOpenActiveOrders,
          ),
        ),
        SliverToBoxAdapter(child: buildSearchField(catalog)),
        SliverToBoxAdapter(
          child: ExploreHeroBanner(onTap: widget.onOpenFinder),
        ),
        if (recents.isNotEmpty)
          SliverToBoxAdapter(
            child: SectionBlock(
              icon: Icons.history,
              title: 'Recently viewed',
              child: SizedBox(
                height: ShopProductCardTile.heightFor(
                  compact: false,
                  subtitleMaxLines: 2,
                ),
                child: ListView.separated(
                  scrollDirection: Axis.horizontal,
                  padding: const EdgeInsets.symmetric(horizontal: 22),
                  itemCount: recents.length,
                  separatorBuilder: (_, _) => const SizedBox(width: 12),
                  itemBuilder: (context, index) {
                    final product = recents[index];

                    return ShopProductCardTile(
                      product: product,
                      width: 128,
                      compact: false,
                      isAdding: false,
                      subtitleOverride: product.shortDescription,
                      subtitleMaxLines: 2,
                      onTap: () => openProduct(product),
                      onAdd: null,
                    );
                  },
                ),
              ),
            ),
          ),
        SliverToBoxAdapter(
          child: SectionBlock(
            icon: Icons.grid_view_rounded,
            title: 'Browse',
            child: ExploreCategoryBadges(
              categories: catalog.categories,
              productCounts: {
                for (final entry in catalog.productsByCategory.entries)
                  entry.key: entry.value.length,
              },
              selectedCategoryId: activeCategoryId,
              totalProductCount: catalog.allProducts.length,
              onSelect: (categoryId) =>
                  setState(() => selectedCategoryId = categoryId),
            ),
          ),
        ),
        if (visibleProducts.isEmpty)
          const SliverToBoxAdapter(
            child: Padding(
              padding: EdgeInsets.only(top: 22),
              child: EmptyStateCard(
                message: 'No products here yet. Try another category.',
              ),
            ),
          )
        else
          SliverToBoxAdapter(
            child: Padding(
              padding: const EdgeInsets.only(top: 22),
              child: ShopProductGridSection(
                title:
                    catalog.categoryById(activeCategoryId)?.name ??
                    'All products',
                items: visibleProducts,
                initialVisibleCount: 12,
                addingProductId: addingProductId,
                onProductTap: openProduct,
                onQuickAdd: quickAddProduct,
              ),
            ),
          ),
        const SliverToBoxAdapter(child: SizedBox(height: 24)),
      ],
    );
  }

  Widget buildSearchField(SearchCatalog catalog) {
    return Padding(
      padding: const EdgeInsets.fromLTRB(22, 12, 22, 10),
      child: CatalogSearchField(
        controller: searchController,
        focusNode: searchFocusNode,
        layerLink: searchFieldLink,
        onChanged: updateSearch,
        onSubmitted: (_) => submitSearch(catalog),
        onClear: clearSearch,
      ),
    );
  }

  Future<void> openSearchCollection({
    required String title,
    required List<ShopProduct> products,
  }) async {
    await Navigator.of(context).push(
      MaterialPageRoute(
        builder: (_) => SearchCollectionScreen(
          title: title,
          products: products,
          onOpenProduct: openProduct,
        ),
      ),
    );
    if (!mounted) return;
    widget.onSearchCollectionClosed();
  }
}

class ExploreHeader extends StatelessWidget {
  final int unreadNotificationCount;
  final VoidCallback onOpenNotifications;
  final int activeOrdersCount;
  final VoidCallback onOpenActiveOrders;

  const ExploreHeader({
    super.key,
    required this.unreadNotificationCount,
    required this.onOpenNotifications,
    required this.activeOrdersCount,
    required this.onOpenActiveOrders,
  });

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.fromLTRB(22, 14, 22, 4),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  'Explore',
                  style: GoogleFonts.playfairDisplay(
                    fontSize: 42,
                    height: 1.0,
                    fontWeight: FontWeight.w800,
                    color: EbtlColors.navy,
                  ),
                ),
                const SizedBox(height: 9),
                Text(
                  'Cocktails, snacks and everything',
                  style: GoogleFonts.manrope(
                    fontSize: 15,
                    height: 1.25,
                    fontWeight: FontWeight.w700,
                    color: EbtlColors.navy,
                    letterSpacing: 0.4,
                  ),
                ),
                Text(
                  'in between.',
                  style: GoogleFonts.playfairDisplay(
                    fontSize: 18,
                    height: 1.18,
                    fontWeight: FontWeight.w700,
                    fontStyle: FontStyle.italic,
                    color: EbtlColors.coral,
                  ),
                ),
              ],
            ),
          ),
          if (activeOrdersCount > 0) ...[
            ActiveOrdersIconButton(
              count: activeOrdersCount,
              onTap: onOpenActiveOrders,
            ),
            const SizedBox(width: 10),
          ],
          NotificationsIconButton(
            unreadCount: unreadNotificationCount,
            onTap: onOpenNotifications,
          ),
        ],
      ),
    );
  }
}
