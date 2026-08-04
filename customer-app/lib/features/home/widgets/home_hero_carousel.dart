import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';

import '../../../core/theme/ebtl_colors.dart';
import '../../../core/theme/home_screen_visuals.dart';
import '../../../models/common_models.dart';
import '../../../shared/widgets/network_or_asset_image.dart';

/// The hero carousel: slides that peek in from both sides with the active one
/// centered. Home shows it in every state except a live order.
///
/// The slides are a merchandising slot on the home payload — image, headline,
/// body, deep link and order, edited in the dashboard's Marketing → Banners tab
/// (`home_hero_banners`). Only the image and the order are required, so a slide
/// may be a bare image, and one without a deep link is not tappable.
///
/// With no banners on the payload the carousel falls back to the three bundled
/// slides below, which is also what ships before marketing has created any.
class HomeHeroCarousel extends StatefulWidget {
  /// CMS slides in display order. Already filtered to renderable ones by
  /// [AppData]; empty selects the bundled fallback.
  final List<HomeHeroBanner> banners;

  /// Follows a slide's deep link. Never called for a slide without one.
  final ValueChanged<HomeHeroBanner> onOpenBanner;

  const HomeHeroCarousel({
    super.key,
    required this.banners,
    required this.onOpenBanner,
  });

  @override
  State<HomeHeroCarousel> createState() => _HomeHeroCarouselState();
}

class _HomeHeroCarouselState extends State<HomeHeroCarousel> {
  /// The bundled slides, used when the payload carries no banners.
  static const List<Widget> _fallbackSlides = [
    _BrandSlide(),
    _HowItWorksSlide(),
    _StepsSlide(),
  ];

  static const Duration _slideDuration = Duration(milliseconds: 280);
  static const Duration _dotDuration = Duration(milliseconds: 180);

  PageController? controller;
  double? controllerViewportFraction;
  int index = 0;

  bool get usesFallback => widget.banners.isEmpty;

  int get slideCount =>
      usesFallback ? _fallbackSlides.length : widget.banners.length;

  /// The fallback set opens on its middle slide so both neighbours are visible
  /// on load. CMS slides open on the first one — marketing ordered them, and
  /// the first is the one they expect to be seen.
  int get initialIndex => usesFallback ? 1 : 0;

  @override
  void initState() {
    super.initState();
    index = initialIndex;
  }

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();

    // The peek is a fixed slide width centered in whatever viewport the phone
    // gives us, so the fraction is derived from the screen rather than pinned.
    final viewportWidth = MediaQuery.sizeOf(context).width;
    final pitch =
        HomeScreenVisuals.heroSlideWidth + HomeScreenVisuals.heroSlideGap;
    final fraction = viewportWidth <= 0
        ? 1.0
        : (pitch / viewportWidth).clamp(0.1, 1.0);

    if (controllerViewportFraction == fraction) return;

    controller?.dispose();
    controllerViewportFraction = fraction;
    controller = PageController(
      initialPage: index,
      viewportFraction: fraction,
    );
  }

  @override
  void didUpdateWidget(HomeHeroCarousel oldWidget) {
    super.didUpdateWidget(oldWidget);

    // A refresh can shorten the carousel — or swap the CMS slides in over the
    // fallback — under a page the controller is already parked on.
    if (index < slideCount) return;

    final target = slideCount - 1;
    setState(() => index = target);
    controller?.jumpToPage(target);
  }

  @override
  void dispose() {
    controller?.dispose();
    super.dispose();
  }

  void goToSlide(int target) {
    controller?.animateToPage(
      target,
      duration: _slideDuration,
      curve: Curves.ease,
    );
  }

  Widget buildSlide(int slideIndex) {
    if (usesFallback) return _fallbackSlides[slideIndex];

    final banner = widget.banners[slideIndex];

    return _BannerSlide(
      banner: banner,
      onTap: banner.link.isTappable
          ? () => widget.onOpenBanner(banner)
          : null,
    );
  }

  @override
  Widget build(BuildContext context) {
    final pageController = controller;
    if (pageController == null) return const SizedBox.shrink();

    return Column(
      children: [
        SizedBox(
          height: HomeScreenVisuals.heroSlideHeight,
          child: PageView.builder(
            controller: pageController,
            padEnds: true,
            itemCount: slideCount,
            onPageChanged: (value) => setState(() => index = value),
            itemBuilder: (context, slideIndex) {
              return Padding(
                padding: const EdgeInsets.symmetric(
                  horizontal: HomeScreenVisuals.heroSlideGap / 2,
                ),
                child: buildSlide(slideIndex),
              );
            },
          ),
        ),
        // 34pt tall so the 6pt dots sit exactly 14 below the track and 20
        // above the next module, while each dot still gets a touch target
        // wider and taller than the pip it draws. A single slide gets no dots
        // — there is nowhere to page to.
        if (slideCount > 1)
          SizedBox(
            height: 34,
            child: Row(
              mainAxisAlignment: MainAxisAlignment.center,
              children: List.generate(slideCount, (dotIndex) {
                final active = dotIndex == index;

                return GestureDetector(
                  behavior: HitTestBehavior.opaque,
                  onTap: () => goToSlide(dotIndex),
                  child: SizedBox(
                    width: 44,
                    height: 34,
                    child: Center(
                      child: AnimatedContainer(
                        duration: _dotDuration,
                        curve: Curves.ease,
                        width: active ? 22 : 6,
                        height: 6,
                        decoration: BoxDecoration(
                          color: active ? EbtlColors.coral : EbtlColors.border,
                          borderRadius: BorderRadius.circular(999),
                        ),
                      ),
                    ),
                  ),
                );
              }),
            ),
          ),
      ],
    );
  }
}

/// A CMS slide: the image, with the headline and body over a scrim when there
/// is any copy to show.
class _BannerSlide extends StatelessWidget {
  final HomeHeroBanner banner;
  final VoidCallback? onTap;

  const _BannerSlide({required this.banner, this.onTap});

  @override
  Widget build(BuildContext context) {
    final headline = banner.headline?.trim() ?? '';
    final body = banner.body?.trim() ?? '';

    final slide = Container(
      decoration: BoxDecoration(
        color: EbtlColors.sand,
        borderRadius: BorderRadius.circular(20),
        border: Border.all(color: EbtlColors.border),
        boxShadow: [
          BoxShadow(
            color: Colors.black.withValues(alpha: 0.04),
            blurRadius: 18,
            offset: const Offset(0, 8),
          ),
        ],
      ),
      child: ClipRRect(
        borderRadius: BorderRadius.circular(20),
        child: Stack(
          fit: StackFit.expand,
          children: [
            NetworkOrAssetImage(
              imageUrl: banner.imageUrl,
              // If the uploaded image cannot be fetched the slide still reads
              // as a hero rather than an empty box.
              asset: 'assets/banners/explore_hero.webp',
            ),
            // Marketing supplies the artwork, so the copy has to stay legible
            // over whatever they upload — hence the scrim rather than tinted
            // text. No copy, no scrim: the image speaks for itself.
            if (banner.hasText) ...[
              DecoratedBox(
                decoration: BoxDecoration(
                  gradient: LinearGradient(
                    begin: Alignment.bottomLeft,
                    end: Alignment.topRight,
                    colors: [
                      EbtlColors.navy.withValues(alpha: 0.78),
                      EbtlColors.navy.withValues(alpha: 0.08),
                    ],
                  ),
                ),
              ),
              Padding(
                padding: const EdgeInsets.all(18),
                child: Column(
                  mainAxisAlignment: MainAxisAlignment.end,
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    if (headline.isNotEmpty)
                      Text(
                        headline,
                        maxLines: 2,
                        overflow: TextOverflow.ellipsis,
                        style: GoogleFonts.playfairDisplay(
                          fontSize: 20,
                          height: 1.16,
                          fontWeight: FontWeight.w800,
                          color: EbtlColors.white,
                        ),
                      ),
                    if (headline.isNotEmpty && body.isNotEmpty)
                      const SizedBox(height: 6),
                    if (body.isNotEmpty)
                      Text(
                        body,
                        maxLines: 2,
                        overflow: TextOverflow.ellipsis,
                        style: GoogleFonts.manrope(
                          fontSize: 12.5,
                          height: 1.35,
                          letterSpacing: 0,
                          fontWeight: FontWeight.w600,
                          color: EbtlColors.white,
                        ),
                      ),
                  ],
                ),
              ),
            ],
          ],
        ),
      ),
    );

    if (onTap == null) {
      return Semantics(
        label: banner.hasText ? null : 'Promotion',
        image: true,
        child: slide,
      );
    }

    return Semantics(
      button: true,
      child: GestureDetector(
        behavior: HitTestBehavior.opaque,
        onTap: onTap,
        child: slide,
      ),
    );
  }
}

class _BrandSlide extends StatelessWidget {
  const _BrandSlide();

  @override
  Widget build(BuildContext context) {
    return Container(
      decoration: BoxDecoration(
        color: EbtlColors.seafoam,
        borderRadius: BorderRadius.circular(20),
        border: Border.all(color: EbtlColors.border),
        boxShadow: [
          BoxShadow(
            color: Colors.black.withValues(alpha: 0.04),
            blurRadius: 18,
            offset: const Offset(0, 8),
          ),
        ],
      ),
      child: ClipRRect(
        borderRadius: BorderRadius.circular(20),
        child: Stack(
          fit: StackFit.expand,
          children: [
            Opacity(
              opacity: 0.45,
              child: Image.asset(
                'assets/banners/explore_hero.webp',
                fit: BoxFit.cover,
                errorBuilder: (_, _, _) => const SizedBox.shrink(),
              ),
            ),
            Padding(
              padding: const EdgeInsets.all(18),
              // Same guard as the steps slide: two 22pt display lines plus the
              // body nearly fill the fixed 148pt box, so a font metric
              // difference or a larger text scale would overflow it. Scaling
              // down keeps the block whole and does nothing at design sizes.
              child: FittedBox(
                fit: BoxFit.scaleDown,
                alignment: Alignment.centerLeft,
                child: SizedBox(
                  // The slide's own width, less its 18pt padding on both sides.
                  width: HomeScreenVisuals.heroSlideWidth - 36,
                  child: Column(
                    mainAxisSize: MainAxisSize.min,
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        'You bring the bottle.',
                        style: GoogleFonts.playfairDisplay(
                          fontSize: 22,
                          height: 1.16,
                          fontWeight: FontWeight.w800,
                          color: EbtlColors.navy,
                        ),
                      ),
                      Text(
                        'We bring the magic.',
                        style: GoogleFonts.playfairDisplay(
                          fontSize: 22,
                          height: 1.16,
                          fontWeight: FontWeight.w600,
                          fontStyle: FontStyle.italic,
                          color: EbtlColors.coral,
                        ),
                      ),
                      const SizedBox(height: 8),
                      SizedBox(
                        width: 200,
                        child: Text(
                          'Mixers, garnish and ice, packed for the beach.',
                          style: GoogleFonts.manrope(
                            fontSize: 12.5,
                            height: 1.4,
                            fontWeight: FontWeight.w600,
                            color: EbtlColors.navy.withValues(alpha: 0.7),
                          ),
                        ),
                      ),
                    ],
                  ),
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _HowItWorksSlide extends StatelessWidget {
  const _HowItWorksSlide();

  @override
  Widget build(BuildContext context) {
    return Semantics(
      label:
          'How it works. Pick your bottle, choose a recipe, mix and enjoy.',
      image: true,
      child: Container(
        decoration: BoxDecoration(
          color: EbtlColors.cream,
          borderRadius: BorderRadius.circular(20),
          border: Border.all(color: EbtlColors.border),
          boxShadow: [
            BoxShadow(
              color: Colors.black.withValues(alpha: 0.04),
              blurRadius: 18,
              offset: const Offset(0, 8),
            ),
          ],
        ),
        child: ClipRRect(
          borderRadius: BorderRadius.circular(20),
          child: Image.asset(
            'assets/banners/how_it_works_banner_2.webp',
            fit: BoxFit.cover,
            errorBuilder: (_, _, _) => const SizedBox.shrink(),
          ),
        ),
      ),
    );
  }
}

class _StepsSlide extends StatelessWidget {
  const _StepsSlide();

  static const List<String> _steps = [
    'Pick the liquor you already own.',
    'We pack the mixers, garnish and ice.',
    'Collect at your beach cart. Pour.',
  ];

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 18, vertical: 16),
      decoration: BoxDecoration(
        color: EbtlColors.navy,
        borderRadius: BorderRadius.circular(20),
        boxShadow: [
          BoxShadow(
            color: EbtlColors.navy.withValues(alpha: 0.18),
            blurRadius: 22,
            offset: const Offset(0, 10),
          ),
        ],
      ),
      // The slide is a fixed 148pt box and the headline plus three steps fill
      // nearly all of it, so anything that makes the type taller — a font
      // metric difference, a larger text scale — would overflow. Scaling the
      // block down keeps it whole; at the design's own sizes it does nothing.
      child: FittedBox(
        fit: BoxFit.scaleDown,
        alignment: Alignment.centerLeft,
        child: SizedBox(
          // The slide's own width, less its 18pt padding on both sides.
          width: HomeScreenVisuals.heroSlideWidth - 36,
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                'Collect at your beach cart.',
                style: GoogleFonts.playfairDisplay(
                  fontSize: 19,
                  height: 1.15,
                  fontWeight: FontWeight.w800,
                  color: EbtlColors.white,
                ),
              ),
              const SizedBox(height: 10),
              for (var step = 0; step < _steps.length; step++) ...[
                if (step > 0) const SizedBox(height: 7),
                Row(
                  children: [
                    Container(
                      width: 24,
                      height: 24,
                      alignment: Alignment.center,
                      decoration: const BoxDecoration(
                        color: EbtlColors.seafoam,
                        shape: BoxShape.circle,
                      ),
                      child: Text(
                        '${step + 1}',
                        style: GoogleFonts.manrope(
                          fontSize: 12,
                          height: 1,
                          fontWeight: FontWeight.w900,
                          color: EbtlColors.navy,
                        ),
                      ),
                    ),
                    const SizedBox(width: 10),
                    Expanded(
                      child: Text(
                        _steps[step],
                        style: GoogleFonts.manrope(
                          fontSize: 12.5,
                          height: 1.3,
                          // The design tracks body copy at 0; without this the
                          // theme's letter spacing wraps the longest step.
                          letterSpacing: 0,
                          fontWeight: FontWeight.w600,
                          color: EbtlColors.white,
                        ),
                      ),
                    ),
                  ],
                ),
              ],
            ],
          ),
        ),
      ),
    );
  }
}
