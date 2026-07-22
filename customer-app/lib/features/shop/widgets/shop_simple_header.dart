import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';

import '../../../core/theme/ebtl_colors.dart';
import '../../../shared/widgets/brand_widgets.dart';

class ShopSimpleHeader extends StatelessWidget {
  final String title;
  final String subtitle;
  final VoidCallback onBack;

  const ShopSimpleHeader({
    super.key,
    required this.title,
    required this.subtitle,
    required this.onBack,
  });

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.fromLTRB(22, 12, 22, 10),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          CircleIconButton(icon: Icons.arrow_back, onTap: onBack),
          const SizedBox(width: 14),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  title,
                  maxLines: 2,
                  overflow: TextOverflow.ellipsis,
                  style: GoogleFonts.playfairDisplay(
                    fontSize: 32,
                    height: 1.05,
                    fontWeight: FontWeight.w800,
                    color: EbtlColors.navy,
                  ),
                ),
                const SizedBox(height: 6),
                Text(
                  subtitle,
                  style: GoogleFonts.manrope(
                    fontSize: 14,
                    height: 1.35,
                    fontWeight: FontWeight.w700,
                    color: EbtlColors.ink,
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
