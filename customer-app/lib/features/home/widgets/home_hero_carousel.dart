import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';

import '../../../core/theme/ebtl_colors.dart';
import '../../../core/theme/home_screen_visuals.dart';

/// The first-run education carousel: three slides that peek in from both sides
/// with the active one centered.
///
/// The slide copy is hardcoded, matching the design. It should become a
/// merchandising slot on the home payload (image, headline, body, deep link,
/// order) so marketing can change it without a release — that endpoint does
/// not exist yet.
class HomeHeroCarousel extends StatefulWidget {
  const HomeHeroCarousel({super.key});

  @override
  State<HomeHeroCarousel> createState() => _HomeHeroCarouselState();
}

class _HomeHeroCarouselState extends State<HomeHeroCarousel> {
  static const int _slideCount = 3;

  /// Opens on the middle slide so both neighbours are visible on load.
  static const int _initialIndex = 1;

  static const Duration _slideDuration = Duration(milliseconds: 280);
  static const Duration _dotDuration = Duration(milliseconds: 180);

  PageController? controller;
  double? controllerViewportFraction;
  int index = _initialIndex;

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

  @override
  Widget build(BuildContext context) {
    final pageController = controller;
    if (pageController == null) return const SizedBox.shrink();

    const slides = [
      _BrandSlide(),
      _HowItWorksSlide(),
      _StepsSlide(),
    ];

    return Column(
      children: [
        SizedBox(
          height: HomeScreenVisuals.heroSlideHeight,
          child: PageView.builder(
            controller: pageController,
            padEnds: true,
            itemCount: _slideCount,
            onPageChanged: (value) => setState(() => index = value),
            itemBuilder: (context, slideIndex) {
              return Padding(
                padding: const EdgeInsets.symmetric(
                  horizontal: HomeScreenVisuals.heroSlideGap / 2,
                ),
                child: slides[slideIndex],
              );
            },
          ),
        ),
        // 34pt tall so the 6pt dots sit exactly 14 below the track and 20
        // above the next module, while each dot still gets a touch target
        // wider and taller than the pip it draws.
        SizedBox(
          height: 34,
          child: Row(
            mainAxisAlignment: MainAxisAlignment.center,
            children: List.generate(_slideCount, (dotIndex) {
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
              child: Column(
                mainAxisAlignment: MainAxisAlignment.center,
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
