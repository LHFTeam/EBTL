import 'package:flutter/material.dart';

import '../../../core/theme/ebtl_colors.dart';

class ShopSkeletonBox extends StatelessWidget {
  final double width;
  final double height;
  final double radius;

  const ShopSkeletonBox({
    super.key,
    required this.width,
    required this.height,
    required this.radius,
  });

  @override
  Widget build(BuildContext context) {
    return Container(
      width: width,
      height: height,
      decoration: BoxDecoration(
        color: EbtlColors.sand.withValues(alpha: 0.55),
        borderRadius: BorderRadius.circular(radius),
        border: Border.all(color: EbtlColors.border.withValues(alpha: 0.65)),
      ),
    );
  }
}
