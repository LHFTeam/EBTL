import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';

import '../../../core/theme/ebtl_colors.dart';
import '../../../core/utils/formatters.dart';
import '../../../models/common_models.dart';
import '../../../services/location_service.dart';

/// Beach-cart picker for the Home context header. The chip no longer sits on a
/// rail of location cards, so the choice moved into this sheet.
///
/// Resolves with the chosen location, or null when dismissed.
Future<ServiceLocation?> showBeachCartPickerSheet({
  required BuildContext context,
  required List<ServiceLocation> serviceAreas,
  required String? selectedLocationId,
  Map<String, double> distanceMetersById = const {},
  Future<Map<String, double>> Function()? onUseMyLocation,
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
        distanceMetersById: distanceMetersById,
        onUseMyLocation: onUseMyLocation,
      );
    },
  );
}

class _BeachCartPickerSheet extends StatefulWidget {
  final List<ServiceLocation> serviceAreas;
  final String? selectedLocationId;
  final Map<String, double> distanceMetersById;
  final Future<Map<String, double>> Function()? onUseMyLocation;

  const _BeachCartPickerSheet({
    required this.serviceAreas,
    required this.selectedLocationId,
    required this.distanceMetersById,
    required this.onUseMyLocation,
  });

  @override
  State<_BeachCartPickerSheet> createState() => _BeachCartPickerSheetState();
}

class _BeachCartPickerSheetState extends State<_BeachCartPickerSheet> {
  late Map<String, double> distances = widget.distanceMetersById;
  bool locating = false;
  bool locationUnavailable = false;

  Future<void> useMyLocation() async {
    final callback = widget.onUseMyLocation;
    if (callback == null || locating) return;
    setState(() {
      locating = true;
      locationUnavailable = false;
    });

    final refreshed = await callback();
    if (!mounted) return;
    setState(() {
      locating = false;
      distances = refreshed;
      // An empty map can also mean the backend has no coordinates for any
      // cart. That is a data-setup issue, not a disabled device location.
      locationUnavailable =
          refreshed.isEmpty &&
          widget.serviceAreas.any(
            (cart) => cart.latitude != null && cart.longitude != null,
          );
    });
  }

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
                  const SizedBox(height: 4),
                  if (locationUnavailable)
                    Text(
                      'Location is off. Turn it on in Settings to sort by distance.',
                      style: GoogleFonts.manrope(
                        fontSize: 12,
                        height: 1.35,
                        fontWeight: FontWeight.w500,
                        color: EbtlColors.muted,
                      ),
                    )
                  else
                    TextButton.icon(
                      onPressed: locating ? null : useMyLocation,
                      style: TextButton.styleFrom(
                        padding: EdgeInsets.zero,
                        visualDensity: VisualDensity.compact,
                      ),
                      icon: locating
                          ? const SizedBox.square(
                              dimension: 14,
                              child: CircularProgressIndicator(strokeWidth: 2),
                            )
                          : const Icon(Icons.my_location_rounded, size: 17),
                      label: const Text('Use my location'),
                    ),
                ],
              ),
            ),
            Flexible(
              child: widget.serviceAreas.isEmpty
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
                      itemCount: LocationService.sortedByDistance(
                        widget.serviceAreas,
                        distances,
                      ).length,
                      separatorBuilder: (_, _) => const SizedBox(height: 10),
                      itemBuilder: (context, index) {
                        final locations = LocationService.sortedByDistance(
                          widget.serviceAreas,
                          distances,
                        );
                        final location = locations[index];

                        return _BeachCartOption(
                          location: location,
                          selected: location.id == widget.selectedLocationId,
                          distanceMeters: distances[location.id],
                          onTap: () => Navigator.of(
                            context,
                          ).pop<ServiceLocation>(location),
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
  final double? distanceMeters;
  final VoidCallback onTap;

  const _BeachCartOption({
    required this.location,
    required this.selected,
    required this.distanceMeters,
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
                      if (distanceMeters != null) ...[
                        const SizedBox(height: 3),
                        Text(
                          formatDistance(distanceMeters!),
                          style: GoogleFonts.manrope(
                            fontSize: 11.5,
                            height: 1.2,
                            fontWeight: FontWeight.w500,
                            color: EbtlColors.muted,
                          ),
                        ),
                      ],
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
