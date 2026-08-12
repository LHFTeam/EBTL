import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';

import '../../../core/theme/ebtl_colors.dart';
import '../../../core/utils/keyboard.dart';

/// Ties a search field to the results dropdown hanging off it, for the sake of
/// taps: a tap on either belongs to the search, and a tap anywhere else puts
/// the keyboard away.
///
/// A screen makes one and hands the same instance to its [CatalogSearchField]
/// and its results dropdown. It carries no state — a [TapRegion] group only
/// needs an identity — and is deliberately not const, so that two screens each
/// get a group of their own.
///
/// iOS is why this is needed at all: unlike desktop and the web, a touch
/// outside a focused field does not dismiss the keyboard there, so the field
/// has to dismiss it itself and needs to know what "outside" means.
class SearchTapGroup {
  SearchTapGroup();
}

/// The one search field the app has: a white pill with the magnifier on the
/// left and a clear button that appears once something is typed.
///
/// Home and Explore both use it, so the two surfaces cannot drift apart in
/// either look or behaviour.
class CatalogSearchField extends StatelessWidget {
  /// The pill's fixed height — it matches the beach-cart chip and the
  /// notifications button it sits under on Home.
  static const double height = 46;

  final TextEditingController controller;
  final FocusNode? focusNode;
  final ValueChanged<String> onChanged;

  /// Called when the keyboard's search key is pressed.
  final ValueChanged<String>? onSubmitted;
  final VoidCallback onClear;
  final String hintText;

  /// Anchors the results dropdown to this field, so it hangs off the pill
  /// instead of pushing the page around. See [SearchResultsDropdown].
  final LayerLink? layerLink;

  /// Groups the pill with its results dropdown, so a tap on either keeps the
  /// keyboard up and a tap anywhere else dismisses it. Without one the pill
  /// stands alone and only taps on it are "inside".
  final SearchTapGroup? tapGroup;

  const CatalogSearchField({
    super.key,
    required this.controller,
    required this.onChanged,
    required this.onClear,
    this.onSubmitted,
    this.focusNode,
    this.layerLink,
    this.tapGroup,
    this.hintText = 'Search cocktails, mixers, snacks',
  });

  @override
  Widget build(BuildContext context) {
    final link = layerLink;
    if (link != null) {
      return CompositedTransformTarget(link: link, child: buildField());
    }

    return buildField();
  }

  Widget buildField() {
    final group = tapGroup;
    if (group == null) return buildPill();

    // The whole pill counts as inside, not just the text — the clear button
    // sits next to the field and must not dismiss what it re-focuses.
    return TapRegion(groupId: group, child: buildPill());
  }

  Widget buildPill() {
    return Container(
      height: height,
      padding: const EdgeInsets.symmetric(horizontal: 16),
      decoration: BoxDecoration(
        color: EbtlColors.white,
        borderRadius: BorderRadius.circular(999),
        border: Border.all(color: EbtlColors.border),
      ),
      child: Row(
        children: [
          const Icon(Icons.search_rounded, size: 18, color: EbtlColors.muted),
          const SizedBox(width: 10),
          Expanded(
            child: TextField(
              controller: controller,
              focusNode: focusNode,
              // "Outside" is the whole tap group: the pill and the results
              // dropdown hanging off it.
              groupId: tapGroup ?? EditableText,
              onTapOutside: dismissKeyboard,
              textInputAction: TextInputAction.search,
              textAlignVertical: TextAlignVertical.center,
              cursorColor: EbtlColors.coral,
              onChanged: onChanged,
              onSubmitted: onSubmitted,
              style: GoogleFonts.manrope(
                fontSize: 14,
                fontWeight: FontWeight.w600,
                color: EbtlColors.navy,
              ),
              decoration: InputDecoration(
                isCollapsed: true,
                border: InputBorder.none,
                hintText: hintText,
                hintStyle: GoogleFonts.manrope(
                  fontSize: 14,
                  fontWeight: FontWeight.w600,
                  color: EbtlColors.muted,
                ),
              ),
            ),
          ),
          // The controller drives this rather than the parent's state, so the
          // button appears on the same frame as the first character.
          ValueListenableBuilder<TextEditingValue>(
            valueListenable: controller,
            builder: (context, value, _) {
              if (value.text.isEmpty) return const SizedBox.shrink();

              return Padding(
                padding: const EdgeInsets.only(left: 6),
                child: Tooltip(
                  message: 'Clear search',
                  child: InkWell(
                    onTap: onClear,
                    customBorder: const CircleBorder(),
                    child: const Padding(
                      padding: EdgeInsets.all(4),
                      child: Icon(
                        Icons.close_rounded,
                        size: 18,
                        color: EbtlColors.muted,
                      ),
                    ),
                  ),
                ),
              );
            },
          ),
        ],
      ),
    );
  }
}
