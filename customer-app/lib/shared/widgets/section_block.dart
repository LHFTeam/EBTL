import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';

import '../../core/theme/ebtl_colors.dart';
import '../../core/theme/ebtl_text_styles.dart';

class SectionBlock extends StatelessWidget {
  /// Leading icon for the header. Null renders the title on its own, flush with
  /// the page gutter.
  final IconData? icon;
  final String title;
  final String? subtitle;
  final String? actionText;
  final VoidCallback? onAction;
  final Widget child;

  const SectionBlock({
    super.key,
    this.icon,
    required this.title,
    this.subtitle,
    this.actionText,
    this.onAction,
    required this.child,
  });

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.only(top: 22),
      child: Column(
        children: [
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: 22),
            child: Row(
              crossAxisAlignment: CrossAxisAlignment.center,
              children: [
                if (icon != null) ...[
                  Icon(icon, color: EbtlColors.coral, size: 28),
                  const SizedBox(width: 12),
                ],
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(title, style: sectionTitleStyle()),
                      if (subtitle != null) ...[
                        const SizedBox(height: 4),
                        Text(
                          subtitle!,
                          style: GoogleFonts.manrope(
                            fontSize: 13,
                            color: EbtlColors.ink,
                            fontWeight: FontWeight.w500,
                          ),
                        ),
                      ],
                    ],
                  ),
                ),
                if (actionText != null)
                  _SectionAction(label: actionText!, onTap: onAction),
              ],
            ),
          ),
          const SizedBox(height: 14),
          child,
        ],
      ),
    );
  }
}

class _SectionAction extends StatelessWidget {
  final String label;
  final VoidCallback? onTap;

  const _SectionAction({required this.label, this.onTap});

  @override
  Widget build(BuildContext context) {
    return Material(
      color: Colors.transparent,
      child: InkWell(
        onTap: onTap,
        borderRadius: BorderRadius.circular(10),
        child: Padding(
          padding: const EdgeInsets.symmetric(horizontal: 4, vertical: 4),
          child: Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              Text(
                label,
                style: GoogleFonts.manrope(
                  fontWeight: FontWeight.w800,
                  color: EbtlColors.teal,
                ),
              ),
              const SizedBox(width: 6),
              const Icon(Icons.chevron_right, color: EbtlColors.teal),
            ],
          ),
        ),
      ),
    );
  }
}
