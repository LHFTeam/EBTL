import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';

import '../../core/theme/ebtl_colors.dart';
import '../../core/theme/home_screen_visuals.dart';
import '../../core/utils/color_utils.dart';
import '../../models/cocktail_models.dart';
import '../../models/common_models.dart';
import 'bottle_widgets.dart';
import 'multiply_blend.dart';
import 'network_or_asset_image.dart';
import 'product_tag_widgets.dart';

class CocktailSmallCard extends StatelessWidget {
  final Cocktail cocktail;
  final VoidCallback? onTap;

  const CocktailSmallCard({super.key, required this.cocktail, this.onTap});

  @override
  Widget build(BuildContext context) {
    return SizedBox(
      width: HomeScreenVisuals.featuredProductCardWidth,
      child: CocktailCardShell(
        cocktail: cocktail,
        showUsing: false,
        onTap: onTap,
        showPrice: HomeScreenVisuals.showFeaturedProductCardPrice,
        imageHeight: HomeScreenVisuals.featuredProductCardImageHeight,
        textPadding: HomeScreenVisuals.featuredProductCardTextPadding,
        nameFontSize: HomeScreenVisuals.featuredProductCardNameFontSize,
        nameLineHeight: HomeScreenVisuals.featuredProductCardNameLineHeight,
        shortDescriptionFontSize:
            HomeScreenVisuals.featuredProductCardShortDescriptionFontSize,
        shortDescriptionLineHeight:
            HomeScreenVisuals.featuredProductCardShortDescriptionLineHeight,
      ),
    );
  }
}

/// The Home "Featured Kits" card: a 176pt rail card with a tinted image well,
/// the kit name, its ingredients and prep time, the price and a favorite
/// toggle. Replaced the 2-up featured grid.
///
/// [tint] is assigned by the rail from the card's position (seafoam → blush →
/// sand) rather than by the cocktail, so a longer list keeps alternating.
class CocktailRailCard extends StatelessWidget {
  final Cocktail cocktail;
  final Color tint;
  final bool isFavorite;
  final VoidCallback? onTap;
  final VoidCallback? onToggleFavorite;

  const CocktailRailCard({
    super.key,
    required this.cocktail,
    required this.tint,
    required this.isFavorite,
    this.onTap,
    this.onToggleFavorite,
  });

  /// The rail's tint cycle, in order.
  static const List<Color> tints = [
    EbtlColors.seafoam,
    EbtlColors.blush,
    EbtlColors.sand,
  ];

  static Color tintForIndex(int index) => tints[index % tints.length];

  /// "Cranberry, grapefruit, ice · 4 min" — the short description with the
  /// prep time appended, or just the prep time when there is no description.
  String get _subtitle {
    final description = cocktail.cardSubtitle;
    final time = '${cocktail.prepTimeMinutes} min';
    return description.isEmpty ? time : '$description · $time';
  }

  @override
  Widget build(BuildContext context) {
    final tag = cocktail.sortedTagDetails.isEmpty
        ? null
        : cocktail.sortedTagDetails.first;
    final orderable = cocktail.availability.isOrderable;

    return SizedBox(
      width: HomeScreenVisuals.featuredRailCardWidth,
      child: Material(
        color: EbtlColors.white,
        borderRadius: BorderRadius.circular(18),
        child: InkWell(
          onTap: onTap,
          borderRadius: BorderRadius.circular(18),
          child: Ink(
            decoration: BoxDecoration(
              color: EbtlColors.white,
              borderRadius: BorderRadius.circular(18),
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
              borderRadius: BorderRadius.circular(18),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                mainAxisSize: MainAxisSize.min,
                children: [
                  SizedBox(
                    height: HomeScreenVisuals.featuredRailCardImageHeight,
                    width: double.infinity,
                    child: Stack(
                      children: [
                        Positioned.fill(
                          child: ColoredBox(
                            color: tint,
                            // Kit photography is shot on white, so it is
                            // multiplied into the tint rather than pasted over
                            // it.
                            child: MultiplyBlend(
                              child: Padding(
                                padding: const EdgeInsets.all(11),
                                child: NetworkOrAssetImage(
                                  imageUrl: cocktail.imageUrl,
                                  asset: cocktail.imageAsset,
                                  fit: BoxFit.contain,
                                ),
                              ),
                            ),
                          ),
                        ),
                        if (tag != null)
                          Positioned(
                            top: 8,
                            left: 8,
                            child: _RailTagBadge(tag: tag),
                          ),
                        if (!orderable)
                          Positioned(
                            bottom: 8,
                            right: 8,
                            child: Container(
                              padding: const EdgeInsets.symmetric(
                                horizontal: 9,
                                vertical: 5,
                              ),
                              decoration: BoxDecoration(
                                color: EbtlColors.sand,
                                borderRadius: BorderRadius.circular(999),
                              ),
                              child: Row(
                                mainAxisSize: MainAxisSize.min,
                                children: [
                                  const Icon(
                                    Icons.info_outline,
                                    size: 13,
                                    color: EbtlColors.coral,
                                  ),
                                  const SizedBox(width: 4),
                                  Text(
                                    'Unavailable',
                                    style: GoogleFonts.manrope(
                                      fontSize: 10,
                                      color: EbtlColors.navy,
                                      fontWeight: FontWeight.w900,
                                    ),
                                  ),
                                ],
                              ),
                            ),
                          ),
                      ],
                    ),
                  ),
                  Padding(
                    padding: const EdgeInsets.fromLTRB(12, 11, 12, 12),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          cocktail.name,
                          maxLines: 2,
                          overflow: TextOverflow.ellipsis,
                          style: GoogleFonts.playfairDisplay(
                            fontSize: 17,
                            height: 1.15,
                            fontWeight: FontWeight.w700,
                            color: EbtlColors.navy,
                          ),
                        ),
                        const SizedBox(height: 4),
                        Text(
                          _subtitle,
                          maxLines: 2,
                          overflow: TextOverflow.ellipsis,
                          style: GoogleFonts.manrope(
                            fontSize: 11.5,
                            height: 1.35,
                            fontWeight: FontWeight.w500,
                            color: EbtlColors.muted,
                          ),
                        ),
                        const SizedBox(height: 9),
                        Row(
                          children: [
                            Expanded(
                              child: Text(
                                cocktail.priceLabel,
                                maxLines: 1,
                                overflow: TextOverflow.ellipsis,
                                style: GoogleFonts.manrope(
                                  fontSize: 15,
                                  fontWeight: FontWeight.w900,
                                  color: EbtlColors.coral,
                                ),
                              ),
                            ),
                            const SizedBox(width: 6),
                            Material(
                              color: EbtlColors.cream,
                              shape: const CircleBorder(
                                side: BorderSide(color: EbtlColors.border),
                              ),
                              child: InkWell(
                                onTap: onToggleFavorite,
                                customBorder: const CircleBorder(),
                                child: SizedBox(
                                  width: 32,
                                  height: 32,
                                  child: Icon(
                                    isFavorite
                                        ? Icons.favorite
                                        : Icons.favorite_border,
                                    size: 16,
                                    color: EbtlColors.coral,
                                  ),
                                ),
                              ),
                            ),
                          ],
                        ),
                      ],
                    ),
                  ),
                ],
              ),
            ),
          ),
        ),
      ),
    );
  }
}

/// The pill on a featured rail card. Unlike [ProductTagBadge] it keeps the
/// design's flat fill and picks a readable foreground for pale tag colors
/// (the gold "POPULAR" tag reads navy, the teal and coral ones read white).
class _RailTagBadge extends StatelessWidget {
  final ProductTag tag;

  const _RailTagBadge({required this.tag});

  @override
  Widget build(BuildContext context) {
    final color = colorFromHex(tag.colorHex);
    final foreground =
        ThemeData.estimateBrightnessForColor(color) == Brightness.dark
        ? EbtlColors.white
        : EbtlColors.navy;

    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 9, vertical: 4),
      decoration: BoxDecoration(
        color: color,
        borderRadius: BorderRadius.circular(999),
      ),
      child: Text(
        tag.name.toUpperCase(),
        maxLines: 1,
        overflow: TextOverflow.ellipsis,
        style: GoogleFonts.manrope(
          fontSize: 10.5,
          height: 1.2,
          fontWeight: FontWeight.w900,
          letterSpacing: 0.6,
          color: foreground,
        ),
      ),
    );
  }
}

class CocktailGridCard extends StatelessWidget {
  final Cocktail cocktail;
  final VoidCallback? onTap;

  const CocktailGridCard({super.key, required this.cocktail, this.onTap});

  @override
  Widget build(BuildContext context) {
    return CocktailCardShell(cocktail: cocktail, showUsing: true, onTap: onTap);
  }
}

class CocktailCardShell extends StatelessWidget {
  final Cocktail cocktail;
  final bool showUsing;
  final VoidCallback? onTap;

  final bool showPrice;
  final double? imageHeight;
  final EdgeInsetsGeometry textPadding;
  final double nameFontSize;
  final double nameLineHeight;
  final double shortDescriptionFontSize;
  final double shortDescriptionLineHeight;

  const CocktailCardShell({
    super.key,
    required this.cocktail,
    required this.showUsing,
    this.onTap,
    this.showPrice = true,
    this.imageHeight,
    this.textPadding = const EdgeInsets.fromLTRB(12, 10, 10, 9),
    this.nameFontSize = 13,
    this.nameLineHeight = 1.15,
    this.shortDescriptionFontSize = 10,
    this.shortDescriptionLineHeight = 1.35,
  });

  @override
  Widget build(BuildContext context) {
    final productTags = cocktail.sortedTagDetails;
    final subtitle = cocktail.cardSubtitle;
    final orderable = cocktail.availability.isOrderable;

    final imageSection = Stack(
      children: [
        Positioned.fill(
          child: NetworkOrAssetImage(
            imageUrl: cocktail.imageUrl,
            asset: cocktail.imageAsset,
          ),
        ),
        if (productTags.isNotEmpty)
          Positioned(
            top: 8,
            left: 8,
            right: 8,
            child: Wrap(
              spacing: 5,
              runSpacing: 5,
              children: productTags
                  .take(showUsing ? 2 : 1)
                  .map((tag) => ProductTagBadge(tag: tag))
                  .toList(),
            ),
          ),
        if (!orderable)
          Positioned(
            bottom: 8,
            right: 8,
            child: Container(
              padding: const EdgeInsets.symmetric(horizontal: 9, vertical: 5),
              decoration: BoxDecoration(
                color: EbtlColors.sand,
                borderRadius: BorderRadius.circular(999),
              ),
              child: Row(
                mainAxisSize: MainAxisSize.min,
                children: [
                  const Icon(
                    Icons.info_outline,
                    size: 13,
                    color: EbtlColors.coral,
                  ),
                  const SizedBox(width: 4),
                  Text(
                    'Unavailable',
                    style: GoogleFonts.manrope(
                      fontSize: 10,
                      color: EbtlColors.navy,
                      fontWeight: FontWeight.w900,
                    ),
                  ),
                ],
              ),
            ),
          ),
      ],
    );

    return Material(
      color: Colors.transparent,
      child: InkWell(
        onTap: onTap,
        borderRadius: BorderRadius.circular(16),
        child: Ink(
          decoration: BoxDecoration(
            color: EbtlColors.white,
            borderRadius: BorderRadius.circular(16),
            border: Border.all(color: EbtlColors.border),
            boxShadow: [
              BoxShadow(
                color: Colors.black.withValues(alpha: 0.04),
                blurRadius: 16,
                offset: const Offset(0, 8),
              ),
            ],
          ),
          child: ClipRRect(
            borderRadius: BorderRadius.circular(16),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                if (imageHeight == null)
                  Expanded(flex: 6, child: imageSection)
                else
                  SizedBox(
                    height: imageHeight,
                    width: double.infinity,
                    child: imageSection,
                  ),
                Expanded(
                  flex: 7,
                  child: Padding(
                    padding: textPadding,
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          cocktail.name,
                          maxLines: 2,
                          overflow: TextOverflow.ellipsis,
                          style: GoogleFonts.manrope(
                            color: EbtlColors.navy,
                            fontSize: nameFontSize,
                            height: nameLineHeight,
                            fontWeight: FontWeight.w900,
                          ),
                        ),
                        if (showPrice) ...[
                          const SizedBox(height: 5),
                          Text(
                            cocktail.priceLabel,
                            maxLines: 1,
                            overflow: TextOverflow.ellipsis,
                            style: GoogleFonts.manrope(
                              fontSize: 12,
                              color: EbtlColors.coral,
                              fontWeight: FontWeight.w900,
                            ),
                          ),
                        ],
                        const SizedBox(height: 5),
                        if (subtitle.isNotEmpty)
                          Expanded(
                            child: Text(
                              subtitle,
                              maxLines: showUsing ? 3 : 2,
                              overflow: TextOverflow.ellipsis,
                              style: GoogleFonts.manrope(
                                fontSize: shortDescriptionFontSize,
                                color: EbtlColors.ink,
                                fontWeight: FontWeight.w500,
                                height: shortDescriptionLineHeight,
                              ),
                            ),
                          )
                        else
                          const Spacer(),
                        Row(
                          children: [
                            if (showUsing)
                              Expanded(
                                child: CompatibleLiquorChips(
                                  compatibility: cocktail.compatibility,
                                ),
                              )
                            else
                              const Spacer(),
                            const SizedBox(width: 8),
                            Icon(
                              cocktail.isFavorite
                                  ? Icons.favorite
                                  : Icons.favorite_border,
                              size: 20,
                              color: cocktail.isFavorite
                                  ? EbtlColors.coral
                                  : EbtlColors.navy,
                            ),
                          ],
                        ),
                      ],
                    ),
                  ),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}
