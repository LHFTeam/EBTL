import 'package:flutter/material.dart';

import '../../core/network/api_exception.dart';
import '../../core/theme/ebtl_colors.dart';
import '../../models/app_data.dart';
import '../../models/product_models.dart';
import '../../models/shop_models.dart';
import '../../services/api_service.dart';
import '../../shared/widgets/app_state_widgets.dart';
import 'shop_category_picker_screen.dart';
import 'shop_category_products_screen.dart';
import 'widgets/shop_loading_state.dart';
import 'widgets/shop_product_detail_sheet.dart';
import 'widgets/shop_product_widgets.dart';
import 'widgets/shop_top_widgets.dart';

class _ShopScreenPayload {
  final ShopResponse shop;
  final List<ShopProduct> cocktails;
  final List<ShopProduct> snacks;
  final List<ShopProduct> essentials;

  const _ShopScreenPayload({
    required this.shop,
    required this.cocktails,
    required this.snacks,
    required this.essentials,
  });

  bool get hasAnyProducts {
    return cocktails.isNotEmpty || snacks.isNotEmpty || essentials.isNotEmpty;
  }
}

class ShopScreen extends StatefulWidget {
  final AppData data;
  final VoidCallback onCartChanged;
  final ValueChanged<int> onSwitchTab;
  final ValueChanged<ShopProduct> onOpenProduct;
  final int unreadNotificationCount;
  final VoidCallback onOpenNotifications;

  const ShopScreen({
    super.key,
    required this.data,
    required this.onCartChanged,
    required this.onSwitchTab,
    required this.onOpenProduct,
    required this.unreadNotificationCount,
    required this.onOpenNotifications,
  });

  @override
  State<ShopScreen> createState() => _ShopScreenState();
}

class _ShopScreenState extends State<ShopScreen> {
  late Future<_ShopScreenPayload> shopFuture;
  final GlobalKey snacksSectionKey = GlobalKey();
  final GlobalKey essentialsSectionKey = GlobalKey();
  String? addingProductId;

  @override
  void initState() {
    super.initState();
    shopFuture = loadShop();
  }

  @override
  void didUpdateWidget(covariant ShopScreen oldWidget) {
    super.didUpdateWidget(oldWidget);

    if (oldWidget.data.selectedLocationId != widget.data.selectedLocationId) {
      shopFuture = loadShop();
    }
  }

  Future<_ShopScreenPayload> loadShop() async {
    final shop = await ApiService.fetchShop(
      locationId: widget.data.selectedLocationId,
    );

    final allFeaturedProducts = shop.allFeaturedProducts;

    final productLists = await Future.wait<List<ShopProduct>>([
      loadProductsForCategoryTarget(
        shop,
        'cocktails',
        fallback: shop.sections.featuredCocktails.items,
      ),
      loadProductsForCategoryTarget(
        shop,
        'snacks',
        fallback: productsMatchingCategoryTarget(allFeaturedProducts, 'snacks'),
      ),
      loadProductsForCategoryTarget(
        shop,
        'essentials',
        fallback: productsMatchingCategoryTarget(
          allFeaturedProducts,
          'essentials',
        ),
      ),
    ]);

    return _ShopScreenPayload(
      shop: shop,
      cocktails: productLists[0],
      snacks: productLists[1],
      essentials: productLists[2],
    );
  }

  Future<List<ShopProduct>> loadProductsForCategoryTarget(
    ShopResponse shop,
    String target, {
    required List<ShopProduct> fallback,
  }) async {
    final category = categoryForTarget(shop, target);

    if (category == null) {
      return dedupeShopProducts(fallback);
    }

    final products = <ShopProduct>[];
    var page = 1;
    var hasMore = true;

    while (hasMore) {
      final response = await ApiService.fetchShopCategoryProducts(
        identifier: category.identifier,
        locationId: widget.data.selectedLocationId,
        page: page,
        pageSize: 100,
        sort: 'display_order',
      );

      products.addAll(response.results);
      hasMore = response.meta.hasMore;
      page = response.meta.page + 1;

      if (response.results.isEmpty) {
        break;
      }
    }

    return dedupeShopProducts(products);
  }

  ShopCategory? categoryForTarget(ShopResponse shop, String target) {
    return shop.categoryByTarget(target) ??
        shop.categoryByTarget(singularCategoryTarget(target));
  }

  String singularCategoryTarget(String target) {
    final clean = target.trim().toLowerCase();

    if (clean.endsWith('ies') && clean.length > 3) {
      return '${clean.substring(0, clean.length - 3)}y';
    }

    if (clean.endsWith('s') && clean.length > 1) {
      return clean.substring(0, clean.length - 1);
    }

    return clean;
  }

  List<ShopProduct> productsMatchingCategoryTarget(
    Iterable<ShopProduct> products,
    String target,
  ) {
    final cleanTarget = target.trim().toLowerCase();
    final singularTarget = singularCategoryTarget(cleanTarget);

    return dedupeShopProducts(
      products.where((product) {
        final categoryName = product.category?.name.trim().toLowerCase() ?? '';
        final categorySlug = product.category?.slug?.trim().toLowerCase() ?? '';
        final productType = product.productType.trim().toLowerCase();

        return categoryName == cleanTarget ||
            categoryName == singularTarget ||
            categoryName.contains(cleanTarget) ||
            categoryName.contains(singularTarget) ||
            categorySlug == cleanTarget ||
            categorySlug == singularTarget ||
            categorySlug.contains(cleanTarget) ||
            categorySlug.contains(singularTarget) ||
            productType == cleanTarget ||
            productType == singularTarget;
      }).toList(),
    );
  }

  List<ShopProduct> dedupeShopProducts(List<ShopProduct> products) {
    final byId = <String, ShopProduct>{};

    for (final product in products) {
      byId[product.id] = product;
    }

    final deduped = byId.values.toList();

    deduped.sort((a, b) {
      final orderCompare = a.displayOrder.compareTo(b.displayOrder);
      if (orderCompare != 0) return orderCompare;

      return a.name.toLowerCase().compareTo(b.name.toLowerCase());
    });

    return deduped;
  }

  Future<void> refreshShop() async {
    final response = await loadShop();
    if (!mounted) return;

    setState(() {
      shopFuture = Future.value(response);
    });
  }

  int cartQuantityFor(_ShopScreenPayload? payload) {
    return payload?.shop.cartSummary?.totalQuantity ??
        widget.data.cartSummary?.totalQuantity ??
        0;
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

      if (!mounted) return;

      showMessage(result.successMessage);
      widget.onCartChanged();

      setState(() {
        addingProductId = null;
        shopFuture = loadShop();
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

  void openProduct(ShopProduct product) {
    if (!product.isCocktail) {
      showShopProductDetailSheet(
        context: context,
        product: product,
        locationId: widget.data.selectedLocationId,
        onCartChanged: widget.onCartChanged,
      );
      return;
    }

    if (product.slug.trim().isEmpty) {
      showMessage('This cocktail is missing a detail link.');
      return;
    }

    widget.onOpenProduct(product);
  }

  void openCategory(ShopCategory category) {
    Navigator.of(context).push(
      MaterialPageRoute(
        builder: (_) => ShopCategoryProductsScreen(
          category: category,
          locationId: widget.data.selectedLocationId,
          locationName: widget.data.selectedLocationName,
          onCartChanged: widget.onCartChanged,
          onSwitchTab: widget.onSwitchTab,
          onOpenProduct: widget.onOpenProduct,
        ),
      ),
    );
  }

  void openCategoryByTarget(ShopResponse shop, String target) {
    final category = categoryForTarget(shop, target);

    if (category == null) {
      showMessage('This category is not available yet.');
      return;
    }

    openCategory(category);
  }

  void openEssentialsFromBanner(ShopResponse shop) {
    final essentials = categoryForTarget(shop, 'essentials');

    if (essentials != null) {
      openCategory(essentials);
      return;
    }

    final context = essentialsSectionKey.currentContext;
    if (context != null) {
      Scrollable.ensureVisible(
        context,
        duration: const Duration(milliseconds: 350),
        curve: Curves.easeOut,
      );
    }
  }

  void openSnacksAndEssentials(ShopResponse shop) {
    final selectedCategories = <ShopCategory>[];

    final snacks = categoryForTarget(shop, 'snacks');
    if (snacks != null) selectedCategories.add(snacks);

    final essentials = categoryForTarget(shop, 'essentials');
    if (essentials != null &&
        !selectedCategories.any((category) => category.id == essentials.id)) {
      selectedCategories.add(essentials);
    }

    if (selectedCategories.isEmpty) {
      openEssentialsFromBanner(shop);
      return;
    }

    Navigator.of(context).push(
      MaterialPageRoute(
        builder: (_) => ShopCategoryPickerScreen(
          title: 'Snacks, beach essentials and more',
          categories: selectedCategories,
          onCategoryTap: openCategory,
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    return FutureBuilder<_ShopScreenPayload>(
      future: shopFuture,
      builder: (context, snapshot) {
        final payload = snapshot.data;

        if (snapshot.connectionState == ConnectionState.waiting) {
          return const ShopLoadingState();
        }

        if (snapshot.hasError) {
          return SafeArea(
            child: CustomScrollView(
              slivers: [
                SliverToBoxAdapter(
                  child: ShopHeader(
                    unreadNotificationCount: widget.unreadNotificationCount,
                    onOpenNotifications: widget.onOpenNotifications,
                  ),
                ),
                SliverToBoxAdapter(
                  child: InlineErrorCard(
                    message: apiErrorMessage(snapshot.error!),
                    onRetry: () {
                      setState(() => shopFuture = loadShop());
                    },
                  ),
                ),
              ],
            ),
          );
        }

        if (payload == null) {
          return SafeArea(
            child: CustomScrollView(
              slivers: [
                SliverToBoxAdapter(
                  child: ShopHeader(
                    unreadNotificationCount: widget.unreadNotificationCount,
                    onOpenNotifications: widget.onOpenNotifications,
                  ),
                ),
                SliverToBoxAdapter(
                  child: InlineErrorCard(
                    message: 'The backend returned no shop data.',
                    onRetry: () {
                      setState(() => shopFuture = loadShop());
                    },
                  ),
                ),
              ],
            ),
          );
        }

        final shop = payload.shop;

        return SafeArea(
          child: RefreshIndicator(
            color: EbtlColors.coral,
            onRefresh: refreshShop,
            child: CustomScrollView(
              physics: const AlwaysScrollableScrollPhysics(),
              slivers: [
                SliverToBoxAdapter(
                  child: ShopHeader(
                    unreadNotificationCount: widget.unreadNotificationCount,
                    onOpenNotifications: widget.onOpenNotifications,
                  ),
                ),
                SliverToBoxAdapter(
                  child: ShopBannerCard(
                    imageUrl: shop.banner.imageUrl,
                    onTap: () => openEssentialsFromBanner(shop),
                  ),
                ),
                if (shop.categories.isNotEmpty)
                  SliverToBoxAdapter(
                    child: ShopCategoryRail(
                      categories: shop.categories,
                      onTap: openCategory,
                    ),
                  ),
                if (payload.cocktails.isNotEmpty)
                  SliverToBoxAdapter(
                    child: ShopProductGridSection(
                      title: 'Cocktails',
                      items: payload.cocktails,
                      addingProductId: addingProductId,
                      onProductTap: openProduct,
                      onQuickAdd: quickAddProduct,
                    ),
                  ),
                if (payload.snacks.isNotEmpty)
                  SliverToBoxAdapter(
                    child: ShopProductGridSection(
                      key: snacksSectionKey,
                      title: 'Snacks',
                      items: payload.snacks,
                      addingProductId: addingProductId,
                      onProductTap: openProduct,
                      onQuickAdd: quickAddProduct,
                    ),
                  ),
                if (payload.essentials.isNotEmpty)
                  SliverToBoxAdapter(
                    child: ShopProductGridSection(
                      key: essentialsSectionKey,
                      title: 'Essentials',
                      items: payload.essentials,
                      addingProductId: addingProductId,
                      onProductTap: openProduct,
                      onQuickAdd: quickAddProduct,
                    ),
                  ),
                if (!payload.hasAnyProducts)
                  const SliverToBoxAdapter(
                    child: Padding(
                      padding: EdgeInsets.only(top: 16),
                      child: EmptyStateCard(
                        message: 'Shop items are coming soon.',
                      ),
                    ),
                  ),
                const SliverToBoxAdapter(child: SizedBox(height: 24)),
              ],
            ),
          ),
        );
      },
    );
  }
}
