import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';

import '../../../core/theme/ebtl_colors.dart';
import '../../../core/theme/home_screen_visuals.dart';
import '../../../models/common_models.dart';
import '../../../models/profile_models.dart';
import '../../../shared/widgets/multiply_blend.dart';
import '../../../shared/widgets/network_or_asset_image.dart';

/// Section header used by every rail on Home: a Manrope title with an optional
/// subtitle underneath and an optional "View all" action on the right.
class HomeSectionHeader extends StatelessWidget {
  final String title;
  final String? subtitle;
  final String? actionLabel;
  final VoidCallback? onAction;

  const HomeSectionHeader({
    super.key,
    required this.title,
    this.subtitle,
    this.actionLabel,
    this.onAction,
  });

  @override
  Widget build(BuildContext context) {
    final action = actionLabel;

    return Padding(
      padding: const EdgeInsets.fromLTRB(22, 0, 22, 14),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  title,
                  style: GoogleFonts.manrope(
                    fontSize: 18,
                    height: 1.2,
                    fontWeight: FontWeight.w900,
                    color: EbtlColors.navy,
                  ),
                ),
                if (subtitle != null) ...[
                  const SizedBox(height: 2),
                  Text(
                    subtitle!,
                    style: GoogleFonts.manrope(
                      fontSize: 13,
                      height: 1.3,
                      fontWeight: FontWeight.w500,
                      color: EbtlColors.muted,
                    ),
                  ),
                ],
              ],
            ),
          ),
          if (action != null)
            GestureDetector(
              behavior: HitTestBehavior.opaque,
              onTap: onAction,
              child: Padding(
                padding: const EdgeInsets.only(left: 12, top: 2, bottom: 6),
                child: Row(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Text(
                      action,
                      style: GoogleFonts.manrope(
                        fontSize: 13.5,
                        fontWeight: FontWeight.w800,
                        color: EbtlColors.teal,
                      ),
                    ),
                    const Icon(
                      Icons.chevron_right_rounded,
                      size: 17,
                      color: EbtlColors.teal,
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

/// The navy tracker that opens Home while an order is still being made.
class HomeLiveOrderCard extends StatelessWidget {
  /// Paid → mixing → ready → collected, drawn as unlabelled progress segments.
  static const int _stageCount = 4;

  final ProfileOrder order;
  final VoidCallback onTap;

  const HomeLiveOrderCard({
    super.key,
    required this.order,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    final completedSteps = order.liveProgressStep;

    return Padding(
      padding: const EdgeInsets.fromLTRB(22, 0, 22, 14),
      child: Material(
        color: EbtlColors.navy,
        borderRadius: BorderRadius.circular(20),
        elevation: 0,
        child: InkWell(
          onTap: onTap,
          borderRadius: BorderRadius.circular(20),
          child: Ink(
            decoration: BoxDecoration(
              color: EbtlColors.navy,
              borderRadius: BorderRadius.circular(20),
              boxShadow: [
                BoxShadow(
                  color: EbtlColors.navy.withValues(alpha: 0.18),
                  blurRadius: 22,
                  offset: const Offset(0, 10),
                ),
              ],
            ),
            child: Padding(
              padding: const EdgeInsets.all(16),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Row(
                    children: [
                      Container(
                        width: 8,
                        height: 8,
                        decoration: const BoxDecoration(
                          color: EbtlColors.gold,
                          shape: BoxShape.circle,
                        ),
                      ),
                      const SizedBox(width: 8),
                      Expanded(
                        child: Text(
                          order.liveStatusLabel,
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                          style: GoogleFonts.manrope(
                            fontSize: 11,
                            fontWeight: FontWeight.w900,
                            letterSpacing: 1.4,
                            color: EbtlColors.gold,
                          ),
                        ),
                      ),
                      const SizedBox(width: 8),
                      Text(
                        order.liveEtaLabel,
                        style: GoogleFonts.manrope(
                          fontSize: 13,
                          fontWeight: FontWeight.w800,
                          color: EbtlColors.white.withValues(alpha: 0.75),
                        ),
                      ),
                    ],
                  ),
                  const SizedBox(height: 12),
                  Row(
                    children: [
                      _Thumb(
                        size: 64,
                        radius: 16,
                        background: EbtlColors.cream,
                        imageUrl: order.orderImageUrl,
                        name: order.primaryItem?.name ?? order.displayLocation,
                      ),
                      const SizedBox(width: 14),
                      Expanded(
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Text(
                              order.displayItemsSummary,
                              maxLines: 1,
                              overflow: TextOverflow.ellipsis,
                              style: GoogleFonts.playfairDisplay(
                                fontSize: 19,
                                height: 1.2,
                                fontWeight: FontWeight.w700,
                                color: EbtlColors.white,
                              ),
                            ),
                            const SizedBox(height: 3),
                            Text(
                              '${order.displayLocation} · ${order.displayTotal}',
                              maxLines: 1,
                              overflow: TextOverflow.ellipsis,
                              style: GoogleFonts.manrope(
                                fontSize: 13,
                                fontWeight: FontWeight.w600,
                                color: EbtlColors.seafoam,
                              ),
                            ),
                          ],
                        ),
                      ),
                    ],
                  ),
                  const SizedBox(height: 14),
                  Row(
                    children: [
                      for (var step = 0; step < _stageCount; step++) ...[
                        if (step > 0) const SizedBox(width: 5),
                        Expanded(
                          child: Container(
                            height: 4,
                            decoration: BoxDecoration(
                              color: step < completedSteps
                                  ? EbtlColors.coral
                                  : EbtlColors.white.withValues(alpha: 0.2),
                              borderRadius: BorderRadius.circular(999),
                            ),
                          ),
                        ),
                      ],
                    ],
                  ),
                  const SizedBox(height: 12),
                  Row(
                    mainAxisAlignment: MainAxisAlignment.end,
                    children: [
                      Text(
                        'Track order',
                        style: GoogleFonts.manrope(
                          fontSize: 13.5,
                          fontWeight: FontWeight.w900,
                          color: EbtlColors.coral,
                        ),
                      ),
                      const Icon(
                        Icons.chevron_right_rounded,
                        size: 17,
                        color: EbtlColors.coral,
                      ),
                    ],
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

/// The blush pill that offers the open cart back to the customer. Hidden when
/// the cart is empty.
class HomeCartResumeBar extends StatelessWidget {
  final int itemCount;
  final String totalLabel;
  final VoidCallback onTap;

  const HomeCartResumeBar({
    super.key,
    required this.itemCount,
    required this.totalLabel,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    final itemsLabel = itemCount == 1 ? '1 item' : '$itemCount items';

    return Padding(
      padding: const EdgeInsets.fromLTRB(22, 0, 22, 22),
      child: Material(
        color: EbtlColors.blush,
        borderRadius: BorderRadius.circular(999),
        child: InkWell(
          onTap: onTap,
          borderRadius: BorderRadius.circular(999),
          child: Padding(
            padding: const EdgeInsets.symmetric(horizontal: 18, vertical: 12),
            child: Row(
              children: [
                const Icon(
                  Icons.shopping_cart_outlined,
                  size: 17,
                  color: EbtlColors.navy,
                ),
                const SizedBox(width: 10),
                Expanded(
                  child: Text(
                    '$itemsLabel · $totalLabel in your cart',
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: GoogleFonts.manrope(
                      fontSize: 13.5,
                      fontWeight: FontWeight.w800,
                      color: EbtlColors.navy,
                    ),
                  ),
                ),
                const SizedBox(width: 8),
                Text(
                  'Checkout',
                  style: GoogleFonts.manrope(
                    fontSize: 13.5,
                    fontWeight: FontWeight.w900,
                    color: EbtlColors.coral,
                  ),
                ),
                const Icon(
                  Icons.chevron_right_rounded,
                  size: 17,
                  color: EbtlColors.coral,
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}

/// One card in the "Order It Again" rail: a past order, its price, and a plus
/// that puts the same kit back in the cart.
class HomeOrderAgainCard extends StatelessWidget {
  final ProfileOrder order;
  final VoidCallback onTap;
  final VoidCallback onAddAgain;
  final bool isAdding;

  const HomeOrderAgainCard({
    super.key,
    required this.order,
    required this.onTap,
    required this.onAddAgain,
    required this.isAdding,
  });

  @override
  Widget build(BuildContext context) {
    return SizedBox(
      width: HomeScreenVisuals.orderAgainCardWidth,
      child: Material(
        color: EbtlColors.white,
        borderRadius: BorderRadius.circular(18),
        child: InkWell(
          onTap: onTap,
          borderRadius: BorderRadius.circular(18),
          child: Ink(
            decoration: BoxDecoration(
              color: EbtlColors.white,
              borderRadius: BorderRadius.circular(18),
              border: Border.all(color: EbtlColors.border),
              boxShadow: [
                BoxShadow(
                  color: Colors.black.withValues(alpha: 0.04),
                  blurRadius: 18,
                  offset: const Offset(0, 8),
                ),
              ],
            ),
            child: Padding(
              padding: const EdgeInsets.all(10),
              child: Row(
                children: [
                  _Thumb(
                    size: 56,
                    radius: 14,
                    background: EbtlColors.sand,
                    imageUrl: order.orderImageUrl,
                    name: order.primaryItem?.name ?? order.displayLocation,
                  ),
                  const SizedBox(width: 12),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        Text(
                          order.displayItemsSummary,
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                          style: GoogleFonts.playfairDisplay(
                            fontSize: 16,
                            height: 1.2,
                            fontWeight: FontWeight.w700,
                            color: EbtlColors.navy,
                          ),
                        ),
                        const SizedBox(height: 2),
                        Text(
                          order.orderedAgoLabel,
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                          style: GoogleFonts.manrope(
                            fontSize: 12.5,
                            height: 1.2,
                            fontWeight: FontWeight.w700,
                            color: EbtlColors.muted,
                          ),
                        ),
                        const SizedBox(height: 4),
                        Text(
                          order.displayTotal,
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                          style: GoogleFonts.manrope(
                            fontSize: 14,
                            height: 1.2,
                            fontWeight: FontWeight.w900,
                            color: EbtlColors.coral,
                          ),
                        ),
                      ],
                    ),
                  ),
                  const SizedBox(width: 12),
                  _CircleAction(
                    size: 36,
                    color: EbtlColors.coral,
                    onTap: isAdding ? null : onAddAgain,
                    child: isAdding
                        ? const SizedBox(
                            width: 16,
                            height: 16,
                            child: CircularProgressIndicator(
                              strokeWidth: 2.2,
                              color: EbtlColors.white,
                            ),
                          )
                        : const Icon(
                            Icons.add_rounded,
                            size: 18,
                            color: EbtlColors.white,
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

/// The category rail. Selection is local to Home; tapping also opens the
/// category in Shop.
class HomeCategoryChips extends StatelessWidget {
  final List<Category> categories;
  final String? selectedCategoryId;
  final ValueChanged<Category> onSelect;

  const HomeCategoryChips({
    super.key,
    required this.categories,
    required this.selectedCategoryId,
    required this.onSelect,
  });

  @override
  Widget build(BuildContext context) {
    return SizedBox(
      height: 40,
      child: ListView.separated(
        scrollDirection: Axis.horizontal,
        padding: const EdgeInsets.symmetric(horizontal: 22),
        itemCount: categories.length,
        separatorBuilder: (_, _) => const SizedBox(width: 8),
        itemBuilder: (context, index) {
          final category = categories[index];
          final selected = category.id == selectedCategoryId;

          return GestureDetector(
            behavior: HitTestBehavior.opaque,
            onTap: () => onSelect(category),
            child: AnimatedContainer(
              duration: const Duration(milliseconds: 180),
              curve: Curves.ease,
              padding: const EdgeInsets.symmetric(horizontal: 16),
              alignment: Alignment.center,
              decoration: BoxDecoration(
                color: selected ? EbtlColors.navy : EbtlColors.white,
                borderRadius: BorderRadius.circular(999),
                border: Border.all(
                  color: selected ? EbtlColors.navy : EbtlColors.border,
                ),
              ),
              child: Text(
                category.name,
                style: GoogleFonts.manrope(
                  fontSize: 13,
                  fontWeight: FontWeight.w800,
                  color: selected ? EbtlColors.white : EbtlColors.navy,
                ),
              ),
            ),
          );
        },
      ),
    );
  }
}

/// Closes the first-run screen with the shop-only path, for customers who have
/// no bottle to build a kit around yet.
class HomeNoBottlePanel extends StatelessWidget {
  final VoidCallback onTap;

  const HomeNoBottlePanel({super.key, required this.onTap});

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.fromLTRB(22, 26, 22, 0),
      child: Material(
        color: EbtlColors.navy,
        borderRadius: BorderRadius.circular(20),
        child: InkWell(
          onTap: onTap,
          borderRadius: BorderRadius.circular(20),
          child: Padding(
            padding: const EdgeInsets.all(18),
            child: Row(
              children: [
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        'No bottle yet?',
                        style: GoogleFonts.playfairDisplay(
                          fontSize: 19,
                          height: 1.2,
                          fontWeight: FontWeight.w700,
                          color: EbtlColors.white,
                        ),
                      ),
                      const SizedBox(height: 4),
                      Text(
                        'Browse mixers, snacks and beach essentials on their '
                        'own.',
                        style: GoogleFonts.manrope(
                          fontSize: 13,
                          height: 1.4,
                          fontWeight: FontWeight.w500,
                          color: EbtlColors.seafoam,
                        ),
                      ),
                    ],
                  ),
                ),
                const SizedBox(width: 14),
                _CircleAction(
                  size: 44,
                  color: EbtlColors.coral,
                  onTap: onTap,
                  child: const Icon(
                    Icons.chevron_right_rounded,
                    size: 22,
                    color: EbtlColors.white,
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

/// A product thumbnail on a tinted well: contained artwork, multiplied so
/// photography shot on white does not draw a box over the tint.
class _Thumb extends StatelessWidget {
  final double size;
  final double radius;
  final Color background;
  final String? imageUrl;
  final String name;

  const _Thumb({
    required this.size,
    required this.radius,
    required this.background,
    required this.imageUrl,
    required this.name,
  });

  @override
  Widget build(BuildContext context) {
    return Container(
      width: size,
      height: size,
      decoration: BoxDecoration(
        color: background,
        borderRadius: BorderRadius.circular(radius),
      ),
      child: ClipRRect(
        borderRadius: BorderRadius.circular(radius),
        child: MultiplyBlend(
          child: Padding(
            padding: EdgeInsets.all(size * 0.06),
            child: NetworkOrAssetImage(
              imageUrl: imageUrl,
              asset: 'assets/images/cocktail_placeholder.jpg',
              fit: BoxFit.contain,
              fallback: Center(
                child: Icon(
                  Icons.local_bar_outlined,
                  size: size * 0.42,
                  color: EbtlColors.navy,
                ),
              ),
            ),
          ),
        ),
      ),
    );
  }
}

class _CircleAction extends StatelessWidget {
  final double size;
  final Color color;
  final VoidCallback? onTap;
  final Widget child;

  const _CircleAction({
    required this.size,
    required this.color,
    required this.onTap,
    required this.child,
  });

  @override
  Widget build(BuildContext context) {
    return Material(
      color: color,
      shape: const CircleBorder(),
      child: InkWell(
        onTap: onTap,
        customBorder: const CircleBorder(),
        child: SizedBox(
          width: size,
          height: size,
          child: Center(child: child),
        ),
      ),
    );
  }
}
