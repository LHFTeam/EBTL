import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';

import '../../../core/theme/ebtl_colors.dart';
import '../../../models/spirit_models.dart';
import '../../../shared/widgets/bottle_widgets.dart';
import 'profile_widgets.dart';

/// A spirit as a bottle-and-name pill. The trailing slot is the only thing that
/// changes between the three places spirits are shown: a remove button on the
/// customer's own list, an add button in the picker, nothing at all on the
/// computed most-ordered list.
class SpiritPill extends StatelessWidget {
  final ProfileSpirit spirit;
  final String? trailingLabel;
  final IconData? actionIcon;
  final bool isBusy;
  final bool highlighted;
  final VoidCallback? onAction;

  const SpiritPill({
    super.key,
    required this.spirit,
    this.trailingLabel,
    this.actionIcon,
    this.isBusy = false,
    this.highlighted = false,
    this.onAction,
  });

  @override
  Widget build(BuildContext context) {
    final pill = Container(
      padding: EdgeInsets.fromLTRB(5, 4, actionIcon == null ? 12 : 4, 4),
      decoration: BoxDecoration(
        color: highlighted
            ? EbtlColors.seafoam.withValues(alpha: 0.55)
            : EbtlColors.cream.withValues(alpha: 0.85),
        borderRadius: BorderRadius.circular(999),
        border: Border.all(color: EbtlColors.border),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          BottleImage.raw(
            name: spirit.name,
            imageUrl: spirit.imageUrl,
            size: 30,
          ),
          const SizedBox(width: 9),
          // Bottle names come from the backend and run long ("Johnnie Walker
          // Blue Label Ghost and Rare"). Without this the pill keeps growing
          // past the row it wraps in and the ellipsis never engages.
          Flexible(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              mainAxisSize: MainAxisSize.min,
              children: [
                Text(
                  spirit.name,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: GoogleFonts.manrope(
                    fontSize: 13,
                    height: 1.15,
                    fontWeight: FontWeight.w900,
                    color: EbtlColors.navy,
                  ),
                ),
                if ((trailingLabel ?? '').isNotEmpty)
                  Text(
                    trailingLabel!,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: GoogleFonts.manrope(
                      fontSize: 10,
                      height: 1.2,
                      fontWeight: FontWeight.w700,
                      color: EbtlColors.muted,
                    ),
                  ),
              ],
            ),
          ),
          if (actionIcon != null) ...[
            const SizedBox(width: 8),
            SizedBox(
              width: 30,
              height: 30,
              child: isBusy
                  ? const Padding(
                      padding: EdgeInsets.all(7),
                      child: CircularProgressIndicator(
                        color: EbtlColors.coral,
                        strokeWidth: 2,
                      ),
                    )
                  : Icon(actionIcon, size: 20, color: EbtlColors.coral),
            ),
          ],
        ],
      ),
    );

    if (onAction == null || isBusy) return pill;

    return Material(
      color: Colors.transparent,
      child: InkWell(
        onTap: onAction,
        borderRadius: BorderRadius.circular(999),
        child: pill,
      ),
    );
  }
}

/// The spirits block on the profile screen: what the customer saved, and the
/// spirits the backend worked out they order most.
class ProfileSpiritsSection extends StatelessWidget {
  final ProfileSpirits spirits;
  final VoidCallback onManage;

  const ProfileSpiritsSection({
    super.key,
    required this.spirits,
    required this.onManage,
  });

  @override
  Widget build(BuildContext context) {
    final favorites = spirits.favoriteSpirits;
    final topSpirits = spirits.topSpirits;

    return Padding(
      padding: const EdgeInsets.fromLTRB(22, 0, 22, 18),
      child: Column(
        children: [
          ProfileSectionHeader(
            title: favorites.title,
            actionText: 'Manage',
            onAction: onManage,
          ),
          Container(
            width: double.infinity,
            padding: const EdgeInsets.all(16),
            decoration: BoxDecoration(
              color: EbtlColors.white.withValues(alpha: 0.92),
              borderRadius: BorderRadius.circular(18),
              border: Border.all(color: EbtlColors.border),
              boxShadow: [
                BoxShadow(
                  color: Colors.black.withValues(alpha: 0.035),
                  blurRadius: 18,
                  offset: const Offset(0, 8),
                ),
              ],
            ),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                if (favorites.isEmpty)
                  _SpiritsEmptyPrompt(onTap: onManage)
                else
                  Wrap(
                    spacing: 8,
                    runSpacing: 8,
                    children: favorites.items
                        .map((spirit) => SpiritPill(spirit: spirit))
                        .toList(),
                  ),
                if (topSpirits.items.isNotEmpty) ...[
                  const SizedBox(height: 16),
                  Divider(
                    height: 1,
                    color: EbtlColors.border.withValues(alpha: 0.95),
                  ),
                  const SizedBox(height: 14),
                  SpiritsGroupLabel(
                    label: topSpirits.title,
                    hint: topSpirits.subtitle,
                  ),
                  const SizedBox(height: 10),
                  Wrap(
                    spacing: 8,
                    runSpacing: 8,
                    children: topSpirits.items
                        .map(
                          (spirit) => SpiritPill(
                            spirit: spirit,
                            trailingLabel: spirit.orderCountLabel,
                            highlighted: true,
                          ),
                        )
                        .toList(),
                  ),
                ],
              ],
            ),
          ),
        ],
      ),
    );
  }
}

class SpiritsGroupLabel extends StatelessWidget {
  final String label;
  final String hint;

  const SpiritsGroupLabel({super.key, required this.label, this.hint = ''});

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(
          label.toUpperCase(),
          style: GoogleFonts.manrope(
            fontSize: 11,
            letterSpacing: 0.8,
            fontWeight: FontWeight.w900,
            color: EbtlColors.teal,
          ),
        ),
        if (hint.trim().isNotEmpty) ...[
          const SizedBox(height: 3),
          Text(
            hint.trim(),
            style: GoogleFonts.manrope(
              fontSize: 12,
              height: 1.3,
              fontWeight: FontWeight.w600,
              color: EbtlColors.muted,
            ),
          ),
        ],
      ],
    );
  }
}

class _SpiritsEmptyPrompt extends StatelessWidget {
  final VoidCallback onTap;

  const _SpiritsEmptyPrompt({required this.onTap});

  @override
  Widget build(BuildContext context) {
    return Material(
      color: Colors.transparent,
      child: InkWell(
        onTap: onTap,
        borderRadius: BorderRadius.circular(14),
        child: Row(
          children: [
            Container(
              width: 52,
              height: 52,
              decoration: BoxDecoration(
                color: EbtlColors.sand.withValues(alpha: 0.62),
                borderRadius: BorderRadius.circular(16),
              ),
              child: const Icon(Icons.liquor_outlined, color: EbtlColors.navy),
            ),
            const SizedBox(width: 14),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    'No spirits saved yet.',
                    style: GoogleFonts.manrope(
                      fontSize: 15,
                      fontWeight: FontWeight.w900,
                      color: EbtlColors.navy,
                    ),
                  ),
                  const SizedBox(height: 4),
                  Text(
                    'Save the bottles you keep at hand.',
                    style: GoogleFonts.manrope(
                      fontSize: 12,
                      height: 1.3,
                      fontWeight: FontWeight.w600,
                      color: EbtlColors.muted,
                    ),
                  ),
                ],
              ),
            ),
            const Icon(Icons.chevron_right, color: EbtlColors.navy, size: 25),
          ],
        ),
      ),
    );
  }
}
