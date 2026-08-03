import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';

import '../../../core/theme/ebtl_colors.dart';
import '../../../models/common_models.dart';

/// Beach-cart picker for the Home context header. The chip no longer sits on a
/// rail of location cards, so the choice moved into this sheet.
///
/// Resolves with the chosen location, or null when dismissed.
Future<ServiceLocation?> showBeachCartPickerSheet({
  required BuildContext context,
  required List<ServiceLocation> serviceAreas,
  required String? selectedLocationId,
}) {
  return showModalBottomSheet<ServiceLocation>(
    context: context,
    backgroundColor: EbtlColors.cream,
    isScrollControlled: true,
    shape: const RoundedRectangleBorder(
      borderRadius: BorderRadius.vertical(top: Radius.circular(24)),
    ),
    builder: (sheetContext) {
      return _BeachCartPickerSheet(
        serviceAreas: serviceAreas,
        selectedLocationId: selectedLocationId,
      );
    },
  );
}

class _BeachCartPickerSheet extends StatelessWidget {
  final List<ServiceLocation> serviceAreas;
  final String? selectedLocationId;

  const _BeachCartPickerSheet({
    required this.serviceAreas,
    required this.selectedLocationId,
  });

  @override
  Widget build(BuildContext context) {
    return SafeArea(
      top: false,
      child: ConstrainedBox(
        constraints: BoxConstraints(
          maxHeight: MediaQuery.sizeOf(context).height * 0.75,
        ),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            const SizedBox(height: 10),
            Container(
              width: 42,
              height: 4,
              decoration: BoxDecoration(
                color: EbtlColors.border,
                borderRadius: BorderRadius.circular(999),
              ),
            ),
            Padding(
              padding: const EdgeInsets.fromLTRB(22, 18, 22, 4),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    'Choose your beach cart',
                    style: GoogleFonts.playfairDisplay(
                      fontSize: 22,
                      height: 1.15,
                      fontWeight: FontWeight.w800,
                      color: EbtlColors.navy,
                    ),
                  ),
                  const SizedBox(height: 6),
                  Text(
                    'Availability and pickup are checked against the cart you '
                    'order from.',
                    style: GoogleFonts.manrope(
                      fontSize: 13,
                      height: 1.4,
                      fontWeight: FontWeight.w500,
                      color: EbtlColors.muted,
                    ),
                  ),
                ],
              ),
            ),
            Flexible(
              child: serviceAreas.isEmpty
                  ? Padding(
                      padding: const EdgeInsets.fromLTRB(22, 22, 22, 26),
                      child: Text(
                        'No beach carts are serving right now. Please check '
                        'back soon.',
                        style: GoogleFonts.manrope(
                          fontSize: 13.5,
                          height: 1.4,
                          fontWeight: FontWeight.w600,
                          color: EbtlColors.ink,
                        ),
                      ),
                    )
                  : ListView.separated(
                      shrinkWrap: true,
                      padding: const EdgeInsets.fromLTRB(22, 14, 22, 26),
                      itemCount: serviceAreas.length,
                      separatorBuilder: (_, _) => const SizedBox(height: 10),
                      itemBuilder: (context, index) {
                        final location = serviceAreas[index];

                        return _BeachCartOption(
                          location: location,
                          selected: location.id == selectedLocationId,
                          onTap: () =>
                              Navigator.of(context).pop<ServiceLocation>(
                                location,
                              ),
                        );
                      },
                    ),
            ),
          ],
        ),
      ),
    );
  }
}

class _BeachCartOption extends StatelessWidget {
  final ServiceLocation location;
  final bool selected;
  final VoidCallback onTap;

  const _BeachCartOption({
    required this.location,
    required this.selected,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    return Material(
      color: EbtlColors.white,
      borderRadius: BorderRadius.circular(18),
      child: InkWell(
        onTap: onTap,
        borderRadius: BorderRadius.circular(18),
        child: Ink(
          decoration: BoxDecoration(
            color: EbtlColors.white,
            borderRadius: BorderRadius.circular(18),
            border: Border.all(
              color: selected ? EbtlColors.coral : EbtlColors.border,
              width: selected ? 1.5 : 1,
            ),
          ),
          child: Padding(
            padding: const EdgeInsets.all(16),
            child: Row(
              children: [
                Container(
                  width: 44,
                  height: 44,
                  decoration: BoxDecoration(
                    color: selected ? EbtlColors.blush : EbtlColors.seafoam,
                    shape: BoxShape.circle,
                  ),
                  child: Icon(
                    selected ? Icons.check_rounded : Icons.place_outlined,
                    size: 21,
                    color: EbtlColors.navy,
                  ),
                ),
                const SizedBox(width: 14),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        location.name,
                        maxLines: 2,
                        overflow: TextOverflow.ellipsis,
                        style: GoogleFonts.manrope(
                          fontSize: 14.5,
                          height: 1.2,
                          fontWeight: FontWeight.w900,
                          color: EbtlColors.navy,
                        ),
                      ),
                      const SizedBox(height: 4),
                      Text(
                        location.subtitle,
                        maxLines: 2,
                        overflow: TextOverflow.ellipsis,
                        style: GoogleFonts.manrope(
                          fontSize: 12.5,
                          height: 1.25,
                          fontWeight: FontWeight.w600,
                          color: EbtlColors.muted,
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
