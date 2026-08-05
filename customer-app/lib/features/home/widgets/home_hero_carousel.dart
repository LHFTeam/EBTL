import 'dart:async';

import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:visibility_detector/visibility_detector.dart';

import '../../../core/theme/ebtl_colors.dart';
import '../../../core/theme/home_screen_visuals.dart';
import '../../../models/common_models.dart';
import '../../../shared/widgets/network_or_asset_image.dart';

/// The hero carousel: slides that peek in from both sides, with the centered
/// one drawn full size and its neighbours scaled down, so a slide grows as it
/// arrives and shrinks as it leaves. Home shows it in every state except a live
/// order.
///
/// The slides are a merchandising slot on the home payload — image, headline,
/// body, deep link and order, edited in the dashboard's Marketing → Banners tab
/// (`home_hero_banners`). Only the image and the order are required, so a slide
/// may be a bare image, and one without a deep link is not tappable.
///
/// With no banners on the payload the carousel falls back to the three bundled
/// slides below, which is also what ships before marketing has created any.
///
/// It advances itself every [rotationInterval] and, with more than one slide,
/// pages endlessly in both directions so neither end is a dead stop. A swipe
/// takes over: the timer is dropped the moment a drag starts and only restarts
/// once the carousel settles again, giving the customer a full interval on
/// whatever they landed on.
///
/// It only rotates while it is actually on screen. Home stays mounted behind a
/// pushed screen and behind the other tabs (RootShell's IndexedStack), so
/// without this the carousel would advance where nobody can see it and the
/// customer would come back to a slide they never watched arrive.
class HomeHeroCarousel extends StatefulWidget {
  /// CMS slides in display order. Already filtered to renderable ones by
  /// [AppData]; empty selects the bundled fallback.
  final List<HomeHeroBanner> banners;

  /// How long a slide dwells before the carousel advances itself, from the
  /// dashboard's rotation setting.
  final Duration rotationInterval;

  /// Follows a slide's deep link. Never called for a slide without one.
  final ValueChanged<HomeHeroBanner> onOpenBanner;

  const HomeHeroCarousel({
    super.key,
    required this.banners,
    required this.onOpenBanner,
    this.rotationInterval = HomeHeroBanner.defaultRotation,
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

  /// The previous side scale made the centered slide read ~30% bigger than its
  /// neighbours. Because the neighbours shrink around their own centers, that
  /// also added about 33.5pt of visual whitespace on top of [heroSlideGap].
  static const double _originalSideScale = 1 / 1.3;

  /// Halve the visible edge-to-edge gap between the centered slide and its
  /// neighbours while keeping the configured layout gap and center size intact.
  ///
  /// visible gap = heroSlideGap + heroSlideWidth * (1 - sideScale) / 2
  static const double _targetVisibleGapScale = 0.5;
  static const double _originalVisibleGap =
      HomeScreenVisuals.heroSlideGap +
      HomeScreenVisuals.heroSlideWidth * (1 - _originalSideScale) / 2;
  static const double _targetVisibleGap =
      _originalVisibleGap * _targetVisibleGapScale;
  static const double _sideScale =
      1 -
      ((_targetVisibleGap - HomeScreenVisuals.heroSlideGap) *
          2 /
          HomeScreenVisuals.heroSlideWidth);

  /// Long enough to read as a slide rather than a cut, short enough that the
  /// dwell time the dashboard sets is what the customer actually perceives.
  static const Duration _autoAdvanceDuration = Duration(milliseconds: 520);

  static const Duration _slideDuration = Duration(milliseconds: 280);
  static const Duration _dotDuration = Duration(milliseconds: 180);

  /// Where an endlessly-paging carousel starts. Far enough from zero that a
  /// customer swiping backwards will never reach the start of the list.
  static const int _loopOrigin = 10000;

  PageController? controller;
  double? controllerViewportFraction;
  int? controllerSlideCount;
  Timer? rotationTimer;

  /// Identifies this carousel to [VisibilityDetector]. Unique per State so two
  /// carousels could never report against the same key, and stable across
  /// rebuilds so the detector keeps tracking the same widget.
  final Key visibilityKey = UniqueKey();

  /// Whether any part of the carousel is on screen. Starts true so the first
  /// interval is already running by the time the detector's first callback
  /// confirms it.
  bool isVisible = true;

  /// The page the controller is parked on. With looping this counts past
  /// [slideCount] and is taken modulo it to pick a slide.
  int page = 0;

  /// Auto-advancing content is exactly what "reduce motion" asks us to stop, so
  /// the carousel holds still and waits to be swiped instead.
  bool motionIsReduced = false;

  bool get usesFallback => widget.banners.isEmpty;

  int get slideCount =>
      usesFallback ? _fallbackSlides.length : widget.banners.length;

  /// One slide is not a carousel: nothing to page to, nothing to rotate.
  bool get loops => slideCount > 1;

  int get initialPage => loops ? (_loopOrigin ~/ slideCount) * slideCount : 0;

  int get activeSlide => slideCount == 0 ? 0 : page % slideCount;

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();

    motionIsReduced = MediaQuery.disableAnimationsOf(context);

    // The peek is a fixed slide width centered in whatever viewport the phone
    // gives us, so the fraction is derived from the screen rather than pinned.
    final viewportWidth = MediaQuery.sizeOf(context).width;
    final pitch =
        HomeScreenVisuals.heroSlideWidth + HomeScreenVisuals.heroSlideGap;
    final fraction = viewportWidth <= 0
        ? 1.0
        : (pitch / viewportWidth).clamp(0.1, 1.0);

    rebuildController(fraction);
    scheduleRotation();
  }

  @override
  void didUpdateWidget(HomeHeroCarousel oldWidget) {
    super.didUpdateWidget(oldWidget);

    // A refresh can swap the CMS slides in over the fallback, or change how
    // many there are — which moves where the loop has to start.
    if (controllerSlideCount != slideCount) {
      rebuildController(controllerViewportFraction);
    }

    if (widget.rotationInterval != oldWidget.rotationInterval ||
        controllerSlideCount != slideCount) {
      scheduleRotation();
    }
  }

  @override
  void dispose() {
    rotationTimer?.cancel();
    controller?.dispose();
    super.dispose();
  }

  void rebuildController(double? fraction) {
    if (fraction == null) return;
    if (controllerViewportFraction == fraction &&
        controllerSlideCount == slideCount) {
      return;
    }

    controller?.dispose();
    controllerViewportFraction = fraction;
    controllerSlideCount = slideCount;
    page = initialPage;
    controller = PageController(
      initialPage: initialPage,
      viewportFraction: fraction,
    );
  }

  /// Restarts the dwell timer from zero. Called on load, after the carousel
  /// settles from an auto-advance, and after the customer lets go of a swipe —
  /// so however they got here, they get a full interval to look at it.
  void scheduleRotation() {
    rotationTimer?.cancel();
    if (!loops || motionIsReduced || !isVisible) return;

    rotationTimer = Timer(widget.rotationInterval, advance);
  }

  /// Any sliver of the carousel on screen counts as visible: the threshold is
  /// there to stop rotation when Home is behind something, not to stop it
  /// while the customer is scrolling past.
  void onVisibilityChanged(VisibilityInfo info) {
    // The detector's callbacks are asynchronous and can land after the widget
    // is gone — the package documents this.
    if (!mounted) return;

    final visible = info.visibleFraction > 0;
    if (visible == isVisible) return;

    isVisible = visible;

    // Coming back starts a fresh interval rather than resuming a stale one, so
    // a returning customer gets a full slide to look at.
    if (visible) {
      scheduleRotation();
    } else {
      stopRotation();
    }
  }

  void stopRotation() {
    rotationTimer?.cancel();
    rotationTimer = null;
  }

  void advance() {
    final pageController = controller;
    if (pageController == null || !pageController.hasClients) return;

    pageController
        .animateToPage(
          page + 1,
          duration: _autoAdvanceDuration,
          curve: Curves.easeInOut,
        )
        // The scroll notification below normally covers this; scheduling here
        // too means a settle that arrives without one cannot stall rotation.
        .then((_) {
          if (mounted) scheduleRotation();
        });
  }

  void goToSlide(int dotIndex) {
    // Page to the nearest copy of that slide rather than back to its first
    // one, so tapping a dot moves at most one step in either direction.
    final target = page - activeSlide + dotIndex;

    controller?.animateToPage(
      target,
      duration: _slideDuration,
      curve: Curves.ease,
    );
  }

  bool onScrollNotification(ScrollNotification notification) {
    // `dragDetails` is what separates a finger on the glass from the carousel
    // animating itself — only the former should take rotation over.
    if (notification is ScrollStartNotification &&
        notification.dragDetails != null) {
      stopRotation();
    } else if (notification is ScrollEndNotification) {
      scheduleRotation();
    }

    return false;
  }

  Widget buildSlide(int slideIndex) {
    if (usesFallback) return _fallbackSlides[slideIndex % slideCount];

    final banner = widget.banners[slideIndex % slideCount];

    return _BannerSlide(
      banner: banner,
      onTap: banner.link.isTappable
          ? () => widget.onOpenBanner(banner)
          : null,
    );
  }

  /// Full size at the center, [_sideScale] a page away, and continuously
  /// between the two — so the growing and shrinking tracks the finger rather
  /// than snapping when the page changes.
  double scaleFor(int slideIndex, PageController pageController) {
    final currentPage =
        pageController.hasClients && pageController.position.haveDimensions
        ? (pageController.page ?? page.toDouble())
        : page.toDouble();

    final distance = (currentPage - slideIndex).abs().clamp(0.0, 1.0);
    return _sideScale + (1.0 - _sideScale) * (1.0 - distance);
  }

  @override
  Widget build(BuildContext context) {
    final pageController = controller;
    if (pageController == null) return const SizedBox.shrink();

    return VisibilityDetector(
      key: visibilityKey,
      // Deliberately a fresh closure per build rather than a tear-off of
      // `onVisibilityChanged`. VisibilityDetector spots "an ancestor stopped
      // painting me" from its setter noticing a *different* callback; Dart
      // compares instance-method tear-offs from the same object as equal, so a
      // tear-off makes the setter early-return and the hide event never
      // arrives. Verified: with a tear-off the carousel keeps rotating behind
      // another tab. Do not "simplify" this back.
      onVisibilityChanged: (info) => onVisibilityChanged(info),
      child: Column(
        children: [
          SizedBox(
            height: HomeScreenVisuals.heroSlideHeight,
            child: NotificationListener<ScrollNotification>(
              onNotification: onScrollNotification,
              child: PageView.builder(
                controller: pageController,
                padEnds: true,
                // Null itemCount pages forever; the builder takes the index
                // modulo the slide count, so the carousel has no ends to hit.
                itemCount: loops ? null : 1,
                onPageChanged: (value) => setState(() => page = value),
                itemBuilder: (context, slideIndex) {
                  return Padding(
                    padding: const EdgeInsets.symmetric(
                      horizontal: HomeScreenVisuals.heroSlideGap / 2,
                    ),
                    child: AnimatedBuilder(
                      animation: pageController,
                      builder: (context, child) {
                        return Transform.scale(
                          scale: scaleFor(slideIndex, pageController),
                          child: child,
                        );
                      },
                      child: buildSlide(slideIndex),
                    ),
                  );
                },
              ),
            ),
          ),
          // 34pt tall so the 6pt dots sit exactly 14 below the track and 20
          // above the next module, while each dot still gets a touch target
          // wider and taller than the pip it draws. A single slide gets no dots
          // — there is nowhere to page to.
          if (loops)
            SizedBox(
              height: 34,
              child: Row(
                mainAxisAlignment: MainAxisAlignment.center,
                children: List.generate(slideCount, (dotIndex) {
                  final active = dotIndex == activeSlide;

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
                            color: active
                                ? EbtlColors.coral
                                : EbtlColors.border,
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
      ),
    );
  }
}

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
