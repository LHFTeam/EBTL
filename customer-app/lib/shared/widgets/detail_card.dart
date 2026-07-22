import 'package:flutter/material.dart';

import '../../core/theme/ebtl_colors.dart';

class DetailCard extends StatelessWidget {
  final Widget child;
  final Color? backgroundColor;

  const DetailCard({super.key, required this.child, this.backgroundColor});

  @override
  Widget build(BuildContext context) {
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: backgroundColor ?? EbtlColors.white.withValues(alpha: 0.9),
        borderRadius: BorderRadius.circular(20),
        border: Border.all(color: EbtlColors.border),
        boxShadow: [
          BoxShadow(
            color: Colors.black.withValues(alpha: 0.035),
            blurRadius: 18,
            offset: const Offset(0, 8),
          ),
        ],
      ),
      child: child,
    );
  }
}
