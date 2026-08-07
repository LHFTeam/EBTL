import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';

import '../../../core/network/api_exception.dart';
import '../../../core/theme/ebtl_colors.dart';
import '../../../core/theme/home_screen_visuals.dart';
import '../../../models/common_models.dart';
import '../../../models/shop_models.dart';
import '../../../models/spotlight_models.dart';
import '../../../services/analytics_service.dart';
import '../../../services/api_service.dart';
import '../../../shared/widgets/app_state_widgets.dart';
import '../../../shared/widgets/network_or_asset_image.dart';
import '../../../shared/widgets/sheet_close_button.dart';
import '../../shop/widgets/shop_product_detail_sheet.dart';
import '../../shop/widgets/shop_product_widgets.dart';

/// How much of the screen the sheet covers. Not the full height: the strip of
/// scrim left above it is what marks this as a sheet to swipe away rather than a
/// screen to navigate back from.
const double _sheetHeightFraction = 0.95;

/// Opens the sheet behind a Spotlight banner: the banner's own artwork across
/// the top, its title and subtitle under that, then the products marketing
/// selected for it, three to a row.
Future<void> showSpotlightSheet({
  required BuildContext context,
  required SpotlightBanner banner,
  required String? locationId,
  required CartChangedCallback onCartChanged,
  required ValueChanged<ShopProduct> onOpenCocktail,
}) {
  return showModalBottomSheet<void>(
    context: context,
    isScrollControlled: true,
    backgroundColor: Colors.transparent,
    // The artwork runs to the very top edge of the sheet, under the status bar,
    // so the sheet cannot be inset by the top safe area.
    useSafeArea: false,
    builder: (_) => SpotlightSheet(
      banner: banner,
      locationId: locationId,
      onCartChanged: onCartChanged,
      onOpenCocktail: onOpenCocktail,
    ),
  );
}

class SpotlightSheet extends StatefulWidget {
  final SpotlightBanner banner;
  final String? locationId;
  final CartChangedCallback onCartChanged;
  final ValueChanged<ShopProduct> onOpenCocktail;

  const SpotlightSheet({
    super.key,
    required this.banner,
    required this.locationId,
    required this.onCartChanged,
    required this.onOpenCocktail,
  });

  @override
  State<SpotlightSheet> createState() => _SpotlightSheetState();
}

class _SpotlightSheetState extends State<SpotlightSheet> {
  /// The banner as the server last described it. Starts as the one Home was
  /// rendered from and is replaced by the fetch, so a title edited in the
  /// dashboard since the last home load still shows correctly.
  late SpotlightBanner banner = widget.banner;

  List<ShopProduct> products = const [];
  bool isLoading = true;
  String? errorMessage;
  String? addingProductId;

  @override
  void initState() {
    super.initState();
    AnalyticsService.logScreenView('spotlight_banner');
    load();
  }

  Future<void> load() async {
    setState(() {
      isLoading = true;
      errorMessage = null;
    });

    try {
      final response = await ApiService.fetchSpotlightProducts(
        bannerId: widget.banner.id,
        locationId: widget.locationId,
      );

      if (!mounted) return;

      setState(() {
        banner = response.banner.isRenderable ? response.banner : banner;
        products = response.results;
        isLoading = false;
      });
    } catch (error) {
      if (!mounted) return;

      setState(() {
        errorMessage = apiErrorMessage(
          error,
          fallback: 'Could not load this collection.',
        );
        isLoading = false;
      });
    }
  }

  void showMessage(String message) => showAppSnackBar(context, message);

  /// Cocktails have a full detail screen of their own, so tapping one closes the
  /// sheet and hands off to it; everything else opens the shop's product sheet
  /// over this one. Same split as the shop and Explore grids.
  void openProduct(ShopProduct product) {
    if (product.isCocktail) {
      if (product.slug.trim().isEmpty) {
        showMessage('This cocktail is missing a detail link.');
        return;
      }

      Navigator.of(context).pop();
      widget.onOpenCocktail(product);
      return;
    }

    showShopProductDetailSheet(
      context: context,
      product: product,
      locationId: widget.locationId,
      onCartChanged: widget.onCartChanged,
    );
  }

  Future<void> quickAddProduct(ShopProduct product) async {
    if (addingProductId != null) return;

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

      setState(() => addingProductId = null);
      widget.onCartChanged(result.totals);
      showMessage(result.successMessage);
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

  @override
  Widget build(BuildContext context) {
    final subtitle = banner.subtitle?.trim() ?? '';

    return SizedBox(
      height: MediaQuery.sizeOf(context).height * _sheetHeightFraction,
      child: ClipRRect(
        borderRadius: const BorderRadius.vertical(top: Radius.circular(24)),
        child: ColoredBox(
          color: EbtlColors.cream,
          child: CustomScrollView(
            slivers: [
              SliverToBoxAdapter(
                child: Stack(
                  children: [
                    AspectRatio(
                      aspectRatio:
                          HomeScreenVisuals.spotlightBannerAspectRatio,
                      child: NetworkOrAssetImage(
                        imageUrl: banner.imageUrl,
                        asset: 'assets/banners/explore_hero.webp',
                      ),
                    ),
                    // Inset by the status bar so the close button clears the
                    // clock and notch the artwork itself runs under.
                    Positioned(
                      top: MediaQuery.paddingOf(context).top + 8,
                      right: 12,
                      child: const SheetCloseButton(),
                    ),
                  ],
                ),
              ),
              SliverToBoxAdapter(
                child: Padding(
                  padding: const EdgeInsets.fromLTRB(22, 20, 22, 0),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        banner.title,
                        style: GoogleFonts.playfairDisplay(
                          fontSize: 24,
                          height: 1.18,
                          fontWeight: FontWeight.w800,
                          color: EbtlColors.navy,
                        ),
                      ),
                      if (subtitle.isNotEmpty) ...[
                        const SizedBox(height: 6),
                        Text(
                          subtitle,
                          style: GoogleFonts.manrope(
                            fontSize: 13.5,
                            height: 1.4,
                            letterSpacing: 0,
                            fontWeight: FontWeight.w600,
                            color: EbtlColors.muted,
                          ),
                        ),
                      ],
                      const SizedBox(height: 18),
                    ],
                  ),
                ),
              ),
              if (isLoading)
                const EbtlLoadingSliver(label: 'Loading products...')
              else if (errorMessage != null)
                SliverToBoxAdapter(
                  child: InlineErrorCard(
                    message: errorMessage!,
                    onRetry: load,
                  ),
                )
              else if (products.isEmpty)
                const SliverToBoxAdapter(
                  child: EmptyStateCard(
                    message: 'Nothing in this collection right now.',
                  ),
                )
              else
                SliverPadding(
                  padding: const EdgeInsets.symmetric(horizontal: 22),
                  sliver: SliverGrid(
                    delegate: SliverChildBuilderDelegate((context, index) {
                      final product = products[index];

                      return ShopProductCardTile(
                        product: product,
                        compact: true,
                        isAdding: addingProductId == product.id,
                        subtitleOverride: product.isCocktail
                            ? product.shortDescription
                            : null,
                        subtitleMaxLines: 2,
                        onTap: () => openProduct(product),
                        onAdd: () => quickAddProduct(product),
                      );
                    }, childCount: products.length),
                    gridDelegate:
                        const SliverGridDelegateWithFixedCrossAxisCount(
                          crossAxisCount: 3,
                          mainAxisExtent: 198,
                          mainAxisSpacing: 12,
                          crossAxisSpacing: 10,
                        ),
                  ),
                ),
              SliverToBoxAdapter(
                child: SizedBox(
                  height: MediaQuery.paddingOf(context).bottom + 28,
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}
