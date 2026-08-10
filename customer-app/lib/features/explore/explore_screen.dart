import 'dart:async';

import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';

import '../../core/network/api_exception.dart';
import '../../core/theme/ebtl_colors.dart';
import '../../models/app_data.dart';
import '../../models/common_models.dart';
import '../../models/product_models.dart';
import '../../models/shop_models.dart';
import '../../services/analytics_service.dart';
import '../../services/api_service.dart';
import '../../shared/widgets/app_state_widgets.dart';
import '../../shared/widgets/brand_widgets.dart';
import '../../shared/widgets/network_or_asset_image.dart';
import '../../shared/widgets/section_block.dart';
import '../shop/shop_product_loading.dart';
import '../shop/widgets/shop_loading_state.dart';
import '../shop/widgets/shop_product_detail_sheet.dart';
import '../shop/widgets/shop_product_widgets.dart';
import 'search_collection_screen.dart';
import 'widgets/explore_category_badges.dart';
import 'widgets/explore_hero_banner.dart';

class _ExplorePayload {
  final ShopResponse shop;

  /// Every category that came back with at least one product, in server order.
  final List<ShopCategory> categories;

  /// Products keyed by category id.
  final Map<String, List<ShopProduct>> productsByCategory;

  /// Deduped union of everything above, sorted by display order then name.
  final List<ShopProduct> allProducts;

  const _ExplorePayload({
    required this.shop,
    required this.categories,
    required this.productsByCategory,
    required this.allProducts,
  });

  List<ShopProduct> productsFor(String? categoryId) {
    if (categoryId == null) return allProducts;
    return productsByCategory[categoryId] ?? const [];
  }

  ShopCategory? categoryById(String? categoryId) {
    if (categoryId == null) return null;

    for (final category in categories) {
      if (category.id == categoryId) return category;
    }

    return null;
  }
}

/// The Explore tab — a single browse surface that replaced the separate Shop
/// and Cocktail Finder tabs. The Finder is still reachable through the hero.
class ExploreScreen extends StatefulWidget {
  final AppData data;
  final CartChangedCallback onCartChanged;
  final VoidCallback onOpenFinder;
  final Future<void> Function(ShopProduct product) onOpenProduct;
  final int unreadNotificationCount;
  final VoidCallback onOpenNotifications;
  final int activeOrdersCount;
  final VoidCallback onOpenActiveOrders;
  final String searchQuery;
  final int searchActivation;
  final ValueChanged<String> onSearchQueryChanged;
  final VoidCallback onSearchCollectionClosed;

  const ExploreScreen({
    super.key,
    required this.data,
    required this.onCartChanged,
    required this.onOpenFinder,
    required this.onOpenProduct,
    required this.unreadNotificationCount,
    required this.onOpenNotifications,
    required this.activeOrdersCount,
    required this.onOpenActiveOrders,
    required this.searchQuery,
    required this.searchActivation,
    required this.onSearchQueryChanged,
    required this.onSearchCollectionClosed,
  });

  @override
  State<ExploreScreen> createState() => _ExploreScreenState();
}

class _ExploreScreenState extends State<ExploreScreen> {
  late Future<_ExplorePayload> exploreFuture;
  late final TextEditingController searchController;
  final FocusNode searchFocusNode = FocusNode();
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
    if (widget.searchActivation > 0) {
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (mounted) searchFocusNode.requestFocus();
      });
    }
  }

  @override
  void didUpdateWidget(covariant ExploreScreen oldWidget) {
    super.didUpdateWidget(oldWidget);

    if (oldWidget.data.selectedLocationId != widget.data.selectedLocationId) {
      exploreFuture = loadExplore();
    }
    if (oldWidget.searchActivation != widget.searchActivation) {
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (mounted) searchFocusNode.requestFocus();
      });
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

  Future<_ExplorePayload> loadExplore() async {
    final shop = await ApiService.fetchShop(
      locationId: widget.data.selectedLocationId,
    );

    // No "all products" endpoint exists, so page every category in parallel
    // and stitch the results into one catalog the badges can filter locally.
    final productLists = await Future.wait(
      shop.categories.map(
        (category) => loadAllProductsInCategory(
          category,
          locationId: widget.data.selectedLocationId,
        ),
      ),
    );

    final categories = <ShopCategory>[];
    final productsByCategory = <String, List<ShopProduct>>{};
    final combined = <ShopProduct>[];

    for (var index = 0; index < shop.categories.length; index++) {
      final category = shop.categories[index];
      final products = productLists[index];

      if (products.isEmpty) continue;

      categories.add(category);
      productsByCategory[category.id] = products;
      combined.addAll(products);
    }

    final allProducts = dedupeShopProducts(combined);

    // Fall back to the featured sections if the catalog came back empty, so a
    // misconfigured category list does not leave the screen blank.
    return _ExplorePayload(
      shop: shop,
      categories: categories,
      productsByCategory: productsByCategory,
      allProducts: allProducts.isEmpty
          ? dedupeShopProducts(shop.allFeaturedProducts)
          : allProducts,
    );
  }

  Future<void> refreshExplore() async {
    final payload = await loadExplore();
    if (!mounted) return;

    setState(() {
      exploreFuture = Future.value(payload);
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
  List<ShopProduct> recentlyViewedProducts(_ExplorePayload payload) {
    final bySlug = <String, ShopProduct>{};

    for (final product in payload.allProducts) {
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
    if (!product.isCocktail) {
      await showShopProductDetailSheet(
        context: context,
        product: product,
        locationId: widget.data.selectedLocationId,
        onCartChanged: widget.onCartChanged,
      );

      await refreshRecentlyViewed();
      return;
    }

    if (product.slug.trim().isEmpty) {
      showMessage('This cocktail is missing a detail link.');
      return;
    }

    await widget.onOpenProduct(product);
    await refreshRecentlyViewed();
  }

  @override
  Widget build(BuildContext context) {
    return SafeArea(
      child: RefreshIndicator(
        color: EbtlColors.coral,
        onRefresh: refreshExplore,
        child: FutureBuilder<_ExplorePayload>(
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

            final payload = snapshot.data;
            if (payload == null) {
              return ListView(
                padding: const EdgeInsets.only(top: 40),
                children: const [
                  EmptyStateCard(message: 'Nothing to explore just yet.'),
                ],
              );
            }

            return buildContent(payload);
          },
        ),
      ),
    );
  }

  Widget buildContent(_ExplorePayload payload) {
    if (appliedQuery.isNotEmpty) return buildSearchResults(payload);
    // A category can disappear between reloads; fall back to "All".
    final activeCategoryId = payload.categoryById(selectedCategoryId)?.id;
    final visibleProducts = payload.productsFor(activeCategoryId);
    final recents = recentlyViewedProducts(payload);

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
        SliverToBoxAdapter(child: buildSearchField()),
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
              categories: payload.categories,
              productCounts: {
                for (final entry in payload.productsByCategory.entries)
                  entry.key: entry.value.length,
              },
              selectedCategoryId: activeCategoryId,
              totalProductCount: payload.allProducts.length,
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
                    payload.categoryById(activeCategoryId)?.name ??
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

  Widget buildSearchField() {
    return Padding(
      padding: const EdgeInsets.fromLTRB(22, 12, 22, 10),
      child: TextField(
        controller: searchController,
        focusNode: searchFocusNode,
        textInputAction: TextInputAction.search,
        onChanged: updateSearch,
        decoration: InputDecoration(
          hintText: 'Search cocktails, mixers, snacks',
          prefixIcon: const Icon(Icons.search_rounded),
          suffixIcon: searchController.text.isEmpty
              ? null
              : IconButton(
                  tooltip: 'Clear search',
                  onPressed: clearSearch,
                  icon: const Icon(Icons.close_rounded),
                ),
          filled: true,
          fillColor: EbtlColors.white,
          border: OutlineInputBorder(
            borderRadius: BorderRadius.circular(18),
            borderSide: const BorderSide(color: EbtlColors.border),
          ),
          enabledBorder: OutlineInputBorder(
            borderRadius: BorderRadius.circular(18),
            borderSide: const BorderSide(color: EbtlColors.border),
          ),
          focusedBorder: OutlineInputBorder(
            borderRadius: BorderRadius.circular(18),
            borderSide: const BorderSide(color: EbtlColors.coral, width: 1.5),
          ),
        ),
      ),
    );
  }

  Widget buildSearchResults(_ExplorePayload payload) {
    final query = appliedQuery.toLowerCase();
    final products = payload.allProducts
        .where((product) => product.matchesQuery(query))
        .toList();
    final categories = payload.categories
        .where((category) => category.matchesQuery(query))
        .toList();

    List<String> matchingValues(
      Iterable<String> values,
    ) {
      final matches = <String, String>{};
      for (final value in values) {
        final clean = value.trim();
        if (clean.toLowerCase().contains(query)) {
          matches.putIfAbsent(clean.toLowerCase(), () => clean);
        }
      }
      final result = matches.values.toList();
      result.sort((a, b) => a.toLowerCase().compareTo(b.toLowerCase()));
      return result;
    }

    final tags = matchingValues(
      payload.allProducts.expand(
        (product) => [
          ...product.tags,
          ...product.tagDetails.map((tag) => tag.name),
        ],
      ),
    );
    final ingredients = matchingValues(
      payload.allProducts.expand((product) => product.ingredientNames),
    );
    final hasResults =
        products.isNotEmpty ||
        categories.isNotEmpty ||
        tags.isNotEmpty ||
        ingredients.isNotEmpty;

    List<ShopProduct> productsForValue(
      String value,
      Iterable<String> Function(ShopProduct product) valuesForProduct,
    ) {
      final target = value.toLowerCase();
      return payload.allProducts
          .where(
            (product) => valuesForProduct(
              product,
            ).any((candidate) => candidate.toLowerCase() == target),
          )
          .toList();
    }

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
        SliverToBoxAdapter(child: buildSearchField()),
        if (!hasResults)
          const SliverToBoxAdapter(
            child: EmptyStateCard(
              message: 'No matches found. Try a different search.',
            ),
          )
        else
          SliverToBoxAdapter(
            child: Container(
              margin: const EdgeInsets.fromLTRB(22, 0, 22, 18),
              constraints: const BoxConstraints(maxHeight: 430),
              decoration: BoxDecoration(
                color: EbtlColors.white,
                borderRadius: BorderRadius.circular(18),
                border: Border.all(color: EbtlColors.border),
                boxShadow: [
                  BoxShadow(
                    color: Colors.black.withValues(alpha: 0.08),
                    blurRadius: 20,
                    offset: const Offset(0, 8),
                  ),
                ],
              ),
              clipBehavior: Clip.antiAlias,
              child: ListView(
                shrinkWrap: true,
                padding: EdgeInsets.zero,
                children: [
                  ...products.map(
                    (product) => _SearchResultRow(
                      label: product.name,
                      typeLabel: product.productTypeLabel,
                      product: product,
                      onTap: () => openProduct(product),
                    ),
                  ),
                  ...categories.map(
                    (category) => _SearchResultRow(
                      label: category.name,
                      typeLabel: 'Category',
                      onTap: () => openSearchCollection(
                        title: category.name,
                        products: payload.productsFor(category.id),
                      ),
                    ),
                  ),
                  ...tags.map(
                    (tag) => _SearchResultRow(
                      label: tag,
                      typeLabel: 'Tag',
                      onTap: () => openSearchCollection(
                        title: tag,
                        products: productsForValue(
                          tag,
                          (product) => [
                            ...product.tags,
                            ...product.tagDetails.map((item) => item.name),
                          ],
                        ),
                      ),
                    ),
                  ),
                  ...ingredients.map(
                    (ingredient) => _SearchResultRow(
                      label: ingredient,
                      typeLabel: 'Ingredient',
                      onTap: () => openSearchCollection(
                        title: ingredient,
                        products: productsForValue(
                          ingredient,
                          (product) => product.ingredientNames,
                        ),
                      ),
                    ),
                  ),
                ],
              ),
            ),
          ),
        const SliverToBoxAdapter(child: SizedBox(height: 24)),
      ],
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


class _SearchResultRow extends StatelessWidget {
  final String label;
  final String typeLabel;
  final ShopProduct? product;
  final VoidCallback onTap;

  const _SearchResultRow({
    required this.label,
    required this.typeLabel,
    this.product,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    return InkWell(
      onTap: onTap,
      child: Container(
        constraints: const BoxConstraints(minHeight: 68),
        padding: const EdgeInsets.fromLTRB(14, 10, 10, 10),
        decoration: const BoxDecoration(
          border: Border(bottom: BorderSide(color: EbtlColors.border)),
        ),
        child: Row(
          children: [
            Container(
              padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
              decoration: BoxDecoration(
                color: EbtlColors.coral.withValues(alpha: 0.12),
                borderRadius: BorderRadius.circular(999),
              ),
              child: Text(
                typeLabel.toUpperCase(),
                style: GoogleFonts.manrope(
                  fontSize: 9,
                  fontWeight: FontWeight.w900,
                  letterSpacing: 0.6,
                  color: EbtlColors.coral,
                ),
              ),
            ),
            const SizedBox(width: 10),
            Expanded(
              child: Text(
                label,
                maxLines: 2,
                overflow: TextOverflow.ellipsis,
                style: GoogleFonts.manrope(
                  fontSize: 14,
                  fontWeight: FontWeight.w800,
                  color: EbtlColors.navy,
                ),
              ),
            ),
            if (product != null)
              ClipRRect(
                borderRadius: BorderRadius.circular(10),
                child: SizedBox(
                  width: 48,
                  height: 48,
                  child: NetworkOrAssetImage(
                    imageUrl: product!.imageUrl,
                    asset: product!.imageAsset,
                  ),
                ),
              )
            else
              const Icon(
                Icons.chevron_right_rounded,
                color: EbtlColors.muted,
              ),
          ],
        ),
      ),
    );
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
