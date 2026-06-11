import 'package:flutter/material.dart';

import '../../core/theme/ebtl_colors.dart';

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
      return Image.network(
        imageUrl!,
        fit: fit,
        errorBuilder: (_, _, _) => fallback ?? fallbackGradient(),
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
