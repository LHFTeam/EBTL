// lib/shared/widgets/ebtl_loading_graphic.dart

import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';

import '../../core/theme/ebtl_colors.dart';

class EbtlLoadingGraphic extends StatelessWidget {
  const EbtlLoadingGraphic({
    super.key,
    this.size = 96,
    this.label = 'Mixing things up...',
    this.showLabel = true,
  });

  static const String assetPath = 'assets/animations/ebtl_loader.webp';

  final double size;
  final String label;
  final bool showLabel;

  @override
  Widget build(BuildContext context) {
    return Center(
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          Image.asset(
            assetPath,
            width: size,
            height: size,
            fit: BoxFit.contain,
            gaplessPlayback: true,
            filterQuality: FilterQuality.high,
          ),
          if (showLabel) ...[
            const SizedBox(height: 14),
            Text(
              label,
              textAlign: TextAlign.center,
              style: GoogleFonts.manrope(
                fontSize: 14,
                fontWeight: FontWeight.w800,
                color: EbtlColors.navy,
              ),
            ),
            const SizedBox(height: 4),
            Container(
              width: 28,
              height: 3,
              decoration: BoxDecoration(
                color: EbtlColors.coral,
                borderRadius: BorderRadius.circular(99),
              ),
            ),
          ],
        ],
      ),
    );
  }
}
