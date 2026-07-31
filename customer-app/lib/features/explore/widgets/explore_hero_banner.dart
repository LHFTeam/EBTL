import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';

import '../../../core/theme/ebtl_colors.dart';

/// The "Match My Bottle" hero at the top of the Explore screen. Tapping it
/// opens the Cocktail Finder, which no longer has its own bottom-nav tab.
class ExploreHeroBanner extends StatelessWidget {
  static const String assetPath = 'assets/banners/explore_hero.webp';

  /// The supplied artwork is roughly 1772 x 886.
  static const double bannerAspectRatio = 2.0;

  static const String headline = 'Match My Bottle';
  static const String subheadline =
      'See cocktails made for the bottle you have.';

  final VoidCallback onTap;

  const ExploreHeroBanner({super.key, required this.onTap});

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.fromLTRB(22, 18, 22, 0),
      child: Semantics(
        button: true,
        label: '$headline. $subheadline',
        child: Material(
          color: EbtlColors.seafoam,
          borderRadius: BorderRadius.circular(24),
          clipBehavior: Clip.antiAlias,
          child: InkWell(
            onTap: onTap,
            child: AspectRatio(
              aspectRatio: bannerAspectRatio,
              child: Stack(
                fit: StackFit.expand,
                children: [
                  Image.asset(
                    assetPath,
                    fit: BoxFit.cover,
                    filterQuality: FilterQuality.high,
                    errorBuilder: (_, _, _) => const _ExploreHeroFallbackArt(),
                  ),
                  // Keeps the copy legible if the artwork is ever swapped for
                  // something busier on the left.
                  const DecoratedBox(
                    decoration: BoxDecoration(
                      gradient: LinearGradient(
                        colors: [
                          Color(0x9EFFF8EE),
                          Color(0x4DFFF8EE),
                          Color(0x00FFF8EE),
                        ],
                        stops: [0, 0.4, 0.62],
                      ),
                    ),
                  ),
                  const _ExploreHeroCopy(),
                  const Positioned(right: 14, bottom: 14, child: _HeroArrow()),
                ],
              ),
            ),
          ),
        ),
      ),
    );
  }
}

/// Copy is constrained to the left half of the banner so it never collides
/// with the bottle-and-glass artwork on the right.
class _ExploreHeroCopy extends StatelessWidget {
  const _ExploreHeroCopy();

  @override
  Widget build(BuildContext context) {
    return Align(
      alignment: Alignment.centerLeft,
      child: FractionallySizedBox(
        widthFactor: 0.5,
        child: Padding(
          padding: const EdgeInsets.fromLTRB(18, 0, 8, 0),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            mainAxisAlignment: MainAxisAlignment.center,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                ExploreHeroBanner.headline,
                style: GoogleFonts.playfairDisplay(
                  fontSize: 21,
                  height: 1.05,
                  fontWeight: FontWeight.w800,
                  color: EbtlColors.navy,
                ),
              ),
              const SizedBox(height: 5),
              Text(
                ExploreHeroBanner.subheadline,
                maxLines: 3,
                overflow: TextOverflow.ellipsis,
                style: GoogleFonts.manrope(
                  fontSize: 11,
                  height: 1.35,
                  fontWeight: FontWeight.w600,
                  color: EbtlColors.ink.withValues(alpha: 0.78),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

class _HeroArrow extends StatelessWidget {
  const _HeroArrow();

  @override
  Widget build(BuildContext context) {
    return Container(
      width: 40,
      height: 40,
      decoration: BoxDecoration(
        color: EbtlColors.navy,
        shape: BoxShape.circle,
        boxShadow: [
          BoxShadow(
            color: EbtlColors.navy.withValues(alpha: 0.3),
            blurRadius: 18,
            offset: const Offset(0, 8),
          ),
        ],
      ),
      child: const Icon(Icons.arrow_forward, size: 20, color: EbtlColors.white),
    );
  }
}

/// Shown until `assets/banners/explore_hero.webp` is added to the bundle, and
/// as a safety net if it ever fails to decode.
class _ExploreHeroFallbackArt extends StatelessWidget {
  const _ExploreHeroFallbackArt();

  @override
  Widget build(BuildContext context) {
    return const DecoratedBox(
      decoration: BoxDecoration(
        gradient: LinearGradient(
          begin: Alignment.topLeft,
          end: Alignment.bottomRight,
          colors: [EbtlColors.seafoam, EbtlColors.sand],
        ),
      ),
    );
  }
}
