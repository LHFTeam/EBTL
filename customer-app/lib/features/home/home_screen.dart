import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';

import '../../core/theme/ebtl_colors.dart';
import '../../core/theme/home_screen_visuals.dart';
import '../../models/app_data.dart';
import '../../models/cocktail_models.dart';
import '../../models/common_models.dart';
import '../../shared/widgets/app_state_widgets.dart';
import '../../shared/widgets/bottle_widgets.dart';
import '../../shared/widgets/brand_widgets.dart';
import '../../shared/widgets/cocktail_card_widgets.dart';
import '../../shared/widgets/network_or_asset_image.dart';
import '../../shared/widgets/section_block.dart';
import 'widgets/how_it_works_block.dart';

class HomeScreen extends StatelessWidget {
  final AppData data;
  final VoidCallback onOpenFinder;
  final ValueChanged<ServiceLocation> onLocationSelected;
  final ValueChanged<Cocktail> onOpenCocktail;
  final ValueChanged<LiquorType> onOpenFinderWithBottle;
  final int unreadNotificationCount;
  final VoidCallback onOpenNotifications;

  const HomeScreen({
    super.key,
    required this.data,
    required this.onOpenFinder,
    required this.onOpenFinderWithBottle,
    required this.onLocationSelected,
    required this.onOpenCocktail,
    required this.unreadNotificationCount,
    required this.onOpenNotifications,
  });

  @override
  Widget build(BuildContext context) {
    final featured = data.featuredCocktails;

    return SafeArea(
      child: CustomScrollView(
        slivers: [
          SliverToBoxAdapter(
            child: HeroHomeHeader(
              hero: data.hero,
              onOpenFinder: onOpenFinder,
              unreadNotificationCount: unreadNotificationCount,
              onOpenNotifications: onOpenNotifications,
            ),
          ),
          if (data.serviceAreas.isNotEmpty)
            SliverToBoxAdapter(
              child: ServiceAreaSection(
                serviceAreas: data.serviceAreas,
                selectedLocationId: data.selectedLocationId,
                onLocationSelected: onLocationSelected,
              ),
            ),
          SliverToBoxAdapter(
            child: SectionBlock(
              icon: Icons.local_bar_outlined,
              title: 'Choose Your Bottle',
              subtitle: 'Pick the liquor you already have.',
              child: SizedBox(
                height: 130,
                child: ListView.separated(
                  padding: const EdgeInsets.only(left: 22, right: 22),
                  scrollDirection: Axis.horizontal,
                  itemCount: data.liquorTypes.length,
                  separatorBuilder: (_, _) => const SizedBox(width: 8),
                  itemBuilder: (context, index) {
                    final liquor = data.liquorTypes[index];

                    return BottleCard(
                      liquor: liquor,
                      onTap: () => onOpenFinderWithBottle(liquor),
                    );
                  },
                ),
              ),
            ),
          ),
          SliverToBoxAdapter(
            child: SectionBlock(
              icon: Icons.local_bar_outlined,
              title: 'Featured Cocktails',
              actionText: 'View all',
              onAction: onOpenFinder,
              child: featured.isEmpty
                  ? const EmptyStateCard(
                      message: 'No featured cocktails are available right now.',
                    )
                  : SizedBox(
                      height: HomeScreenVisuals.featuredProductCardHeight,
                      child: ListView.separated(
                        padding: const EdgeInsets.only(left: 22, right: 22),
                        scrollDirection: Axis.horizontal,
                        itemCount: featured.length,
                        separatorBuilder: (_, _) => const SizedBox(width: 12),
                        itemBuilder: (context, index) {
                          return CocktailSmallCard(
                            cocktail: featured[index],
                            onTap: () => onOpenCocktail(featured[index]),
                          );
                        },
                      ),
                    ),
            ),
          ),
          const SliverToBoxAdapter(child: HowItWorksBlock()),
          const SliverToBoxAdapter(child: SizedBox(height: 24)),
        ],
      ),
    );
  }
}

class HeroHomeHeader extends StatelessWidget {
  final HeroContent hero;
  final VoidCallback onOpenFinder;
  final int unreadNotificationCount;
  final VoidCallback onOpenNotifications;

  const HeroHomeHeader({
    super.key,
    required this.hero,
    required this.onOpenFinder,
    required this.unreadNotificationCount,
    required this.onOpenNotifications,
  });

  @override
  Widget build(BuildContext context) {
    return Container(
      height: 470,
      decoration: const BoxDecoration(color: EbtlColors.cream),
      child: Stack(
        children: [
          Positioned.fill(
            top: 120,
            child: Opacity(
              opacity: 0.45,
              child: hero.imageUrl != null
                  ? NetworkOrAssetImage(
                      imageUrl: hero.imageUrl,
                      asset: 'assets/images/home_hero.jpg',
                    )
                  : const AssetOrGradientImage(
                      asset: 'assets/images/home_hero.jpg',
                      borderRadius: BorderRadius.zero,
                      gradientStart: EbtlColors.blush,
                      gradientEnd: EbtlColors.sand,
                    ),
            ),
          ),
          Positioned(
            left: 22,
            right: 22,
            top: 14,
            child: Row(
              children: [
                const EbtlLogo(),
                const Spacer(),
                NotificationsIconButton(
                  unreadCount: unreadNotificationCount,
                  onTap: onOpenNotifications,
                ),
              ],
            ),
          ),
          Positioned(
            left: 22,
            right: 22,
            top: 130,
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  'Hey there, Cocktail Lover! 👋',
                  style: GoogleFonts.manrope(
                    fontSize: 18,
                    fontWeight: FontWeight.w800,
                    color: EbtlColors.navy,
                  ),
                ),
                const SizedBox(height: 20),
                Text(
                  'You bring the bottle.',
                  style: GoogleFonts.playfairDisplay(
                    fontSize: 32,
                    height: 1.25,
                    fontWeight: FontWeight.w800,
                    color: EbtlColors.navy,
                  ),
                ),
                Text(
                  'We bring the magic.',
                  style: GoogleFonts.playfairDisplay(
                    fontSize: 26,
                    height: 1.1,
                    fontWeight: FontWeight.w600,
                    fontStyle: FontStyle.italic,
                    color: EbtlColors.coral,
                  ),
                ),
                const SizedBox(height: 24),
                Text(
                  hero.headline,
                  maxLines: 3,
                  overflow: TextOverflow.ellipsis,
                  style: GoogleFonts.manrope(
                    fontSize: 17,
                    height: 1.55,
                    fontWeight: FontWeight.w500,
                    color: EbtlColors.ink,
                  ),
                ),
                const SizedBox(height: 28),
                SizedBox(
                  height: 64,
                  child: ElevatedButton.icon(
                    onPressed: onOpenFinder,
                    icon: const Icon(
                      Icons.liquor_outlined,
                      color: Colors.white,
                    ),
                    label: Text(hero.primaryCtaLabel),
                    style: ElevatedButton.styleFrom(
                      backgroundColor: EbtlColors.coral,
                      foregroundColor: Colors.white,
                      elevation: 0,
                      padding: const EdgeInsets.symmetric(horizontal: 24),
                      shape: RoundedRectangleBorder(
                        borderRadius: BorderRadius.circular(22),
                      ),
                      textStyle: GoogleFonts.manrope(
                        fontSize: 16,
                        fontWeight: FontWeight.w800,
                      ),
                    ),
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

class ServiceAreaSection extends StatelessWidget {
  final List<ServiceLocation> serviceAreas;
  final String? selectedLocationId;
  final ValueChanged<ServiceLocation> onLocationSelected;

  const ServiceAreaSection({
    super.key,
    required this.serviceAreas,
    required this.selectedLocationId,
    required this.onLocationSelected,
  });

  @override
  Widget build(BuildContext context) {
    return SectionBlock(
      icon: Icons.beach_access_outlined,
      title: selectedLocationId == null
          ? 'Choose Your Beach Cart'
          : 'Ordering From',
      subtitle: selectedLocationId == null
          ? 'Select your location for real-time availability.'
          : 'Availability is checked against this beach cart.',
      child: SizedBox(
        height: 100,
        child: ListView.separated(
          padding: const EdgeInsets.only(left: 22, right: 22),
          scrollDirection: Axis.horizontal,
          itemCount: serviceAreas.length,
          separatorBuilder: (_, _) => const SizedBox(width: 12),
          itemBuilder: (context, index) {
            final location = serviceAreas[index];
            final selected = location.id == selectedLocationId;
            return ServiceAreaCard(
              location: location,
              selected: selected,
              onTap: () => onLocationSelected(location),
            );
          },
        ),
      ),
    );
  }
}

class ServiceAreaCard extends StatelessWidget {
  final ServiceLocation location;
  final bool selected;
  final VoidCallback onTap;

  const ServiceAreaCard({
    super.key,
    required this.location,
    required this.selected,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    return Material(
      color: Colors.transparent,
      child: InkWell(
        onTap: onTap,
        borderRadius: BorderRadius.circular(20),
        child: AnimatedContainer(
          duration: const Duration(milliseconds: 180),
          width: 235,
          padding: const EdgeInsets.all(16),
          decoration: BoxDecoration(
            color: EbtlColors.white.withValues(alpha: 0.9),
            borderRadius: BorderRadius.circular(20),
            border: Border.all(
              color: selected ? EbtlColors.coral : EbtlColors.border,
              width: selected ? 1.5 : 1,
            ),
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
              Container(
                width: 52,
                height: 52,
                decoration: BoxDecoration(
                  color: selected ? EbtlColors.blush : EbtlColors.seafoam,
                  shape: BoxShape.circle,
                ),
                child: Icon(
                  selected ? Icons.check : Icons.beach_access_outlined,
                  color: EbtlColors.navy,
                ),
              ),
              const SizedBox(width: 14),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  mainAxisAlignment: MainAxisAlignment.center,
                  children: [
                    Text(
                      location.name,
                      maxLines: 2,
                      overflow: TextOverflow.ellipsis,
                      style: GoogleFonts.manrope(
                        color: EbtlColors.navy,
                        fontSize: 15,
                        fontWeight: FontWeight.w900,
                        height: 1.15,
                      ),
                    ),
                    const SizedBox(height: 6),
                    Text(
                      location.subtitle,
                      maxLines: 2,
                      overflow: TextOverflow.ellipsis,
                      style: GoogleFonts.manrope(
                        color: EbtlColors.muted,
                        fontSize: 12,
                        fontWeight: FontWeight.w700,
                        height: 1.2,
                      ),
                    ),
                  ],
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}
