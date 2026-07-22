import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';

import '../../../core/theme/ebtl_colors.dart';

class HowItWorksBlock extends StatelessWidget {
  static const String assetPath = 'assets/banners/how_it_works_banner.webp';

  // The attached banner is approximately 1440 x 1064.
  // Keeping the same aspect ratio prevents stretching or cropping.
  static const double bannerAspectRatio = 1440 / 1064;

  const HowItWorksBlock({super.key});

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.fromLTRB(22, 30, 22, 0),
      child: Semantics(
        label:
            'How it works. Pick your bottle, choose a recipe, mix and enjoy.',
        image: true,
        child: ClipRRect(
          borderRadius: BorderRadius.circular(24),
          child: AspectRatio(
            aspectRatio: bannerAspectRatio,
            child: Image.asset(
              assetPath,
              fit: BoxFit.contain,
              alignment: Alignment.center,
              filterQuality: FilterQuality.high,
              errorBuilder: (_, _, _) => const HowItWorksAssetFallback(),
            ),
          ),
        ),
      ),
    );
  }
}

class HowItWorksAssetFallback extends StatelessWidget {
  const HowItWorksAssetFallback({super.key});

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.all(18),
      decoration: BoxDecoration(
        color: EbtlColors.white.withValues(alpha: 0.88),
        borderRadius: BorderRadius.circular(24),
        border: Border.all(color: EbtlColors.border),
      ),
      child: Column(
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          Text(
            'How it works',
            textAlign: TextAlign.center,
            style: GoogleFonts.playfairDisplay(
              fontSize: 26,
              fontWeight: FontWeight.w800,
              color: EbtlColors.navy,
            ),
          ),
          const SizedBox(height: 14),
          Text(
            '1. Pick your bottle\n2. Choose a recipe\n3. Mix and enjoy',
            textAlign: TextAlign.center,
            style: GoogleFonts.manrope(
              fontSize: 14,
              height: 1.45,
              fontWeight: FontWeight.w800,
              color: EbtlColors.ink,
            ),
          ),
        ],
      ),
    );
  }
}

class HowItWorksStep {
  final String number;
  final IconData icon;
  final String title;
  final String description;
  final Color color;

  const HowItWorksStep({
    required this.number,
    required this.icon,
    required this.title,
    required this.description,
    required this.color,
  });
}

class HowItWorksCard extends StatelessWidget {
  final HowItWorksStep step;

  const HowItWorksCard({super.key, required this.step});

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.fromLTRB(16, 14, 16, 14),
      decoration: BoxDecoration(
        color: EbtlColors.white.withValues(alpha: 0.82),
        borderRadius: BorderRadius.circular(20),
        border: Border.all(color: EbtlColors.border),
        boxShadow: [
          BoxShadow(
            color: Colors.black.withValues(alpha: 0.035),
            blurRadius: 18,
            offset: const Offset(0, 8),
          ),
        ],
      ),
      child: Row(
        children: [
          Stack(
            clipBehavior: Clip.none,
            children: [
              Container(
                width: 58,
                height: 58,
                decoration: BoxDecoration(
                  color: step.color,
                  shape: BoxShape.circle,
                ),
                child: Icon(step.icon, color: EbtlColors.navy, size: 28),
              ),
              Positioned(
                left: -4,
                top: -4,
                child: Container(
                  width: 25,
                  height: 25,
                  decoration: const BoxDecoration(
                    color: EbtlColors.coral,
                    shape: BoxShape.circle,
                  ),
                  alignment: Alignment.center,
                  child: Text(
                    step.number,
                    style: GoogleFonts.manrope(
                      color: Colors.white,
                      fontSize: 12,
                      fontWeight: FontWeight.w900,
                    ),
                  ),
                ),
              ),
            ],
          ),
          const SizedBox(width: 16),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  step.title,
                  style: GoogleFonts.manrope(
                    fontSize: 15,
                    color: EbtlColors.navy,
                    fontWeight: FontWeight.w900,
                  ),
                ),
                const SizedBox(height: 5),
                Text(
                  step.description,
                  style: GoogleFonts.manrope(
                    fontSize: 13,
                    height: 1.35,
                    color: EbtlColors.ink,
                    fontWeight: FontWeight.w500,
                  ),
                ),
              ],
            ),
          ),
          const Icon(Icons.chevron_right, color: EbtlColors.muted),
        ],
      ),
    );
  }
}
