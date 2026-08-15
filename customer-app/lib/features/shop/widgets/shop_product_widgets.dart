import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';

import '../../../core/theme/ebtl_colors.dart';
import '../../../core/theme/home_screen_visuals.dart';
import '../../../models/cocktail_models.dart';
import '../../../models/shop_models.dart';
import '../../../shared/widgets/cocktail_card_widgets.dart';
import '../../../shared/widgets/network_or_asset_image.dart';
import '../../../shared/widgets/product_tag_widgets.dart';

/// A product in the shop grid, drawn as the Cocktail Finder draws its cards.
///
/// The two grids show the same catalog, so they use the same card: the shell
/// from [CocktailGridCard], fed through the [Cocktail.fromShopProduct] bridge.
/// The one difference is the corner action — the Finder's heart marks a
/// favorite, while here it is the plus that adds the product to the cart.
class ShopCatalogCard extends StatelessWidget {
  final ShopProduct product;
  final bool isAdding;
  final VoidCallback onTap;
  final VoidCallback onAdd;

  const ShopCatalogCard({
    super.key,
    required this.product,
    required this.isAdding,
    required this.onTap,
    required this.onAdd,
  });

  @override
  Widget build(BuildContext context) {
    return CocktailGridCard(
      cocktail: Cocktail.fromShopProduct(product),
      onTap: onTap,
      onAdd: onAdd,
      isAdding: isAdding,
    );
  }
}

class ShopProductGridSection extends StatefulWidget {
  final String title;
  final List<ShopProduct> items;
  final String? addingProductId;
  final ValueChanged<ShopProduct> onProductTap;
  final ValueChanged<ShopProduct> onQuickAdd;

  /// How many tiles show before "View more". Used by the shop's stacked
  /// sections; Explore's grid pages itself as the customer scrolls instead.
  final int initialVisibleCount;

  const ShopProductGridSection({
    super.key,
    required this.title,
    required this.items,
    required this.addingProductId,
    required this.onProductTap,
    required this.onQuickAdd,
    this.initialVisibleCount = 6,
  });

  @override
  State<ShopProductGridSection> createState() => _ShopProductGridSectionState();
}

class _ShopProductGridSectionState extends State<ShopProductGridSection> {
  bool isExpanded = false;

  @override
  void didUpdateWidget(covariant ShopProductGridSection oldWidget) {
    super.didUpdateWidget(oldWidget);

    if (oldWidget.title != widget.title ||
        productSignature(oldWidget.items) != productSignature(widget.items)) {
      isExpanded = false;
    }
  }

  String productSignature(List<ShopProduct> products) {
    return products.map((product) => product.id).join('|');
  }

  void expandSection() {
    setState(() => isExpanded = true);
  }

  @override
  Widget build(BuildContext context) {
    if (widget.items.isEmpty) {
      return const SizedBox.shrink();
    }

    final visibleItems = isExpanded
        ? widget.items
        : widget.items.take(widget.initialVisibleCount).toList();

    final hiddenCount = widget.items.length - widget.initialVisibleCount;
    final showViewMoreButton = !isExpanded && hiddenCount > 0;

    return Padding(
      padding: const EdgeInsets.only(bottom: 22),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          ShopGridSectionHeader(title: widget.title),
          const SizedBox(height: 14),
          GridView.builder(
            shrinkWrap: true,
            primary: false,
            physics: const NeverScrollableScrollPhysics(),
            padding: const EdgeInsets.symmetric(horizontal: 22),
            itemCount: visibleItems.length,
            gridDelegate: SliverGridDelegateWithFixedCrossAxisCount(
              crossAxisCount: 3,
              mainAxisExtent: ShopProductCardTile.heightFor(
                compact: true,
                subtitleMaxLines: 2,
              ),
              mainAxisSpacing: 12,
              crossAxisSpacing: 10,
            ),
            itemBuilder: (context, index) {
              final product = visibleItems[index];

              return ShopProductCardTile(
                product: product,
                compact: true,
                isAdding: widget.addingProductId == product.id,
                subtitleOverride: product.isCocktail
                    ? product.shortDescription
                    : null,
                subtitleMaxLines: 2,
                onTap: () => widget.onProductTap(product),
                onAdd: () => widget.onQuickAdd(product),
              );
            },
          ),
          if (showViewMoreButton)
            ShopViewMoreButton(hiddenCount: hiddenCount, onTap: expandSection),
        ],
      ),
    );
  }
}

class ShopViewMoreButton extends StatelessWidget {
  final int hiddenCount;
  final VoidCallback onTap;

  const ShopViewMoreButton({
    super.key,
    required this.hiddenCount,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.fromLTRB(22, 14, 22, 0),
      child: SizedBox(
        width: double.infinity,
        height: 48,
        child: OutlinedButton.icon(
          onPressed: onTap,
          icon: const Icon(Icons.expand_more),
          label: const Text('View more'),
          style: OutlinedButton.styleFrom(
            foregroundColor: EbtlColors.coral,
            side: const BorderSide(color: EbtlColors.coral, width: 1.2),
            shape: RoundedRectangleBorder(
              borderRadius: BorderRadius.circular(16),
            ),
            textStyle: GoogleFonts.manrope(
              fontSize: 13,
              fontWeight: FontWeight.w900,
            ),
          ),
        ),
      ),
    );
  }
}

class ShopGridSectionHeader extends StatelessWidget {
  final String title;

  const ShopGridSectionHeader({super.key, required this.title});

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 22),
      child: Text(
        title,
        style: GoogleFonts.playfairDisplay(
          fontSize: 22,
          fontWeight: FontWeight.w800,
          color: EbtlColors.navy,
        ),
      ),
    );
  }
}

class ShopProductSection extends StatelessWidget {
  final String title;
  final String actionText;
  final List<ShopProduct> items;
  final bool compact;
  final String? addingProductId;
  final VoidCallback onActionTap;
  final ValueChanged<ShopProduct> onProductTap;
  final ValueChanged<ShopProduct> onQuickAdd;

  const ShopProductSection({
    super.key,
    required this.title,
    required this.actionText,
    required this.items,
    required this.compact,
    required this.addingProductId,
    required this.onActionTap,
    required this.onProductTap,
    required this.onQuickAdd,
  });

  @override
  Widget build(BuildContext context) {
    final screenWidth = MediaQuery.of(context).size.width;

    final cardWidth = compact
        ? ((screenWidth - 80) / 4).clamp(92.0, 120.0).toDouble()
        : HomeScreenVisuals.featuredProductCardWidth;

    final sectionHeight = compact
        ? 170.0
        : HomeScreenVisuals.featuredProductCardHeight;

    return Padding(
      padding: const EdgeInsets.only(bottom: 20),
      child: Column(
        children: [
          ShopSectionHeader(
            title: title,
            actionText: actionText,
            onTap: onActionTap,
          ),
          const SizedBox(height: 14),
          SizedBox(
            height: sectionHeight,
            child: ListView.separated(
              padding: const EdgeInsets.symmetric(horizontal: 22),
              scrollDirection: Axis.horizontal,
              itemCount: items.length,
              separatorBuilder: (_, _) => const SizedBox(width: 12),
              itemBuilder: (context, index) {
                final product = items[index];

                if (!compact && product.isCocktail) {
                  return SizedBox(
                    width: HomeScreenVisuals.featuredProductCardWidth,
                    child: CocktailSmallCard(
                      cocktail: Cocktail.fromShopProduct(product),
                      onTap: () => onProductTap(product),
                    ),
                  );
                }

                return ShopProductCardTile(
                  product: product,
                  width: cardWidth,
                  compact: compact,
                  isAdding: addingProductId == product.id,
                  onTap: () => onProductTap(product),
                  onAdd: product.isCocktail ? () => onQuickAdd(product) : null,
                );
              },
            ),
          ),
        ],
      ),
    );
  }
}

class ShopSectionHeader extends StatelessWidget {
  final String title;
  final String actionText;
  final VoidCallback onTap;

  const ShopSectionHeader({
    super.key,
    required this.title,
    required this.actionText,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 22),
      child: Row(
        children: [
          Expanded(
            child: Text(
              title,
              style: GoogleFonts.playfairDisplay(
                fontSize: 22,
                fontWeight: FontWeight.w800,
                color: EbtlColors.navy,
              ),
            ),
          ),
          InkWell(
            onTap: onTap,
            borderRadius: BorderRadius.circular(999),
            child: Padding(
              padding: const EdgeInsets.symmetric(horizontal: 4, vertical: 4),
              child: Row(
                children: [
                  Text(
                    actionText,
                    style: GoogleFonts.manrope(
                      fontSize: 13,
                      fontWeight: FontWeight.w900,
                      color: EbtlColors.teal,
                    ),
                  ),
                  const SizedBox(width: 5),
                  const Icon(
                    Icons.chevron_right,
                    color: EbtlColors.teal,
                    size: 20,
                  ),
                ],
              ),
            ),
          ),
        ],
      ),
    );
  }
}

class ShopProductCardTile extends StatelessWidget {
  final ShopProduct product;
  final double? width;
  final bool compact;
  final bool isAdding;
  final VoidCallback onTap;
  final VoidCallback? onAdd;
  final String? subtitleOverride;
  final int? subtitleMaxLines;

  const ShopProductCardTile({
    super.key,
    required this.product,
    this.width,
    required this.compact,
    required this.isAdding,
    required this.onTap,
    required this.onAdd,
    this.subtitleOverride,
    this.subtitleMaxLines,
  });

  static const double _compactImageHeight = 84;
  static const double _imageHeight = 112;
  static const double _compactTextPaddingY = 8;
  static const double _textPaddingY = 10;
  static const double _borderWidth = 1;

  /// The height this tile lays out to.
  ///
  /// Both its artwork and its text block are fixed boxes, so a rail or grid
  /// that gives it less than this overflows rather than compressing the card.
  /// Fixed-extent call sites must size themselves from this instead of from a
  /// hand-tuned constant that silently drifts when the card changes.
  static double heightFor({required bool compact, int? subtitleMaxLines}) {
    return (compact ? _compactImageHeight : _imageHeight) +
        2 * (compact ? _compactTextPaddingY : _textPaddingY) +
        2 * _borderWidth +
        _textAreaHeight(compact, subtitleMaxLines);
  }

  /// The text block grows with the name and subtitle type sizes: both are
  /// fixed-line-count boxes, so a size bump has to be paid for here or the
  /// column overflows the card.
  static double _textAreaHeight(bool compact, int? subtitleMaxLines) {
    if (compact) return 100;
    return (subtitleMaxLines ?? 3) > 2 ? 124 : 102;
  }

  @override
  Widget build(BuildContext context) {
    final cardTags = product.cardTagDetails;
    final showAdd = onAdd != null;
    final orderable =
        product.availability.isOrderable && product.defaultVariant != null;
    final cleanSubtitleOverride = subtitleOverride?.trim();
    final subtitleText =
        cleanSubtitleOverride != null && cleanSubtitleOverride.isNotEmpty
        ? cleanSubtitleOverride
        : product.subtitle;
    final effectiveSubtitleMaxLines = subtitleMaxLines ?? (compact ? 2 : 3);

    final textAreaHeight = _textAreaHeight(compact, subtitleMaxLines);

    return SizedBox(
      width: width,
      child: Material(
        color: Colors.transparent,
        child: InkWell(
          onTap: onTap,
          borderRadius: BorderRadius.circular(18),
          child: Ink(
            decoration: BoxDecoration(
              color: EbtlColors.white.withValues(alpha: 0.94),
              borderRadius: BorderRadius.circular(18),
              border: Border.all(
                color: EbtlColors.border,
                width: _borderWidth,
              ),
              boxShadow: [
                BoxShadow(
                  color: Colors.black.withValues(alpha: 0.035),
                  blurRadius: 14,
                  offset: const Offset(0, 8),
                ),
              ],
            ),
            child: ClipRRect(
              borderRadius: BorderRadius.circular(18),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  SizedBox(
                    height: compact ? _compactImageHeight : _imageHeight,
                    width: double.infinity,
                    child: Stack(
                      children: [
                        Positioned.fill(
                          child: NetworkOrAssetImage(
                            imageUrl: product.imageUrl,
                            asset: product.imageAsset,
                            fit: BoxFit.cover,
                          ),
                        ),
                        // A product may carry several tags; the card badges
                        // every one an admin marked for the card, and the
                        // compact card has no room for any of them.
                        if (cardTags.isNotEmpty && !compact)
                          Positioned(
                            left: 8,
                            top: 8,
                            right: 8,
                            child: Wrap(
                              spacing: 5,
                              runSpacing: 5,
                              children: cardTags
                                  .map((tag) => ProductTagBadge(tag: tag))
                                  .toList(),
                            ),
                          ),
                      ],
                    ),
                  ),
                  Padding(
                    padding: EdgeInsets.fromLTRB(
                      compact ? 9 : 12,
                      compact ? _compactTextPaddingY : _textPaddingY,
                      compact ? 9 : 10,
                      compact ? _compactTextPaddingY : _textPaddingY,
                    ),
                    child: SizedBox(
                      height: textAreaHeight,
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text(
                            product.name,
                            maxLines: compact ? 3 : 2,
                            overflow: TextOverflow.ellipsis,
                            style: GoogleFonts.manrope(
                              fontSize: compact ? 10 : 12,
                              height: 1.15,
                              fontWeight: FontWeight.w900,
                              color: EbtlColors.navy,
                            ),
                          ),
                          const SizedBox(height: 5),
                          Text(
                            subtitleText,
                            maxLines: effectiveSubtitleMaxLines,
                            overflow: TextOverflow.ellipsis,
                            style: GoogleFonts.manrope(
                              fontSize: compact ? 9 : 11,
                              height: 1.22,
                              fontWeight: FontWeight.w700,
                              color: EbtlColors.muted,
                            ),
                          ),
                          const Spacer(),
                          Row(
                            children: [
                              Expanded(
                                child: Text(
                                  product.priceLabel,
                                  maxLines: 1,
                                  overflow: TextOverflow.ellipsis,
                                  style: GoogleFonts.manrope(
                                    fontSize: compact ? 11 : 14,
                                    fontWeight: FontWeight.w900,
                                    color: EbtlColors.navy,
                                  ),
                                ),
                              ),
                              if (showAdd)
                                SizedBox(
                                  width: compact ? 30 : 36,
                                  height: compact ? 30 : 36,
                                  child: Material(
                                    color: orderable
                                        ? EbtlColors.blush.withValues(
                                            alpha: 0.65,
                                          )
                                        : EbtlColors.sand,
                                    shape: const CircleBorder(),
                                    child: InkWell(
                                      customBorder: const CircleBorder(),
                                      onTap: isAdding ? null : onAdd,
                                      child: Center(
                                        child: isAdding
                                            ? const SizedBox(
                                                width: 14,
                                                height: 14,
                                                child:
                                                    CircularProgressIndicator(
                                                      strokeWidth: 2,
                                                      color: EbtlColors.coral,
                                                    ),
                                              )
                                            : Icon(
                                                Icons.add,
                                                size: compact ? 18 : 22,
                                                color: orderable
                                                    ? EbtlColors.coral
                                                    : EbtlColors.muted,
                                              ),
                                      ),
                                    ),
                                  ),
                                ),
                            ],
                          ),
                        ],
                      ),
                    ),
                  ),
                ],
              ),
            ),
          ),
        ),
      ),
    );
  }
}
