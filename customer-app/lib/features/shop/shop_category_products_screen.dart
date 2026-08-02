import 'package:flutter/material.dart';

import '../../core/network/api_exception.dart';
import '../../core/theme/ebtl_colors.dart';
import '../../models/common_models.dart';
import '../../models/shop_models.dart';
import '../../services/analytics_service.dart';
import '../../services/api_service.dart';
import '../../shared/widgets/app_state_widgets.dart';
import 'widgets/shop_product_detail_sheet.dart';
import 'widgets/shop_product_widgets.dart';
import 'widgets/shop_simple_header.dart';

class ShopCategoryProductsScreen extends StatefulWidget {
  final ShopCategory category;
  final String? locationId;
  final String? locationName;
  final CartChangedCallback onCartChanged;
  final ValueChanged<int> onSwitchTab;
  final ValueChanged<ShopProduct> onOpenProduct;

  const ShopCategoryProductsScreen({
    super.key,
    required this.category,
    required this.locationId,
    required this.locationName,
    required this.onCartChanged,
    required this.onSwitchTab,
    required this.onOpenProduct,
  });

  @override
  State<ShopCategoryProductsScreen> createState() =>
      _ShopCategoryProductsScreenState();
}

class _ShopCategoryProductsScreenState
    extends State<ShopCategoryProductsScreen> {
  final ScrollController scrollController = ScrollController();

  final List<ShopProduct> products = <ShopProduct>[];
  int page = 1;
  bool hasMore = true;
  bool isLoading = false;
  bool hasLoadedInitial = false;
  String? errorMessage;
  String? addingProductId;
  ShopCategory? loadedCategory;

  @override
  void initState() {
    super.initState();
    AnalyticsService.logScreenView('shop_category');
    scrollController.addListener(onScroll);
    loadPage(reset: true);
  }

  @override
  void dispose() {
    scrollController.dispose();
    AnalyticsService.logScreenView('shop');
    super.dispose();
  }

  void onScroll() {
    if (!hasMore || isLoading) return;
    if (!scrollController.hasClients) return;

    final position = scrollController.position;
    if (position.pixels >= position.maxScrollExtent - 420) {
      loadPage();
    }
  }

  Future<void> loadPage({bool reset = false}) async {
    if (isLoading) return;

    setState(() {
      isLoading = true;
      errorMessage = null;

      if (reset) {
        page = 1;
        hasMore = true;
        hasLoadedInitial = false;
        products.clear();
      }
    });

    try {
      final response = await ApiService.fetchShopCategoryProducts(
        identifier: widget.category.identifier,
        locationId: widget.locationId,
        page: page,
        pageSize: 24,
        sort: 'display_order',
      );

      if (!mounted) return;

      setState(() {
        loadedCategory = response.category ?? loadedCategory;
        products.addAll(response.results);
        page = response.meta.page + 1;
        hasMore = response.meta.hasMore;
        hasLoadedInitial = true;
        isLoading = false;
      });
    } catch (error) {
      if (!mounted) return;

      setState(() {
        errorMessage = apiErrorMessage(error);
        hasLoadedInitial = true;
        isLoading = false;
      });
    }
  }

  Future<void> refresh() async {
    await loadPage(reset: true);
  }

  void showMessage(String message) {
    showAppSnackBar(context, message);
  }

  Future<void> quickAddProduct(ShopProduct product) async {
    if (!product.isCocktail) return;

    final locationId = widget.locationId?.trim();

    if (locationId == null || locationId.isEmpty) {
      showMessage('Choose a beach cart before adding items.');
      return;
    }

    if (!product.availability.isOrderable) {
      showMessage(product.unavailableReason);
      return;
    }

    final variant = product.firstOrderableVariant;

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

      setState(() => addingProductId = null);
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
        locationId: widget.locationId,
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

  @override
  Widget build(BuildContext context) {
    final title = loadedCategory?.name ?? widget.category.name;

    return Scaffold(
      backgroundColor: EbtlColors.cream,
      body: SafeArea(
        child: RefreshIndicator(
          color: EbtlColors.coral,
          onRefresh: refresh,
          child: CustomScrollView(
            controller: scrollController,
            physics: const AlwaysScrollableScrollPhysics(),
            slivers: [
              SliverToBoxAdapter(
                child: ShopSimpleHeader(
                  title: title,
                  subtitle: 'Browse ${widget.category.name.toLowerCase()}.',
                  onBack: () => Navigator.of(context).pop(),
                ),
              ),
              if (errorMessage != null && products.isEmpty)
                SliverToBoxAdapter(
                  child: InlineErrorCard(
                    message: errorMessage!,
                    onRetry: () => loadPage(reset: true),
                  ),
                )
              else if (!hasLoadedInitial)
                const EbtlLoadingSliver(label: 'Loading products...')
              else if (products.isEmpty)
                const SliverToBoxAdapter(
                  child: EmptyStateCard(
                    message: 'No products found in this category yet.',
                  ),
                )
              else
                SliverPadding(
                  padding: const EdgeInsets.fromLTRB(22, 14, 22, 0),
                  sliver: SliverGrid(
                    delegate: SliverChildBuilderDelegate((context, index) {
                      final product = products[index];

                      return ShopProductCardTile(
                        product: product,
                        compact: false,
                        isAdding: addingProductId == product.id,
                        subtitleOverride: product.isCocktail
                            ? product.shortDescription
                            : null,
                        subtitleMaxLines: product.isCocktail ? 3 : null,
                        onTap: () => openProduct(product),
                        onAdd: product.isCocktail
                            ? () => quickAddProduct(product)
                            : null,
                      );
                    }, childCount: products.length),
                    gridDelegate:
                        const SliverGridDelegateWithFixedCrossAxisCount(
                          crossAxisCount: 2,
                          mainAxisExtent: 256,
                          mainAxisSpacing: 14,
                          crossAxisSpacing: 14,
                        ),
                  ),
                ),
              if (isLoading && products.isNotEmpty)
                const EbtlLoadingSliver(
                  padding: EdgeInsets.all(22),
                  size: 56,
                  showLabel: false,
                ),
              const SliverToBoxAdapter(child: SizedBox(height: 24)),
            ],
          ),
        ),
      ),
    );
  }
}
