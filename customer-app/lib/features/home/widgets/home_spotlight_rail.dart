import 'package:flutter/material.dart';

import '../../../core/theme/ebtl_colors.dart';
import '../../../core/theme/home_screen_visuals.dart';
import '../../../models/spotlight_models.dart';
import '../../../shared/widgets/network_or_asset_image.dart';

/// Home's "The Spotlight" rail: a horizontal run of banner artwork, each card
/// tapping into its own sheet of curated products.
///
/// The cards carry no overlay copy — a Spotlight banner's message is set in the
/// artwork marketing uploads, and the title only appears once the sheet is open.
/// Each card is exactly [HomeScreenVisuals.spotlightBannerAspectRatio], so the
/// image fills it without cropping whatever marketing supplied.
class HomeSpotlightRail extends StatelessWidget {
  final List<SpotlightBanner> banners;
  final ValueChanged<SpotlightBanner> onOpenBanner;

  const HomeSpotlightRail({
    super.key,
    required this.banners,
    required this.onOpenBanner,
  });

  @override
  Widget build(BuildContext context) {
    return SizedBox(
      height: HomeScreenVisuals.spotlightBannerHeight,
      child: ListView.separated(
        scrollDirection: Axis.horizontal,
        padding: const EdgeInsets.symmetric(horizontal: 22),
        itemCount: banners.length,
        separatorBuilder: (_, _) =>
            const SizedBox(width: HomeScreenVisuals.spotlightBannerGap),
        itemBuilder: (context, index) {
          final banner = banners[index];

          return _SpotlightCard(
            banner: banner,
            onTap: () => onOpenBanner(banner),
          );
        },
      ),
    );
  }
}

class _SpotlightCard extends StatelessWidget {
  final SpotlightBanner banner;
  final VoidCallback onTap;

  const _SpotlightCard({required this.banner, required this.onTap});

  @override
  Widget build(BuildContext context) {
    return Semantics(
      button: true,
      label: banner.title,
      child: GestureDetector(
        behavior: HitTestBehavior.opaque,
        onTap: onTap,
        child: Container(
          width: HomeScreenVisuals.spotlightBannerWidth,
          decoration: BoxDecoration(
            color: EbtlColors.sand,
            borderRadius: BorderRadius.circular(16),
            boxShadow: [
              BoxShadow(
                color: Colors.black.withValues(alpha: 0.04),
                blurRadius: 18,
                offset: const Offset(0, 8),
              ),
            ],
          ),
          child: ClipRRect(
            borderRadius: BorderRadius.circular(16),
            child: NetworkOrAssetImage(
              imageUrl: banner.imageUrl,
              asset: 'assets/banners/explore_hero.webp',
            ),
          ),
        ),
      ),
    );
  }
}
