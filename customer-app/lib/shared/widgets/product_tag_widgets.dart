import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';

import '../../core/theme/ebtl_colors.dart';
import '../../core/utils/color_utils.dart';
import '../../models/common_models.dart';

class ProductTagBadge extends StatelessWidget {
  final ProductTag tag;

  const ProductTagBadge({super.key, required this.tag});

  @override
  Widget build(BuildContext context) {
    final color = colorFromHex(tag.colorHex);

    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 9, vertical: 5),
      decoration: BoxDecoration(
        color: color,
        borderRadius: BorderRadius.circular(999),
        boxShadow: [
          BoxShadow(
            color: color.withValues(alpha: 0.24),
            blurRadius: 8,
            offset: const Offset(0, 3),
          ),
        ],
      ),
      child: Text(
        tag.name,
        maxLines: 1,
        overflow: TextOverflow.ellipsis,
        style: GoogleFonts.manrope(
          fontSize: 10,
          color: Colors.white,
          fontWeight: FontWeight.w900,
        ),
      ),
    );
  }
}

class ProductTagFilterChip extends StatelessWidget {
  final ProductTag tag;
  final bool selected;
  final VoidCallback onTap;

  const ProductTagFilterChip({
    super.key,
    required this.tag,
    required this.selected,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    final color = colorFromHex(tag.colorHex);

    return GestureDetector(
      onTap: onTap,
      child: AnimatedContainer(
        duration: const Duration(milliseconds: 160),
        padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
        decoration: BoxDecoration(
          color: selected ? color : color.withValues(alpha: 0.12),
          borderRadius: BorderRadius.circular(999),
          border: Border.all(
            color: selected ? color : color.withValues(alpha: 0.42),
          ),
        ),
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            if (selected) ...[
              const Icon(Icons.check, color: Colors.white, size: 15),
              const SizedBox(width: 5),
            ] else ...[
              Container(
                width: 8,
                height: 8,
                decoration: BoxDecoration(color: color, shape: BoxShape.circle),
              ),
              const SizedBox(width: 6),
            ],
            Text(
              tag.name,
              style: GoogleFonts.manrope(
                fontSize: 12,
                fontWeight: FontWeight.w900,
                color: selected ? Colors.white : EbtlColors.navy,
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class ProductTagSelectedChip extends StatelessWidget {
  final ProductTag tag;
  final VoidCallback onDeleted;

  const ProductTagSelectedChip({
    super.key,
    required this.tag,
    required this.onDeleted,
  });

  @override
  Widget build(BuildContext context) {
    final color = colorFromHex(tag.colorHex);

    return Chip(
      backgroundColor: color.withValues(alpha: 0.12),
      side: BorderSide(color: color.withValues(alpha: 0.42)),
      avatar: Container(
        width: 10,
        height: 10,
        decoration: BoxDecoration(color: color, shape: BoxShape.circle),
      ),
      label: Text(
        tag.name,
        style: GoogleFonts.manrope(
          fontWeight: FontWeight.w900,
          color: EbtlColors.navy,
        ),
      ),
      deleteIcon: const Icon(Icons.close, size: 16),
      onDeleted: onDeleted,
    );
  }
}
