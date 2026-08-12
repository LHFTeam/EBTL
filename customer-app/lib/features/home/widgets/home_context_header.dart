import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';

import '../../../core/theme/ebtl_colors.dart';
import '../../search/widgets/catalog_search_field.dart';

/// The fixed block at the top of Home: the beach-cart chip, the notifications
/// button and the search field. It does not scroll — it is the context the
/// whole screen is read against ("where am I ordering from, what can I look
/// for").
class HomeContextHeader extends StatelessWidget {
  /// The selected beach cart, or null when none has been chosen yet — which
  /// switches the chip to its coral "choose one" variant.
  final String? locationName;
  final VoidCallback onOpenLocationPicker;
  final int unreadNotificationCount;
  final VoidCallback onOpenNotifications;

  /// The search field is a live input — the screen behind it owns the
  /// controller, the debounce and the results.
  final TextEditingController searchController;
  final FocusNode searchFocusNode;

  /// Anchors the results dropdown to the field, so it hangs off the header
  /// over the modules below.
  final LayerLink searchFieldLink;

  /// Groups the field with that dropdown, so only a tap outside both puts the
  /// keyboard away.
  final SearchTapGroup searchTapGroup;
  final ValueChanged<String> onSearchChanged;
  final ValueChanged<String> onSubmitSearch;
  final VoidCallback onClearSearch;

  const HomeContextHeader({
    super.key,
    required this.locationName,
    required this.onOpenLocationPicker,
    required this.unreadNotificationCount,
    required this.onOpenNotifications,
    required this.searchController,
    required this.searchFocusNode,
    required this.searchFieldLink,
    required this.searchTapGroup,
    required this.onSearchChanged,
    required this.onSubmitSearch,
    required this.onClearSearch,
  });

  @override
  Widget build(BuildContext context) {
    return Container(
      decoration: const BoxDecoration(
        color: EbtlColors.cream,
        border: Border(bottom: BorderSide(color: EbtlColors.border)),
      ),
      child: SafeArea(
        bottom: false,
        child: Padding(
          padding: const EdgeInsets.fromLTRB(22, 12, 22, 12),
          child: Column(
            children: [
              Row(
                children: [
                  Expanded(
                    child: _BeachCartChip(
                      locationName: locationName,
                      onTap: onOpenLocationPicker,
                    ),
                  ),
                  const SizedBox(width: 10),
                  _NotificationsButton(
                    unreadCount: unreadNotificationCount,
                    onTap: onOpenNotifications,
                  ),
                ],
              ),
              const SizedBox(height: 12),
              CatalogSearchField(
                controller: searchController,
                focusNode: searchFocusNode,
                layerLink: searchFieldLink,
                tapGroup: searchTapGroup,
                onChanged: onSearchChanged,
                onSubmitted: onSubmitSearch,
                onClear: onClearSearch,
              ),
            ],
          ),
        ),
      ),
    );
  }
}

class _BeachCartChip extends StatelessWidget {
  final String? locationName;
  final VoidCallback onTap;

  const _BeachCartChip({required this.locationName, required this.onTap});

  @override
  Widget build(BuildContext context) {
    final name = locationName?.trim();
    final hasLocation = name != null && name.isNotEmpty;

    return Material(
      color: hasLocation ? EbtlColors.white : EbtlColors.coral,
      borderRadius: BorderRadius.circular(999),
      child: InkWell(
        onTap: onTap,
        borderRadius: BorderRadius.circular(999),
        child: Container(
          height: 46,
          padding: EdgeInsets.symmetric(horizontal: hasLocation ? 14 : 16),
          decoration: BoxDecoration(
            borderRadius: BorderRadius.circular(999),
            border: hasLocation
                ? Border.all(color: EbtlColors.border)
                : null,
          ),
          child: hasLocation
              ? _selectedContent(name)
              : _emptyContent(),
        ),
      ),
    );
  }

  Widget _selectedContent(String name) {
    return Row(
      children: [
        const Icon(Icons.place_outlined, size: 16, color: EbtlColors.coral),
        const SizedBox(width: 8),
        Expanded(
          child: Column(
            mainAxisAlignment: MainAxisAlignment.center,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                'ORDERING FROM',
                style: GoogleFonts.manrope(
                  fontSize: 9.5,
                  height: 1.2,
                  fontWeight: FontWeight.w800,
                  letterSpacing: 1.1,
                  color: EbtlColors.muted,
                ),
              ),
              Text(
                name,
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                style: GoogleFonts.manrope(
                  fontSize: 13.5,
                  height: 1.2,
                  fontWeight: FontWeight.w900,
                  color: EbtlColors.navy,
                ),
              ),
            ],
          ),
        ),
        const SizedBox(width: 8),
        const Icon(
          Icons.keyboard_arrow_down_rounded,
          size: 18,
          color: EbtlColors.navy,
        ),
      ],
    );
  }

  Widget _emptyContent() {
    return Row(
      children: [
        const Icon(Icons.place_outlined, size: 17, color: EbtlColors.white),
        const SizedBox(width: 9),
        Expanded(
          child: Text(
            'Choose your beach cart',
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
            style: GoogleFonts.manrope(
              fontSize: 14.5,
              fontWeight: FontWeight.w900,
              color: EbtlColors.white,
            ),
          ),
        ),
        const SizedBox(width: 8),
        const Icon(
          Icons.chevron_right_rounded,
          size: 18,
          color: EbtlColors.white,
        ),
      ],
    );
  }
}

class _NotificationsButton extends StatelessWidget {
  final int unreadCount;
  final VoidCallback onTap;

  const _NotificationsButton({required this.unreadCount, required this.onTap});

  @override
  Widget build(BuildContext context) {
    return Stack(
      clipBehavior: Clip.none,
      children: [
        Material(
          color: EbtlColors.white,
          shape: const CircleBorder(
            side: BorderSide(color: EbtlColors.border),
          ),
          child: InkWell(
            onTap: onTap,
            customBorder: const CircleBorder(),
            child: const SizedBox(
              width: 46,
              height: 46,
              child: Icon(
                Icons.notifications_none_rounded,
                size: 20,
                color: EbtlColors.navy,
              ),
            ),
          ),
        ),
        if (unreadCount > 0)
          Positioned(
            top: -2,
            right: -2,
            child: IgnorePointer(
              child: Container(
                constraints: const BoxConstraints(minWidth: 20),
                height: 20,
                padding: const EdgeInsets.symmetric(horizontal: 4),
                alignment: Alignment.center,
                decoration: BoxDecoration(
                  color: EbtlColors.coral,
                  borderRadius: BorderRadius.circular(999),
                  border: Border.all(color: EbtlColors.cream, width: 2),
                ),
                child: Text(
                  unreadCount > 9 ? '9+' : '$unreadCount',
                  style: GoogleFonts.manrope(
                    fontSize: 11,
                    height: 1,
                    fontWeight: FontWeight.w900,
                    color: EbtlColors.white,
                  ),
                ),
              ),
            ),
          ),
      ],
    );
  }
}
