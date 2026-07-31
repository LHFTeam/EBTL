import 'package:cached_network_image/cached_network_image.dart';
import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';

import '../../core/theme/ebtl_colors.dart';
import '../../core/theme/home_screen_visuals.dart';
import '../../models/common_models.dart';
import '../../models/product_models.dart';
import 'bottle_placeholder.dart';

class BottleImage extends StatelessWidget {
  final String name;
  final String? imageUrl;
  final double? size;

  BottleImage({super.key, required LiquorType liquor, this.size})
    : name = liquor.name,
      imageUrl = liquor.imageUrl;

  const BottleImage.raw({
    super.key,
    required this.name,
    this.imageUrl,
    this.size,
  });

  @override
  Widget build(BuildContext context) {
    // Bottle art is drawn small (an 80pt card, or a 20pt compatibility chip);
    // decoding the source at full resolution would waste most of the image
    // cache on pixels that are never shown.
    final decodeWidth = ((size ?? 96) * 3).round();

    final image = imageUrl == null
        ? BottlePlaceholder(name: name)
        : CachedNetworkImage(
            imageUrl: imageUrl!,
            fit: BoxFit.contain,
            width: double.infinity,
            height: double.infinity,
            memCacheWidth: decodeWidth,
            maxWidthDiskCache: decodeWidth,
            fadeInDuration: Duration.zero,
            placeholder: (_, _) => BottlePlaceholder(name: name),
            errorWidget: (_, _, _) => BottlePlaceholder(name: name),
          );

    final clippedImage = ClipRRect(
      borderRadius: BorderRadius.circular(size == null ? 14 : 999),
      child: image,
    );

    if (size != null) {
      return SizedBox(width: size, height: size, child: clippedImage);
    }

    return SizedBox.expand(child: clippedImage);
  }
}

class BottleCard extends StatelessWidget {
  final LiquorType liquor;
  final VoidCallback? onTap;

  const BottleCard({super.key, required this.liquor, this.onTap});

  @override
  Widget build(BuildContext context) {
    final showName = HomeScreenVisuals.showHomeLiquorBottleCardName;

    final card = Container(
      width: 80,
      decoration: BoxDecoration(
        color: EbtlColors.white.withValues(alpha: 0.88),
        borderRadius: BorderRadius.circular(18),
        border: Border.all(color: EbtlColors.border),
        boxShadow: [
          BoxShadow(
            color: Colors.black.withValues(alpha: 0.035),
            blurRadius: 18,
            offset: const Offset(0, 8),
          ),
        ],
      ),
      child: Column(
        children: [
          Expanded(
            child: Padding(
              padding: showName
                  ? const EdgeInsets.fromLTRB(4, 4, 4, 2)
                  : const EdgeInsets.fromLTRB(4, 4, 4, 4),
              child: BottleImage(liquor: liquor),
            ),
          ),
          if (showName)
            Padding(
              padding: const EdgeInsets.fromLTRB(6, 2, 6, 9),
              child: Text(
                liquor.name,
                textAlign: TextAlign.center,
                maxLines: 2,
                overflow: TextOverflow.ellipsis,
                style: GoogleFonts.manrope(
                  color: EbtlColors.navy,
                  fontSize: 12,
                  fontWeight: FontWeight.w900,
                  height: 1.05,
                ),
              ),
            ),
        ],
      ),
    );

    if (onTap == null) return card;

    return GestureDetector(
      behavior: HitTestBehavior.opaque,
      onTap: onTap,
      child: card,
    );
  }
}

class SelectableBottleCard extends StatelessWidget {
  final LiquorType liquor;
  final bool selected;
  final VoidCallback onTap;

  const SelectableBottleCard({
    super.key,
    required this.liquor,
    required this.selected,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      behavior: HitTestBehavior.opaque,
      onTap: onTap,
      child: Stack(
        clipBehavior: Clip.none,
        children: [
          BottleCard(liquor: liquor),
          if (selected)
            Positioned(
              top: 10,
              right: 10,
              child: Container(
                width: 26,
                height: 26,
                decoration: const BoxDecoration(
                  color: EbtlColors.coral,
                  shape: BoxShape.circle,
                ),
                child: const Icon(Icons.check, color: Colors.white, size: 17),
              ),
            ),
        ],
      ),
    );
  }
}

class CompatibleLiquorChips extends StatelessWidget {
  final List<LiquorCompatibility> compatibility;

  const CompatibleLiquorChips({super.key, required this.compatibility});

  @override
  Widget build(BuildContext context) {
    if (compatibility.isEmpty) {
      return Text(
        'Works with: Any bottle',
        maxLines: 1,
        overflow: TextOverflow.ellipsis,
        style: GoogleFonts.manrope(
          fontSize: 11,
          color: EbtlColors.navy,
          fontWeight: FontWeight.w900,
        ),
      );
    }

    final first = compatibility.first;
    final extraCount = compatibility.length - 1;

    return Row(
      children: [
        Flexible(
          child: Container(
            height: 28,
            padding: const EdgeInsets.fromLTRB(4, 3, 8, 3),
            decoration: BoxDecoration(
              color: EbtlColors.cream,
              borderRadius: BorderRadius.circular(999),
              border: Border.all(color: EbtlColors.border),
            ),
            child: Row(
              mainAxisSize: MainAxisSize.min,
              children: [
                BottleImage.raw(
                  name: first.liquorTypeName,
                  imageUrl: first.liquorTypeImageUrl,
                  size: 20,
                ),
                const SizedBox(width: 6),
                Flexible(
                  child: Text(
                    first.liquorTypeName,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: GoogleFonts.manrope(
                      fontSize: 10,
                      color: EbtlColors.navy,
                      fontWeight: FontWeight.w900,
                    ),
                  ),
                ),
              ],
            ),
          ),
        ),
        if (extraCount > 0) ...[
          const SizedBox(width: 5),
          Container(
            height: 28,
            padding: const EdgeInsets.symmetric(horizontal: 8),
            alignment: Alignment.center,
            decoration: BoxDecoration(
              color: EbtlColors.seafoam.withValues(alpha: 0.65),
              borderRadius: BorderRadius.circular(999),
              border: Border.all(color: EbtlColors.border),
            ),
            child: Text(
              '+$extraCount',
              style: GoogleFonts.manrope(
                fontSize: 10,
                color: EbtlColors.navy,
                fontWeight: FontWeight.w900,
              ),
            ),
          ),
        ],
      ],
    );
  }
}
