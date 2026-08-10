import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';

import '../../../core/theme/ebtl_colors.dart';
import '../../../models/shop_models.dart';
import '../../../shared/widgets/app_state_widgets.dart';
import '../../../shared/widgets/network_or_asset_image.dart';
import '../catalog_search.dart';

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
      return const EmptyStateCard(
        message: 'No matches found. Try a different search.',
      );
    }

    return Container(
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
