import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';

import '../../../core/theme/ebtl_colors.dart';
import '../../../models/shop_models.dart';
import '../../../shared/widgets/network_or_asset_image.dart';
import '../catalog_search.dart';

/// The floating card the search results hang in, under the field they belong
/// to. Solid white with a shadow — it sits over whatever the screen was
/// already showing rather than replacing it.
class SearchDropdownCard extends StatelessWidget {
  final Widget child;

  const SearchDropdownCard({super.key, required this.child});

  @override
  Widget build(BuildContext context) {
    return Container(
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
      child: child,
    );
  }
}

/// A line of text inside the dropdown — nothing matched, or the catalog could
/// not be loaded — with an optional action under it.
class SearchDropdownMessage extends StatelessWidget {
  final String message;
  final String? actionLabel;
  final VoidCallback? onAction;

  const SearchDropdownMessage({
    super.key,
    required this.message,
    this.actionLabel,
    this.onAction,
  });

  @override
  Widget build(BuildContext context) {
    final label = actionLabel;
    final action = onAction;

    return Padding(
      padding: const EdgeInsets.all(18),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        mainAxisSize: MainAxisSize.min,
        children: [
          Text(
            message,
            style: GoogleFonts.manrope(
              fontSize: 13,
              height: 1.35,
              fontWeight: FontWeight.w700,
              color: EbtlColors.muted,
            ),
          ),
          if (label != null && action != null) ...[
            const SizedBox(height: 10),
            InkWell(
              onTap: action,
              child: Text(
                label,
                style: GoogleFonts.manrope(
                  fontSize: 13,
                  fontWeight: FontWeight.w900,
                  color: EbtlColors.coral,
                ),
              ),
            ),
          ],
        ],
      ),
    );
  }
}

/// Hangs [child] off the search field [link] is attached to, floating over the
/// page. Drop it into a [Stack] laid over the screen's own content.
///
/// Anchoring to the field rather than to the page means the dropdown follows a
/// field that scrolls — as Explore's does — and disappears with it.
class SearchResultsDropdown extends StatelessWidget {
  /// The gutter both screens lay their pages out on, and so the width of the
  /// search field the dropdown lines up with.
  static const double _pageGutter = 22;

  /// The gap between the bottom of the field and the top of the card.
  static const double _gap = 8;

  final LayerLink link;
  final Widget child;

  const SearchResultsDropdown({
    super.key,
    required this.link,
    required this.child,
  });

  @override
  Widget build(BuildContext context) {
    return Positioned(
      left: 0,
      top: 0,
      child: CompositedTransformFollower(
        link: link,
        showWhenUnlinked: false,
        targetAnchor: Alignment.bottomLeft,
        followerAnchor: Alignment.topLeft,
        offset: const Offset(0, _gap),
        child: SizedBox(
          width: MediaQuery.sizeOf(context).width - _pageGutter * 2,
          child: child,
        ),
      ),
    );
  }
}

/// The dropdown of everything a query matched: products first, then the
/// categories, tags and ingredients that open a collection of their own.
///
/// Shared by Home and Explore — both drop it straight under their search
/// field while a query is applied.
class SearchResultsPanel extends StatelessWidget {
  final SearchCatalog catalog;
  final SearchResults results;
  final ValueChanged<ShopProduct> onOpenProduct;

  /// Opens a named collection — a category, tag or ingredient — as its own
  /// screen of matching products.
  final void Function(String title, List<ShopProduct> products)
  onOpenCollection;

  const SearchResultsPanel({
    super.key,
    required this.catalog,
    required this.results,
    required this.onOpenProduct,
    required this.onOpenCollection,
  });

  @override
  Widget build(BuildContext context) {
    if (results.isEmpty) {
      return const SearchDropdownCard(
        child: SearchDropdownMessage(
          message: 'No matches found. Try a different search.',
        ),
      );
    }

    return SearchDropdownCard(
      child: ListView(
        shrinkWrap: true,
        padding: EdgeInsets.zero,
        children: [
          ...results.products.map(
            (product) => SearchResultRow(
              label: product.name,
              typeLabel: product.productTypeLabel,
              product: product,
              onTap: () => onOpenProduct(product),
            ),
          ),
          ...results.categories.map(
            (category) => SearchResultRow(
              label: category.name,
              typeLabel: 'Category',
              onTap: () => onOpenCollection(
                category.name,
                catalog.productsFor(category.id),
              ),
            ),
          ),
          ...results.tags.map(
            (tag) => SearchResultRow(
              label: tag,
              typeLabel: 'Tag',
              onTap: () => onOpenCollection(tag, catalog.productsWithTag(tag)),
            ),
          ),
          ...results.ingredients.map(
            (ingredient) => SearchResultRow(
              label: ingredient,
              typeLabel: 'Ingredient',
              onTap: () => onOpenCollection(
                ingredient,
                catalog.productsWithIngredient(ingredient),
              ),
            ),
          ),
        ],
      ),
    );
  }
}

/// One row of the dropdown: the kind of thing it is, its name, and either the
/// product's image or the chevron that says it opens a collection.
class SearchResultRow extends StatelessWidget {
  final String label;
  final String typeLabel;
  final ShopProduct? product;
  final VoidCallback onTap;

  const SearchResultRow({
    super.key,
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
              const Icon(Icons.chevron_right_rounded, color: EbtlColors.muted),
          ],
        ),
      ),
    );
  }
}
