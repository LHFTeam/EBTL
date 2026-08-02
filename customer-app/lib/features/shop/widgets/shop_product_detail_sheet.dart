import 'package:flutter/material.dart';
import 'package:flutter_markdown/flutter_markdown.dart';
import 'package:google_fonts/google_fonts.dart';

import '../../../core/network/api_exception.dart';
import '../../../core/theme/ebtl_colors.dart';
import '../../../core/utils/formatters.dart';
import '../../../models/common_models.dart';
import '../../../models/product_models.dart';
import '../../../models/shop_models.dart';
import '../../../services/analytics_service.dart';
import '../../../services/api_service.dart';
import '../../../shared/widgets/app_state_widgets.dart';
import '../../../shared/widgets/network_or_asset_image.dart';
import '../../../shared/widgets/product_tag_widgets.dart';

/// Bottom-sheet detail view for non-cocktail shop products (snacks, essentials,
/// bundles, add-ons). Cocktails have their own full-screen detail; these
/// products carry everything needed (image, description, price, variants,
/// availability) on the already-loaded [ShopProduct], so this sheet needs no
/// extra backend call and adds to cart directly.
Future<void> showShopProductDetailSheet({
  required BuildContext context,
  required ShopProduct product,
  required String? locationId,
  required CartChangedCallback onCartChanged,
}) {
  return showModalBottomSheet<void>(
    context: context,
    isScrollControlled: true,
    backgroundColor: Colors.transparent,
    builder: (_) => ShopProductDetailSheet(
      product: product,
      locationId: locationId,
      onCartChanged: onCartChanged,
    ),
  );
}

class ShopProductDetailSheet extends StatefulWidget {
  final ShopProduct product;
  final String? locationId;
  final CartChangedCallback onCartChanged;

  const ShopProductDetailSheet({
    super.key,
    required this.product,
    required this.locationId,
    required this.onCartChanged,
  });

  @override
  State<ShopProductDetailSheet> createState() => _ShopProductDetailSheetState();
}

class _ShopProductDetailSheetState extends State<ShopProductDetailSheet> {
  int quantity = 1;
  bool isAdding = false;

  ShopProduct get product => widget.product;

  ProductVariant? get orderableVariant {
    final firstOrderable = product.firstOrderableVariant;
    if (firstOrderable != null) return firstOrderable;

    if (!product.availability.isOrderable) return null;

    for (final variant in product.variants) {
      if (variant.isActive) return variant;
    }

    return null;
  }

  @override
  void initState() {
    super.initState();

    final variant = orderableVariant;
    AnalyticsService.logViewItem(
      AnalyticsItem(
        id: product.id,
        name: product.name,
        category: product.category?.name ?? product.productType,
        variant: variant?.name,
        price: variant?.priceIncVat ?? product.startingPriceIncVat ?? 0,
        quantity: 1,
        currency: variant?.currency ?? product.currency,
      ),
    );

    // Feeds the Explore "Recently viewed" rail. Fire-and-forget: a storage
    // failure must never take the sheet down with it.
    ApiService.recordRecentlyViewed(product.slug).ignore();
  }

  void changeQuantity(int delta) {
    final next = (quantity + delta).clamp(1, 99);
    if (next == quantity) return;
    setState(() => quantity = next);
  }

  Future<void> addToCart() async {
    if (isAdding) return;

    final locationId = widget.locationId?.trim();
    if (locationId == null || locationId.isEmpty) {
      showAppSnackBar(context, 'Choose a beach cart before adding items.');
      return;
    }

    if (!product.availability.isOrderable) {
      showAppSnackBar(context, product.unavailableReason);
      return;
    }

    final variant = orderableVariant;
    if (variant == null) {
      showAppSnackBar(context, product.unavailableReason);
      return;
    }

    setState(() => isAdding = true);

    try {
      final result = await ApiService.addShopProductToCart(
        productId: product.id,
        variantId: variant.id,
        quantity: quantity,
        locationId: locationId,
      );

      AnalyticsService.logAddToCart(
        AnalyticsItem(
          id: product.id,
          name: product.name,
          category: product.category?.name ?? product.productType,
          variant: variant.name,
          price: variant.priceIncVat,
          quantity: quantity,
          currency: variant.currency,
        ),
      );

      if (!mounted) return;

      widget.onCartChanged(result.totals);
      showAppSnackBar(context, result.successMessage);
      Navigator.of(context).pop();
    } catch (error) {
      if (!mounted) return;

      setState(() => isAdding = false);
      showAppSnackBar(
        context,
        apiErrorMessage(
          error,
          fallback: 'Could not add this item to your cart.',
        ),
      );
    }
  }

  @override
  Widget build(BuildContext context) {
    final variant = orderableVariant;
    final canAdd = product.availability.isOrderable && variant != null;
    final description = product.description?.trim() ?? '';
    final shortDescription = product.shortDescription?.trim() ?? '';

    return Padding(
      padding: EdgeInsets.only(
        bottom: MediaQuery.of(context).viewInsets.bottom,
      ),
      child: Container(
        constraints: BoxConstraints(
          maxHeight: MediaQuery.of(context).size.height * 0.9,
        ),
        decoration: const BoxDecoration(
          color: EbtlColors.cream,
          borderRadius: BorderRadius.vertical(top: Radius.circular(28)),
        ),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Flexible(
              child: ListView(
                padding: EdgeInsets.zero,
                shrinkWrap: true,
                children: [
                  Stack(
                    children: [
                      ClipRRect(
                        borderRadius: const BorderRadius.vertical(
                          top: Radius.circular(28),
                        ),
                        child: SizedBox(
                          height: 210,
                          width: double.infinity,
                          child: NetworkOrAssetImage(
                            imageUrl: product.imageUrl,
                            asset: product.imageAsset,
                            fit: BoxFit.cover,
                          ),
                        ),
                      ),
                      Positioned(
                        top: 12,
                        right: 12,
                        child: Material(
                          color: EbtlColors.white.withValues(alpha: 0.85),
                          shape: const CircleBorder(),
                          child: InkWell(
                            customBorder: const CircleBorder(),
                            onTap: () => Navigator.of(context).pop(),
                            child: const SizedBox(
                              width: 40,
                              height: 40,
                              child: Icon(Icons.close, size: 22),
                            ),
                          ),
                        ),
                      ),
                    ],
                  ),
                  Padding(
                    padding: const EdgeInsets.fromLTRB(22, 18, 22, 8),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          product.productTypeLabel.toUpperCase(),
                          style: GoogleFonts.manrope(
                            fontSize: 12,
                            letterSpacing: 0.6,
                            fontWeight: FontWeight.w800,
                            color: EbtlColors.muted,
                          ),
                        ),
                        const SizedBox(height: 4),
                        Text(
                          product.name,
                          style: GoogleFonts.playfairDisplay(
                            fontSize: 26,
                            fontWeight: FontWeight.w800,
                            color: EbtlColors.navy,
                          ),
                        ),
                        const SizedBox(height: 8),
                        Text(
                          product.priceLabel,
                          style: GoogleFonts.manrope(
                            fontSize: 18,
                            fontWeight: FontWeight.w900,
                            color: EbtlColors.coral,
                          ),
                        ),
                        if (product.tagDetails.isNotEmpty) ...[
                          const SizedBox(height: 14),
                          Wrap(
                            spacing: 8,
                            runSpacing: 8,
                            children: product.tagDetails
                                .map((tag) => ProductTagBadge(tag: tag))
                                .toList(),
                          ),
                        ],
                        if (description.isNotEmpty) ...[
                          const SizedBox(height: 18),
                          MarkdownBody(
                            data: description,
                            styleSheet: MarkdownStyleSheet(
                              p: GoogleFonts.manrope(
                                fontSize: 15,
                                height: 1.42,
                                fontWeight: FontWeight.w600,
                                color: EbtlColors.ink,
                              ),
                              strong: GoogleFonts.manrope(
                                fontWeight: FontWeight.w900,
                                color: EbtlColors.navy,
                              ),
                              listBullet: GoogleFonts.manrope(
                                fontSize: 15,
                                color: EbtlColors.coral,
                                fontWeight: FontWeight.w900,
                              ),
                            ),
                          ),
                        ] else if (shortDescription.isNotEmpty) ...[
                          const SizedBox(height: 18),
                          Text(
                            shortDescription,
                            style: GoogleFonts.manrope(
                              fontSize: 15,
                              height: 1.42,
                              fontWeight: FontWeight.w600,
                              color: EbtlColors.ink,
                            ),
                          ),
                        ],
                        if (!canAdd) ...[
                          const SizedBox(height: 18),
                          Text(
                            product.unavailableReason,
                            style: GoogleFonts.manrope(
                              fontSize: 14,
                              fontWeight: FontWeight.w700,
                              color: EbtlColors.coral,
                            ),
                          ),
                        ],
                        const SizedBox(height: 20),
                      ],
                    ),
                  ),
                ],
              ),
            ),
            _ShopProductAddBar(
              priceLabel: variant != null
                  ? formatMoney(
                      variant.priceIncVat * quantity,
                      variant.currency,
                    )
                  : product.priceLabel,
              quantity: quantity,
              canAdd: canAdd,
              isAdding: isAdding,
              onDecrement: () => changeQuantity(-1),
              onIncrement: () => changeQuantity(1),
              onAdd: canAdd ? addToCart : null,
            ),
          ],
        ),
      ),
    );
  }
}

class _ShopProductAddBar extends StatelessWidget {
  final String priceLabel;
  final int quantity;
  final bool canAdd;
  final bool isAdding;
  final VoidCallback onDecrement;
  final VoidCallback onIncrement;
  final VoidCallback? onAdd;

  const _ShopProductAddBar({
    required this.priceLabel,
    required this.quantity,
    required this.canAdd,
    required this.isAdding,
    required this.onDecrement,
    required this.onIncrement,
    required this.onAdd,
  });

  @override
  Widget build(BuildContext context) {
    return SafeArea(
      top: false,
      child: Container(
        padding: const EdgeInsets.fromLTRB(22, 12, 22, 12),
        decoration: const BoxDecoration(
          color: EbtlColors.white,
          border: Border(top: BorderSide(color: EbtlColors.border)),
        ),
        child: Row(
          children: [
            if (canAdd) ...[
              _QuantityStepper(
                quantity: quantity,
                onDecrement: onDecrement,
                onIncrement: onIncrement,
              ),
              const SizedBox(width: 14),
            ],
            Expanded(
              child: SizedBox(
                height: 54,
                child: ElevatedButton(
                  onPressed: isAdding ? null : onAdd,
                  style: ElevatedButton.styleFrom(
                    backgroundColor: EbtlColors.coral,
                    disabledBackgroundColor: EbtlColors.border,
                    foregroundColor: Colors.white,
                    shape: RoundedRectangleBorder(
                      borderRadius: BorderRadius.circular(16),
                    ),
                  ),
                  child: isAdding
                      ? const SizedBox(
                          width: 22,
                          height: 22,
                          child: CircularProgressIndicator(
                            strokeWidth: 2.4,
                            color: Colors.white,
                          ),
                        )
                      : Text(
                          canAdd ? 'Add to cart · $priceLabel' : 'Unavailable',
                          style: GoogleFonts.manrope(
                            fontSize: 15,
                            fontWeight: FontWeight.w900,
                          ),
                        ),
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _QuantityStepper extends StatelessWidget {
  final int quantity;
  final VoidCallback onDecrement;
  final VoidCallback onIncrement;

  const _QuantityStepper({
    required this.quantity,
    required this.onDecrement,
    required this.onIncrement,
  });

  @override
  Widget build(BuildContext context) {
    return Container(
      decoration: BoxDecoration(
        color: EbtlColors.cream,
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: EbtlColors.border),
      ),
      child: Row(
        children: [
          _StepButton(icon: Icons.remove, onTap: onDecrement),
          SizedBox(
            width: 32,
            child: Text(
              quantity.toString(),
              textAlign: TextAlign.center,
              style: GoogleFonts.manrope(
                fontSize: 16,
                fontWeight: FontWeight.w900,
                color: EbtlColors.navy,
              ),
            ),
          ),
          _StepButton(icon: Icons.add, onTap: onIncrement),
        ],
      ),
    );
  }
}

class _StepButton extends StatelessWidget {
  final IconData icon;
  final VoidCallback onTap;

  const _StepButton({required this.icon, required this.onTap});

  @override
  Widget build(BuildContext context) {
    return InkWell(
      borderRadius: BorderRadius.circular(16),
      onTap: onTap,
      child: SizedBox(
        width: 44,
        height: 52,
        child: Icon(icon, size: 20, color: EbtlColors.navy),
      ),
    );
  }
}
