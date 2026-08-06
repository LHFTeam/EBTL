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
import '../../shared/widgets/section_block.dart';
import '../shop/shop_product_loading.dart';
import '../shop/widgets/shop_loading_state.dart';
import '../shop/widgets/shop_product_detail_sheet.dart';
import '../shop/widgets/shop_product_widgets.dart';
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
  });

  @override
  State<ExploreScreen> createState() => _ExploreScreenState();
}

class _ExploreScreenState extends State<ExploreScreen> {
  late Future<_ExplorePayload> exploreFuture;

  /// Null means the "All" badge is selected.
  String? selectedCategoryId;
  List<String> recentlyViewedSlugs = const [];
  String? addingProductId;

  @override
  void initState() {
    super.initState();
    exploreFuture = loadExplore();
    refreshRecentlyViewed();
  }

  @override
  void didUpdateWidget(covariant ExploreScreen oldWidget) {
    super.didUpdateWidget(oldWidget);

    if (oldWidget.data.selectedLocationId != widget.data.selectedLocationId) {
      exploreFuture = loadExplore();
    }
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
