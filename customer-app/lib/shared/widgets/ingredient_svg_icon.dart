import 'package:flutter/material.dart';
import 'package:flutter_svg/flutter_svg.dart';

import '../../core/theme/ebtl_colors.dart';

class IngredientIconResolver {
  static const String _basePath = 'assets/icons/ingredients';
  static const String fallback = '$_basePath/generic.svg';

  static String pathFor(String? iconKey) {
    final key = iconKey?.trim().toLowerCase();

    if (key == null || key.isEmpty) {
      return fallback;
    }

    final validKey = RegExp(r'^[a-z0-9]+([_-][a-z0-9]+)*$').hasMatch(key);
    if (!validKey) {
      return fallback;
    }

    return '$_basePath/$key.svg';
  }
}

class IngredientSvgIcon extends StatelessWidget {
  final String? iconKey;
  final double size;

  const IngredientSvgIcon({super.key, required this.iconKey, this.size = 20});

  @override
  Widget build(BuildContext context) {
    final iconPath = IngredientIconResolver.pathFor(iconKey);

    Widget fallbackIcon() {
      return Icon(Icons.spa_outlined, size: size, color: EbtlColors.navy);
    }

    Widget fallbackSvgOrIcon() {
      return SvgPicture.asset(
        IngredientIconResolver.fallback,
        width: size,
        height: size,
        fit: BoxFit.contain,
        placeholderBuilder: (_) => fallbackIcon(),
        errorBuilder: (_, _, _) => fallbackIcon(),
      );
    }

    return SvgPicture.asset(
      iconPath,
      width: size,
      height: size,
      fit: BoxFit.contain,
      placeholderBuilder: (_) => fallbackIcon(),
      errorBuilder: (_, _, _) {
        if (iconPath == IngredientIconResolver.fallback) {
          return fallbackIcon();
        }

        return fallbackSvgOrIcon();
      },
    );
  }
}
