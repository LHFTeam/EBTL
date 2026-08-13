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
  final OpenCocktailCallback onOpenCocktail;
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

  /// The last catalog that arrived, so a refresh does not blank the page.
  SearchCatalog? lastCatalog;
  late final TextEditingController searchController;
  final FocusNode searchFocusNode = FocusNode();

  /// Anchors the results dropdown to the search field, which scrolls with the
  /// rest of the page here.
  final LayerLink searchFieldLink = LayerLink();

  /// The field and its dropdown, as one thing to tap: a tap anywhere else on
  /// the page puts the keyboard away.
  final SearchTapGroup searchTapGroup = SearchTapGroup();
  Timer? searchDebounce;
  String appliedQuery = '';

  /// Null means the "All" badge is selected.
  String? selectedCategoryId;
  String? addingProductId;

  /// How many products of the selected category the grid is drawing.
  ///
  /// The whole catalog is already in memory, so the grid grows a page at a time
  /// as the customer nears the end of it rather than rendering thousands of
  /// tiles up front — an infinite scroll without a second request.
  static const int _productPageSize = 12;

  /// How close to the bottom the scroll has to get before the next page is
  /// revealed, so more tiles are there before the customer reaches the end.
  static const double _loadMoreExtent = 600;

  int visibleProductCount = _productPageSize;

  /// How many products the selected category holds, as the last build saw it.
  /// The scroll listener has no catalog of its own to check against.
  int loadedProductCount = 0;

  final ScrollController scrollController = ScrollController();

  @override
  void initState() {
    super.initState();
    searchController = TextEditingController(text: widget.searchQuery);
    appliedQuery = widget.searchQuery.trim();
    exploreFuture = loadExplore();
    scrollController.addListener(handleScroll);
  }

  /// Reveals the next page as the end of the grid comes into reach.
  void handleScroll() {
    if (!scrollController.hasClients) return;
    if (visibleProductCount >= loadedProductCount) return;

    final position = scrollController.position;
    if (position.pixels < position.maxScrollExtent - _loadMoreExtent) return;

    setState(() => visibleProductCount += _productPageSize);
  }

  void selectCategory(String? categoryId) {
    setState(() {
      selectedCategoryId = categoryId;
      // A different category is a different list; start it from the top.
      visibleProductCount = _productPageSize;
    });
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
    scrollController.dispose();
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
      visibleProductCount = _productPageSize;
    });
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
          source: AnalyticsSource.explore,
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

  Future<void> openProduct(ShopProduct product) {
    return openCatalogProduct(
      context,
      product: product,
      locationId: widget.data.selectedLocationId,
      onCartChanged: widget.onCartChanged,
      onOpenCocktail: widget.onOpenCocktail,
    );
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

            // A refresh — a pull, a beach-cart change, an add that re-reads
            // availability — replaces the future, which empties the snapshot
            // while the request is out. The catalog already on screen is kept
            // through that, so a browse deep into an infinite scroll is not
            // thrown back to a loading page and the top of the grid.
            final catalog = snapshot.data ?? lastCatalog;

            if (catalog == null) {
              if (snapshot.connectionState == ConnectionState.waiting) {
                return const ShopLoadingState();
              }

              return ListView(
                padding: const EdgeInsets.only(top: 40),
                children: const [
                  EmptyStateCard(message: 'Nothing to explore just yet.'),
                ],
              );
            }

            lastCatalog = catalog;
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
            tapGroup: searchTapGroup,
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
    final products = catalog.productsFor(activeCategoryId);
    // Infinite scroll: the catalog is already in memory, so "loading more" is
    // revealing more of it as the customer reaches the end of what is drawn.
    loadedProductCount = products.length;
    final visibleProducts = products.take(visibleProductCount).toList();
    final hasMore = visibleProducts.length < products.length;

    return CustomScrollView(
      controller: scrollController,
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
              onSelect: selectCategory,
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
        else ...[
          SliverToBoxAdapter(
            child: Padding(
              padding: const EdgeInsets.fromLTRB(22, 22, 22, 14),
              child: ShopGridSectionHeader(
                title:
                    catalog.categoryById(activeCategoryId)?.name ??
                    'All products',
              ),
            ),
          ),
          SliverPadding(
            padding: const EdgeInsets.symmetric(horizontal: 22),
            sliver: SliverGrid.builder(
              itemCount: visibleProducts.length,
              gridDelegate: const SliverGridDelegateWithFixedCrossAxisCount(
                crossAxisCount: 2,
                mainAxisSpacing: 14,
                crossAxisSpacing: 14,
                childAspectRatio: 0.62,
              ),
              itemBuilder: (context, index) {
                final product = visibleProducts[index];

                return ShopCatalogCard(
                  product: product,
                  isAdding: addingProductId == product.id,
                  onTap: () => openProduct(product),
                  onAdd: () => quickAddProduct(product),
                );
              },
            ),
          ),
          if (hasMore)
            const SliverToBoxAdapter(
              child: Padding(
                padding: EdgeInsets.only(top: 20),
                child: EbtlLoadingSection(
                  padding: EdgeInsets.zero,
                  size: 48,
                  showLabel: false,
                ),
              ),
            ),
        ],
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
        tapGroup: searchTapGroup,
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
