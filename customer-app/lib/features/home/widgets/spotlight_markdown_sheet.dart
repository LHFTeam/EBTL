import 'package:flutter/material.dart';
import 'package:flutter_markdown/flutter_markdown.dart';
import 'package:google_fonts/google_fonts.dart';

import '../../../core/theme/ebtl_colors.dart';
import '../../../core/theme/home_screen_visuals.dart';
import '../../../models/spotlight_models.dart';
import '../../../services/analytics_service.dart';
import '../../../shared/widgets/network_or_asset_image.dart';
import '../../../shared/widgets/sheet_close_button.dart';

/// Matches [_sheetHeightFraction] in spotlight_sheet.dart: the two sheets are
/// the same shape, so the scrim strip above them reads the same way.
const double _sheetHeightFraction = 0.95;

/// Opens the sheet behind a markdown-slide Spotlight banner: the banner's own
/// artwork across the top, then the markdown marketing wrote for it. Unlike
/// [SpotlightSheet], there is no separate title/subtitle block — the
/// markdown's own first heading takes that place, so the copy is one
/// continuous piece rather than a caption bolted onto a heading.
Future<void> showSpotlightMarkdownSheet({
  required BuildContext context,
  required SpotlightBanner banner,
}) {
  return showModalBottomSheet<void>(
    context: context,
    isScrollControlled: true,
    backgroundColor: Colors.transparent,
    // Same as the product-grid sheet: the artwork runs under the status bar,
    // so the sheet cannot be inset by the top safe area.
    useSafeArea: false,
    builder: (_) => SpotlightMarkdownSheet(banner: banner),
  );
}

class SpotlightMarkdownSheet extends StatefulWidget {
  final SpotlightBanner banner;

  const SpotlightMarkdownSheet({super.key, required this.banner});

  @override
  State<SpotlightMarkdownSheet> createState() =>
      _SpotlightMarkdownSheetState();
}

class _SpotlightMarkdownSheetState extends State<SpotlightMarkdownSheet> {
  @override
  void initState() {
    super.initState();
    AnalyticsService.logScreenView('spotlight_banner_slide');
  }

  @override
  Widget build(BuildContext context) {
    final banner = widget.banner;
    // The banner is untrusted like every other payload, so a slide with
    // nothing written falls back to the title alone rather than an empty
    // scroll view under the artwork.
    final markdown = banner.markdownBody?.trim() ?? '';

    return SizedBox(
      height: MediaQuery.sizeOf(context).height * _sheetHeightFraction,
      child: ClipRRect(
        borderRadius: const BorderRadius.vertical(top: Radius.circular(24)),
        child: ColoredBox(
          color: EbtlColors.cream,
          child: CustomScrollView(
            slivers: [
              SliverToBoxAdapter(
                child: Stack(
                  children: [
                    AspectRatio(
                      aspectRatio:
                          HomeScreenVisuals.spotlightBannerAspectRatio,
                      child: NetworkOrAssetImage(
                        imageUrl: banner.imageUrl,
                        asset: 'assets/banners/explore_hero.webp',
                      ),
                    ),
                    Positioned(
                      top: MediaQuery.paddingOf(context).top + 8,
                      right: 12,
                      child: const SheetCloseButton(),
                    ),
                  ],
                ),
              ),
              SliverToBoxAdapter(
                child: Padding(
                  padding: const EdgeInsets.fromLTRB(22, 20, 22, 0),
                  child: markdown.isEmpty
                      ? Text(banner.title, style: _headingStyle(1))
                      : MarkdownBody(
                          data: markdown,
                          styleSheet: MarkdownStyleSheet(
                            // h1 matches SpotlightSheet's title exactly, so a
                            // slide reads the same as the sheet it stands in
                            // for; h2-h4 step down through the app's existing
                            // heading sizes rather than inventing a new scale.
                            h1: _headingStyle(1),
                            h2: _headingStyle(2),
                            h3: _headingStyle(3),
                            h4: _headingStyle(4),
                            h1Padding: const EdgeInsets.only(bottom: 6),
                            h2Padding: const EdgeInsets.only(
                              top: 14,
                              bottom: 4,
                            ),
                            h3Padding: const EdgeInsets.only(
                              top: 12,
                              bottom: 4,
                            ),
                            h4Padding: const EdgeInsets.only(
                              top: 10,
                              bottom: 4,
                            ),
                            p: GoogleFonts.manrope(
                              fontSize: 15,
                              height: 1.42,
                              fontWeight: FontWeight.w600,
                              color: EbtlColors.ink,
                            ),
                            pPadding: const EdgeInsets.only(bottom: 4),
                            strong: GoogleFonts.manrope(
                              fontWeight: FontWeight.w900,
                              color: EbtlColors.navy,
                            ),
                            listBullet: GoogleFonts.manrope(
                              fontSize: 15,
                              color: EbtlColors.coral,
                              fontWeight: FontWeight.w900,
                            ),
                          ),
                        ),
                ),
              ),
              SliverToBoxAdapter(
                child: SizedBox(
                  height: MediaQuery.paddingOf(context).bottom + 28,
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

/// The app's heading scale for markdown slides: Playfair Display for the top
/// two levels (display type, matching the product-grid sheet's title at h1),
/// Manrope for the two below (matching sectionTitleStyle/
/// detailSectionTitleStyle in ebtl_text_styles.dart), all in the same navy the
/// rest of the app's headings use.
TextStyle _headingStyle(int level) {
  switch (level) {
    case 1:
      return GoogleFonts.playfairDisplay(
        fontSize: 24,
        height: 1.18,
        fontWeight: FontWeight.w800,
        color: EbtlColors.navy,
      );
    case 2:
      return GoogleFonts.playfairDisplay(
        fontSize: 20,
        height: 1.2,
        fontWeight: FontWeight.w700,
        color: EbtlColors.navy,
      );
    case 3:
      return GoogleFonts.manrope(
        fontSize: 18,
        height: 1.25,
        fontWeight: FontWeight.w900,
        color: EbtlColors.navy,
      );
    default:
      return GoogleFonts.manrope(
        fontSize: 16,
        height: 1.3,
        fontWeight: FontWeight.w900,
        color: EbtlColors.navy,
      );
  }
}
