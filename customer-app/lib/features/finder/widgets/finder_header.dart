import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';

import '../../../core/theme/ebtl_colors.dart';
import '../../../core/utils/model_sorters.dart';
import '../../../models/common_models.dart';
import '../../../shared/widgets/bottle_widgets.dart';
import '../../../shared/widgets/brand_widgets.dart';
import '../../../shared/widgets/network_or_asset_image.dart';

class FinderHeader extends StatelessWidget {
  final List<LiquorType> liquorTypes;
  final Set<String> selectedLiquorTypeIds;
  final ValueChanged<String> onToggle;
  final VoidCallback onClear;

  /// Replaces the logo with a back button when the Finder is a pushed route.
  final VoidCallback? onBack;

  const FinderHeader({
    super.key,
    required this.liquorTypes,
    required this.selectedLiquorTypeIds,
    required this.onToggle,
    required this.onClear,
    this.onBack,
  });

  @override
  Widget build(BuildContext context) {
    final orderedLiquorTypes = sortLiquorTypesWithSelectedFirst(
      liquorTypes,
      selectedLiquorTypeIds,
    );

    return Container(
      height: 455,
      decoration: const BoxDecoration(color: EbtlColors.cream),
      child: Stack(
        children: [
          const Positioned.fill(
            top: 130,
            child: Opacity(
              opacity: 0.35,
              child: AssetOrGradientImage(
                asset: 'assets/images/finder_hero.jpg',
                borderRadius: BorderRadius.zero,
                gradientStart: EbtlColors.sand,
                gradientEnd: EbtlColors.blush,
              ),
            ),
          ),
          // The back button is not drawn here: the screen floats it above the
          // scroll so it stays reachable once the header has scrolled away.
          // The logo takes its place when the Finder is not a pushed route.
          if (onBack == null)
            const Positioned(left: 22, right: 22, top: 14, child: EbtlLogo()),
          Positioned(
            left: 22,
            right: 22,
            top: 105,
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  'Cocktail Finder',
                  style: GoogleFonts.playfairDisplay(
                    fontSize: 37,
                    fontWeight: FontWeight.w800,
                    color: EbtlColors.navy,
                  ),
                ),
                const SizedBox(height: 8),
                Text(
                  'Choose your bottle(s) to discover cocktails you can make.',
                  style: GoogleFonts.manrope(
                    fontSize: 16,
                    fontWeight: FontWeight.w600,
                    color: EbtlColors.ink,
                  ),
                ),
                const SizedBox(height: 34),
                Row(
                  children: [
                    const StepBubble(number: 1),
                    const SizedBox(width: 12),
                    Text(
                      'Choose Your Bottle',
                      style: GoogleFonts.manrope(
                        fontSize: 18,
                        fontWeight: FontWeight.w900,
                        color: EbtlColors.navy,
                      ),
                    ),
                    const Spacer(),
                    TextButton(
                      onPressed: onClear,
                      child: Text(
                        'Clear All',
                        style: GoogleFonts.manrope(
                          fontWeight: FontWeight.w800,
                          color: EbtlColors.teal,
                        ),
                      ),
                    ),
                  ],
                ),
                const SizedBox(height: 12),
                SizedBox(
                  height: 130,
                  child: ListView.separated(
                    scrollDirection: Axis.horizontal,
                    itemCount: orderedLiquorTypes.length,
                    separatorBuilder: (_, _) => const SizedBox(width: 8),
                    itemBuilder: (context, index) {
                      final liquor = orderedLiquorTypes[index];
                      final selected = selectedLiquorTypeIds.contains(
                        liquor.id,
                      );

                      return SelectableBottleCard(
                        liquor: liquor,
                        selected: selected,
                        onTap: () => onToggle(liquor.id),
                      );
                    },
                  ),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}
