import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';

import '../../../core/theme/ebtl_colors.dart';
import '../../../models/shop_models.dart';
import '../../../shared/widgets/network_or_asset_image.dart';

/// Horizontal category filter for the Explore grid. Unlike the shop's category
/// rail these badges are fully server-driven and filter the grid in place —
/// a category added in the dashboard shows up here on its own.
class ExploreCategoryBadges extends StatelessWidget {
  /// Categories that actually have products, in server order.
  final List<ShopCategory> categories;

  /// Product count per category id, used for the badge counter.
  final Map<String, int> productCounts;

  /// Null means "All".
  final String? selectedCategoryId;

  final int totalProductCount;
  final ValueChanged<String?> onSelect;

  const ExploreCategoryBadges({
    super.key,
    required this.categories,
    required this.productCounts,
    required this.selectedCategoryId,
    required this.totalProductCount,
    required this.onSelect,
  });

  @override
  Widget build(BuildContext context) {
    if (categories.isEmpty) {
      return const SizedBox.shrink();
    }

    return SizedBox(
      height: 56,
      child: ListView.separated(
        scrollDirection: Axis.horizontal,
        padding: const EdgeInsets.symmetric(horizontal: 22),
        itemCount: categories.length + 1,
        separatorBuilder: (_, _) => const SizedBox(width: 10),
        itemBuilder: (context, index) {
          if (index == 0) {
            return ExploreCategoryBadge(
              label: 'All',
              count: totalProductCount,
              imageUrl: null,
              selected: selectedCategoryId == null,
              onTap: () => onSelect(null),
            );
          }

          final category = categories[index - 1];

          return ExploreCategoryBadge(
            label: category.name,
            count: productCounts[category.id] ?? 0,
            imageUrl: category.imageUrl,
            selected: selectedCategoryId == category.id,
            onTap: () => onSelect(category.id),
          );
        },
      ),
    );
  }
}

class ExploreCategoryBadge extends StatelessWidget {
  final String label;
  final int count;
  final String? imageUrl;
  final bool selected;
  final VoidCallback onTap;

  const ExploreCategoryBadge({
    super.key,
    required this.label,
    required this.count,
    required this.imageUrl,
    required this.selected,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    final hasImage = imageUrl != null && imageUrl!.trim().isNotEmpty;

    return Semantics(
      button: true,
      selected: selected,
      child: InkWell(
        onTap: onTap,
        borderRadius: BorderRadius.circular(999),
        child: AnimatedContainer(
          duration: const Duration(milliseconds: 160),
          height: 46,
          padding: hasImage
              ? const EdgeInsets.fromLTRB(7, 7, 14, 7)
              : const EdgeInsets.symmetric(horizontal: 16, vertical: 7),
          decoration: BoxDecoration(
            color: selected
                ? EbtlColors.blush.withValues(alpha: 0.55)
                : EbtlColors.white.withValues(alpha: 0.88),
            borderRadius: BorderRadius.circular(999),
            border: Border.all(
              color: selected ? EbtlColors.coral : EbtlColors.border,
              width: selected ? 1.3 : 1,
            ),
            boxShadow: [
              BoxShadow(
                color: Colors.black.withValues(alpha: 0.035),
                blurRadius: 12,
                offset: const Offset(0, 6),
              ),
            ],
          ),
          child: Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              if (hasImage) ...[
                ClipOval(
                  child: SizedBox(
                    width: 32,
                    height: 32,
                    child: NetworkOrAssetImage(
                      imageUrl: imageUrl,
                      asset: 'assets/images/cocktail_placeholder.jpg',
                      fit: BoxFit.cover,
                    ),
                  ),
                ),
                const SizedBox(width: 7),
              ],
              Text(
                label,
                style: GoogleFonts.manrope(
                  fontSize: 11,
                  fontWeight: FontWeight.w900,
                  color: EbtlColors.navy,
                ),
              ),
              const SizedBox(width: 6),
              Text(
                count.toString(),
                style: GoogleFonts.manrope(
                  fontSize: 10,
                  fontWeight: FontWeight.w700,
                  color: selected ? EbtlColors.ink : EbtlColors.muted,
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}
