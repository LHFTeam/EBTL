import 'package:cached_network_image/cached_network_image.dart';
import 'package:flutter/material.dart';

import '../../core/theme/ebtl_colors.dart';

/// Widest this image is ever drawn at (full-bleed hero on a large phone),
/// doubled for device pixel ratio.
const int _memCacheWidth = 1080;

/// Cap on what is written to disk, so the cache does not fill up with
/// originals that are far larger than anything the app displays.
const int _maxWidthDiskCache = 1440;

class NetworkOrAssetImage extends StatelessWidget {
  final String? imageUrl;
  final String asset;
  final BoxFit fit;
  final Widget? fallback;

  const NetworkOrAssetImage({
    super.key,
    this.imageUrl,
    required this.asset,
    this.fit = BoxFit.cover,
    this.fallback,
  });

  @override
  Widget build(BuildContext context) {
    if (imageUrl != null && imageUrl!.trim().isNotEmpty) {
      return CachedNetworkImage(
        imageUrl: imageUrl!.trim(),
        fit: fit,
        // Decode near display size rather than at source resolution — full-size
        // decodes are what blow the in-memory budget and force re-downloads.
        memCacheWidth: _memCacheWidth,
        maxWidthDiskCache: _maxWidthDiskCache,
        // Cached images resolve synchronously, so a fade would flash on every
        // rebuild of an already-loaded image.
        fadeInDuration: Duration.zero,
        placeholder: (_, _) => fallbackGradient(),
        errorWidget: (_, _, _) => fallback ?? fallbackGradient(),
      );
    }

    return Image.asset(
      asset,
      fit: fit,
      errorBuilder: (_, _, _) => fallback ?? fallbackGradient(),
    );
  }

  Widget fallbackGradient() {
    return Container(
      decoration: const BoxDecoration(
        gradient: LinearGradient(
          colors: [EbtlColors.sand, EbtlColors.blush],
          begin: Alignment.topLeft,
          end: Alignment.bottomRight,
        ),
      ),
      child: const Center(
        child: Icon(Icons.local_bar_outlined, color: EbtlColors.navy, size: 36),
      ),
    );
  }
}

class AssetOrGradientImage extends StatelessWidget {
  final String asset;
  final BorderRadius borderRadius;
  final Color gradientStart;
  final Color gradientEnd;

  const AssetOrGradientImage({
    super.key,
    required this.asset,
    required this.borderRadius,
    required this.gradientStart,
    required this.gradientEnd,
  });

  @override
  Widget build(BuildContext context) {
    return ClipRRect(
      borderRadius: borderRadius,
      child: Image.asset(
        asset,
        fit: BoxFit.cover,
        errorBuilder: (_, _, _) {
          return Container(
            decoration: BoxDecoration(
              gradient: LinearGradient(
                colors: [gradientStart, gradientEnd],
                begin: Alignment.topLeft,
                end: Alignment.bottomRight,
              ),
            ),
          );
        },
      ),
    );
  }
}
