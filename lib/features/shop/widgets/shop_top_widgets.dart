import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';

import '../../../core/theme/ebtl_colors.dart';
import '../../../models/shop_models.dart';
import '../../../shared/widgets/brand_widgets.dart';
import '../../../shared/widgets/network_or_asset_image.dart';

class ShopHeader extends StatelessWidget {
  final int cartQuantity;
  final VoidCallback? onSearch;
  final VoidCallback onOpenCart;

  const ShopHeader({
    super.key,
    required this.cartQuantity,
    required this.onSearch,
    required this.onOpenCart,
  });

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.fromLTRB(22, 14, 22, 10),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  'Shop',
                  style: GoogleFonts.playfairDisplay(
                    fontSize: 42,
                    height: 1.0,
                    fontWeight: FontWeight.w800,
                    color: EbtlColors.navy,
                  ),
                ),
                const SizedBox(height: 9),
                Text(
                  'Everything you need for',
                  style: GoogleFonts.manrope(
                    fontSize: 15,
                    height: 1.25,
                    fontWeight: FontWeight.w700,
                    color: EbtlColors.navy,
                    letterSpacing: 0.4,
                  ),
                ),
                Text(
                  'perfect cocktails.',
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
          CircleIconButton(icon: Icons.search, onTap: onSearch ?? () {}),
          const SizedBox(width: 12),
          ShopCartIconButton(count: cartQuantity, onTap: onOpenCart),
        ],
      ),
    );
  }
}

class ShopCartIconButton extends StatelessWidget {
  final int count;
  final VoidCallback onTap;

  const ShopCartIconButton({
    super.key,
    required this.count,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    return Stack(
      clipBehavior: Clip.none,
      children: [
        CircleIconButton(icon: Icons.shopping_cart_outlined, onTap: onTap),
        if (count > 0)
          Positioned(
            right: -2,
            top: -4,
            child: Container(
              padding: const EdgeInsets.all(6),
              decoration: const BoxDecoration(
                color: EbtlColors.coral,
                shape: BoxShape.circle,
              ),
              child: Text(
                count > 99 ? '99+' : count.toString(),
                style: const TextStyle(
                  color: Colors.white,
                  fontSize: 11,
                  fontWeight: FontWeight.w800,
                ),
              ),
            ),
          ),
      ],
    );
  }
}

class _ShopFilterDefinition {
  final String target;
  final String label;
  final String assetPath;

  const _ShopFilterDefinition({
    required this.target,
    required this.label,
    required this.assetPath,
  });

  static const defaults = [
    _ShopFilterDefinition(
      target: 'cocktails',
      label: 'Cocktails',
      assetPath: 'assets/images/filters/cocktails.webp',
    ),
    _ShopFilterDefinition(
      target: 'snacks',
      label: 'Snacks',
      assetPath: 'assets/images/filters/snacks.webp',
    ),
    _ShopFilterDefinition(
      target: 'essentials',
      label: 'Essentials',
      assetPath: 'assets/images/filters/essentials.webp',
    ),
  ];
}

class _ShopFilterItem {
  final _ShopFilterDefinition filter;
  final ShopCategory category;

  const _ShopFilterItem({required this.filter, required this.category});
}

class ShopCategoryRail extends StatelessWidget {
  final List<ShopCategory> categories;
  final ValueChanged<ShopCategory> onTap;

  const ShopCategoryRail({
    super.key,
    required this.categories,
    required this.onTap,
  });

  String singularTarget(String target) {
    final clean = target.trim().toLowerCase();

    if (clean.endsWith('ies') && clean.length > 3) {
      return '${clean.substring(0, clean.length - 3)}y';
    }

    if (clean.endsWith('s') && clean.length > 1) {
      return clean.substring(0, clean.length - 1);
    }

    return clean;
  }

  ShopCategory? categoryForFilter(String target) {
    final cleanTarget = target.trim().toLowerCase();
    final singular = singularTarget(cleanTarget);

    for (final category in categories) {
      final slug = category.slug?.trim().toLowerCase() ?? '';
      final name = category.name.trim().toLowerCase();

      if (slug == cleanTarget ||
          slug == singular ||
          name == cleanTarget ||
          name == singular) {
        return category;
      }
    }

    for (final category in categories) {
      final slug = category.slug?.trim().toLowerCase() ?? '';
      final name = category.name.trim().toLowerCase();

      if (slug.contains(cleanTarget) ||
          slug.contains(singular) ||
          name.contains(cleanTarget) ||
          name.contains(singular)) {
        return category;
      }
    }

    return null;
  }

  @override
  Widget build(BuildContext context) {
    final filters = _ShopFilterDefinition.defaults
        .map((filter) {
          final category = categoryForFilter(filter.target);
          if (category == null) return null;

          return _ShopFilterItem(filter: filter, category: category);
        })
        .whereType<_ShopFilterItem>()
        .toList();

    if (filters.isEmpty) {
      return const SizedBox.shrink();
    }

    return SizedBox(
      height: 70,
      child: ListView.separated(
        padding: const EdgeInsets.fromLTRB(22, 8, 22, 10),
        scrollDirection: Axis.horizontal,
        itemCount: filters.length,
        separatorBuilder: (_, _) => const SizedBox(width: 10),
        itemBuilder: (context, index) {
          final item = filters[index];

          return ShopCategoryPill(
            label: item.filter.label,
            assetPath: item.filter.assetPath,
            selected: index == 0,
            onTap: () => onTap(item.category),
          );
        },
      ),
    );
  }
}

class ShopCategoryPill extends StatelessWidget {
  final String label;
  final String assetPath;
  final bool selected;
  final VoidCallback onTap;

  const ShopCategoryPill({
    super.key,
    required this.label,
    required this.assetPath,
    required this.selected,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    return Material(
      color: Colors.transparent,
      child: InkWell(
        onTap: onTap,
        borderRadius: BorderRadius.circular(999),
        child: AnimatedContainer(
          duration: const Duration(milliseconds: 180),
          height: 52,
          padding: const EdgeInsets.fromLTRB(8, 7, 16, 7),
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
              ClipOval(
                child: SizedBox(
                  width: 38,
                  height: 38,
                  child: Image.asset(
                    assetPath,
                    fit: BoxFit.cover,
                    errorBuilder: (_, _, _) {
                      return Container(
                        color: EbtlColors.sand,
                        child: Icon(
                          Icons.shopping_bag_outlined,
                          color: selected ? EbtlColors.coral : EbtlColors.navy,
                          size: 20,
                        ),
                      );
                    },
                  ),
                ),
              ),
              const SizedBox(width: 9),
              Text(
                label,
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                style: GoogleFonts.manrope(
                  fontSize: 13,
                  fontWeight: FontWeight.w900,
                  color: selected ? EbtlColors.coral : EbtlColors.navy,
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

class ShopBannerCard extends StatelessWidget {
  final String? imageUrl;
  final VoidCallback onTap;

  const ShopBannerCard({
    super.key,
    required this.imageUrl,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.fromLTRB(22, 8, 22, 18),
      child: InkWell(
        onTap: onTap,
        borderRadius: BorderRadius.circular(20),
        child: ClipRRect(
          borderRadius: BorderRadius.circular(20),
          child: SizedBox(
            height: 142,
            width: double.infinity,
            child: Stack(
              children: [
                Positioned.fill(
                  child: NetworkOrAssetImage(
                    imageUrl: imageUrl,
                    asset: 'assets/images/home_hero.jpg',
                    fit: BoxFit.cover,
                  ),
                ),
                Positioned.fill(
                  child: DecoratedBox(
                    decoration: BoxDecoration(
                      gradient: LinearGradient(
                        colors: [
                          EbtlColors.cream.withValues(alpha: 0.95),
                          EbtlColors.cream.withValues(alpha: 0.58),
                          Colors.transparent,
                        ],
                        stops: const [0, 0.48, 1],
                      ),
                    ),
                  ),
                ),
                Positioned(
                  left: 20,
                  top: 20,
                  bottom: 18,
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        'Beach day essential?',
                        style: GoogleFonts.playfairDisplay(
                          fontSize: 21,
                          fontWeight: FontWeight.w800,
                          color: EbtlColors.navy,
                        ),
                      ),
                      const SizedBox(height: 8),
                      Text(
                        "We've got you.",
                        style: GoogleFonts.manrope(
                          fontSize: 15,
                          fontWeight: FontWeight.w800,
                          color: EbtlColors.navy,
                        ),
                      ),
                      const Spacer(),
                      Container(
                        height: 42,
                        padding: const EdgeInsets.symmetric(horizontal: 16),
                        alignment: Alignment.center,
                        decoration: BoxDecoration(
                          color: EbtlColors.navy,
                          borderRadius: BorderRadius.circular(12),
                        ),
                        child: Text(
                          'Shop Essentials',
                          style: GoogleFonts.manrope(
                            fontSize: 13,
                            fontWeight: FontWeight.w900,
                            color: Colors.white,
                          ),
                        ),
                      ),
                    ],
                  ),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}
