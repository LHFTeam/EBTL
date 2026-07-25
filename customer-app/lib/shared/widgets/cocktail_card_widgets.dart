import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';

import '../../core/theme/ebtl_colors.dart';
import '../../core/theme/home_screen_visuals.dart';
import '../../models/cocktail_models.dart';
import 'bottle_widgets.dart';
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
