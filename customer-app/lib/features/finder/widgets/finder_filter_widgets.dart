import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';

import '../../../core/theme/ebtl_colors.dart';
import '../../../core/theme/ebtl_text_styles.dart';
import '../../../core/utils/model_sorters.dart';
import '../../../models/common_models.dart';
import '../../../models/finder_models.dart';
import '../../../shared/widgets/bottle_widgets.dart';
import '../../../shared/widgets/brand_widgets.dart';
import '../../../shared/widgets/product_tag_widgets.dart';

class FinderResultsHeader extends StatelessWidget {
  final int count;
  final List<SortOption> sortOptions;
  final int sortIndex;
  final ValueChanged<int> onSortChanged;

  const FinderResultsHeader({
    super.key,
    required this.count,
    required this.sortOptions,
    required this.sortIndex,
    required this.onSortChanged,
  });

  @override
  Widget build(BuildContext context) {
    final options = sortOptions.isEmpty ? SortOption.defaults : sortOptions;

    return Padding(
      padding: const EdgeInsets.fromLTRB(22, 22, 22, 6),
      child: Column(
        children: [
          Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              const StepBubble(number: 2),
              const SizedBox(width: 12),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      'Cocktails You Can Make',
                      maxLines: 2,
                      overflow: TextOverflow.ellipsis,
                      style: sectionTitleStyle(),
                    ),
                    const SizedBox(height: 3),
                    Text(
                      '$count matches',
                      style: GoogleFonts.manrope(
                        fontSize: 14,
                        color: EbtlColors.muted,
                        fontWeight: FontWeight.w700,
                      ),
                    ),
                  ],
                ),
              ),
            ],
          ),
          const SizedBox(height: 16),
          SizedBox(
            height: 38,
            child: ListView.separated(
              scrollDirection: Axis.horizontal,
              itemCount: options.length,
              separatorBuilder: (_, _) => const SizedBox(width: 10),
              itemBuilder: (context, index) {
                final active = sortIndex == index;

                return GestureDetector(
                  onTap: () => onSortChanged(index),
                  child: Container(
                    padding: const EdgeInsets.symmetric(horizontal: 16),
                    decoration: BoxDecoration(
                      color: active ? EbtlColors.coral : EbtlColors.white,
                      borderRadius: BorderRadius.circular(999),
                      border: Border.all(
                        color: active ? EbtlColors.coral : EbtlColors.border,
                      ),
                    ),
                    alignment: Alignment.center,
                    child: Row(
                      children: [
                        Text(
                          options[index].label,
                          style: GoogleFonts.manrope(
                            color: active ? Colors.white : EbtlColors.ink,
                            fontWeight: FontWeight.w800,
                            fontSize: 11,
                          ),
                        ),
                        if (active) ...[
                          const SizedBox(width: 6),
                          const Icon(
                            Icons.check_circle,
                            size: 16,
                            color: Colors.white,
                          ),
                        ],
                      ],
                    ),
                  ),
                );
              },
            ),
          ),
        ],
      ),
    );
  }
}

class ProductTagFilterSection extends StatelessWidget {
  final List<ProductTag> productTags;
  final Set<String> selectedTagNames;
  final ValueChanged<String> onToggle;
  final VoidCallback onClear;

  const ProductTagFilterSection({
    super.key,
    required this.productTags,
    required this.selectedTagNames,
    required this.onToggle,
    required this.onClear,
  });

  @override
  Widget build(BuildContext context) {
    final tags = sortProductTags(productTags);
    if (tags.isEmpty) return const SizedBox.shrink();

    return Padding(
      padding: const EdgeInsets.fromLTRB(22, 8, 22, 10),
      child: Container(
        width: double.infinity,
        padding: const EdgeInsets.fromLTRB(16, 14, 16, 16),
        decoration: BoxDecoration(
          color: EbtlColors.white.withValues(alpha: 0.72),
          borderRadius: BorderRadius.circular(20),
          border: Border.all(color: EbtlColors.border),
        ),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                const Icon(
                  Icons.sell_outlined,
                  color: EbtlColors.coral,
                  size: 22,
                ),
                const SizedBox(width: 10),
                Expanded(
                  child: Text(
                    'Filter by Style',
                    style: GoogleFonts.manrope(
                      fontSize: 13,
                      fontWeight: FontWeight.w900,
                      color: EbtlColors.navy,
                    ),
                  ),
                ),
                if (selectedTagNames.isNotEmpty)
                  TextButton(
                    onPressed: onClear,
                    child: Text(
                      'Clear',
                      style: GoogleFonts.manrope(
                        fontWeight: FontWeight.w900,
                        color: EbtlColors.teal,
                      ),
                    ),
                  ),
              ],
            ),
            const SizedBox(height: 12),
            Wrap(
              spacing: 7,
              runSpacing: 7,
              children: tags.map((tag) {
                final selected = selectedTagNames.contains(tag.name);
                return ProductTagFilterChip(
                  tag: tag,
                  selected: selected,
                  onTap: () => onToggle(tag.name),
                );
              }).toList(),
            ),
          ],
        ),
      ),
    );
  }
}

class SelectedChips extends StatelessWidget {
  final List<LiquorType> liquorTypes;
  final List<ProductTag> productTags;
  final Set<String> selectedLiquorTypeIds;
  final Set<String> selectedProductTagNames;
  final ValueChanged<String> onRemoveLiquor;
  final ValueChanged<String> onRemoveTag;

  const SelectedChips({
    super.key,
    required this.liquorTypes,
    required this.productTags,
    required this.selectedLiquorTypeIds,
    required this.selectedProductTagNames,
    required this.onRemoveLiquor,
    required this.onRemoveTag,
  });

  @override
  Widget build(BuildContext context) {
    final selectedLiquors = liquorTypes
        .where((liquor) => selectedLiquorTypeIds.contains(liquor.id))
        .toList();

    final selectedTags = sortProductTags(
      productTags,
    ).where((tag) => selectedProductTagNames.contains(tag.name)).toList();

    if (selectedLiquors.isEmpty && selectedTags.isEmpty) {
      return const SizedBox.shrink();
    }

    return Padding(
      padding: const EdgeInsets.fromLTRB(22, 0, 22, 8),
      child: Wrap(
        spacing: 10,
        runSpacing: 10,
        crossAxisAlignment: WrapCrossAlignment.center,
        children: [
          Text(
            'Selected:',
            style: GoogleFonts.manrope(
              fontWeight: FontWeight.w900,
              color: EbtlColors.navy,
            ),
          ),
          ...selectedLiquors.map(
            (liquor) => Chip(
              backgroundColor: EbtlColors.white,
              side: const BorderSide(color: EbtlColors.border),
              visualDensity: VisualDensity.compact,
              materialTapTargetSize: MaterialTapTargetSize.shrinkWrap,
              labelPadding: const EdgeInsets.symmetric(horizontal: 3),
              avatar: BottleImage(liquor: liquor, size: 20),
              label: Text(
                liquor.name,
                style: GoogleFonts.manrope(
                  fontSize: 12,
                  fontWeight: FontWeight.w800,
                ),
              ),
              deleteIcon: const Icon(Icons.close, size: 14),
              onDeleted: () => onRemoveLiquor(liquor.id),
            ),
          ),
          ...selectedTags.map(
            (tag) => ProductTagSelectedChip(
              tag: tag,
              onDeleted: () => onRemoveTag(tag.name),
            ),
          ),
        ],
      ),
    );
  }
}

class FinderSearchBox extends StatelessWidget {
  final TextEditingController controller;
  final ValueChanged<String> onSubmitted;
  final VoidCallback onClear;

  const FinderSearchBox({
    super.key,
    required this.controller,
    required this.onSubmitted,
    required this.onClear,
  });

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.fromLTRB(22, 6, 22, 8),
      child: TextField(
        controller: controller,
        textInputAction: TextInputAction.search,
        onSubmitted: onSubmitted,
        // iOS keeps the keyboard up on a touch outside the field, so tapping
        // the results below it has to put the keyboard away by hand.
        onTapOutside: (_) => FocusManager.instance.primaryFocus?.unfocus(),
        decoration: InputDecoration(
          hintText: 'Search cocktails, flavors, tags...',
          prefixIcon: const Icon(Icons.search, color: EbtlColors.muted),
          suffixIcon: IconButton(
            icon: const Icon(Icons.close, color: EbtlColors.muted),
            onPressed: onClear,
          ),
          filled: true,
          fillColor: EbtlColors.white.withValues(alpha: 0.9),
          contentPadding: const EdgeInsets.symmetric(
            horizontal: 18,
            vertical: 16,
          ),
          border: OutlineInputBorder(
            borderRadius: BorderRadius.circular(20),
            borderSide: const BorderSide(color: EbtlColors.border),
          ),
          enabledBorder: OutlineInputBorder(
            borderRadius: BorderRadius.circular(20),
            borderSide: const BorderSide(color: EbtlColors.border),
          ),
          focusedBorder: OutlineInputBorder(
            borderRadius: BorderRadius.circular(20),
            borderSide: const BorderSide(color: EbtlColors.coral, width: 1.4),
          ),
        ),
      ),
    );
  }
}

class FinderInfoBanner extends StatelessWidget {
  final bool hasSelectedLocation;
  final String? selectedLocationName;

  const FinderInfoBanner({
    super.key,
    required this.hasSelectedLocation,
    required this.selectedLocationName,
  });

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.fromLTRB(22, 8, 22, 0),
      child: Container(
        constraints: const BoxConstraints(minHeight: 56),
        padding: const EdgeInsets.symmetric(horizontal: 18, vertical: 12),
        decoration: BoxDecoration(
          color: EbtlColors.white.withValues(alpha: 0.65),
          borderRadius: BorderRadius.circular(20),
          border: Border.all(color: EbtlColors.border),
        ),
        child: Row(
          children: [
            Icon(
              hasSelectedLocation
                  ? Icons.check_circle_outline
                  : Icons.info_outline,
              color: hasSelectedLocation ? EbtlColors.teal : EbtlColors.coral,
            ),
            const SizedBox(width: 14),
            Expanded(
              child: Text(
                hasSelectedLocation
                    ? 'Showing real availability for ${selectedLocationName ?? 'your selected beach cart'}.'
                    : 'Choose a beach cart on Home to see real-time order availability.',
                style: GoogleFonts.manrope(
                  fontSize: 13,
                  color: EbtlColors.ink,
                  fontWeight: FontWeight.w600,
                ),
              ),
            ),
            const Icon(Icons.chevron_right, color: EbtlColors.muted),
          ],
        ),
      ),
    );
  }
}
