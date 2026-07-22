import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';

import '../../core/theme/ebtl_colors.dart';

class BottlePlaceholder extends StatelessWidget {
  final String name;

  const BottlePlaceholder({super.key, required this.name});

  @override
  Widget build(BuildContext context) {
    return LayoutBuilder(
      builder: (context, constraints) {
        final compact = constraints.maxWidth < 36 || constraints.maxHeight < 36;
        final cleanName = name.trim();

        final label = compact
            ? (cleanName.isEmpty
                  ? '?'
                  : cleanName.substring(0, 1).toUpperCase())
            : (cleanName.isEmpty
                  ? 'BOTTLE'
                  : cleanName.split(RegExp(r'\s+')).first.toUpperCase());

        return CustomPaint(
          painter: BottlePainter(),
          child: Center(
            child: Padding(
              padding: EdgeInsets.only(top: compact ? 0 : 18),
              child: Text(
                label,
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                style: GoogleFonts.manrope(
                  color: EbtlColors.navy,
                  fontWeight: FontWeight.w900,
                  fontSize: compact ? 9 : 10,
                ),
              ),
            ),
          ),
        );
      },
    );
  }
}

class BottlePainter extends CustomPainter {
  @override
  void paint(Canvas canvas, Size size) {
    final paint = Paint()
      ..color = EbtlColors.seafoam.withValues(alpha: 0.65)
      ..style = PaintingStyle.fill;

    final border = Paint()
      ..color = EbtlColors.navy.withValues(alpha: 0.25)
      ..style = PaintingStyle.stroke
      ..strokeWidth = 1.2;

    final body = RRect.fromRectAndRadius(
      Rect.fromLTWH(
        size.width * 0.28,
        size.height * 0.28,
        size.width * 0.44,
        size.height * 0.55,
      ),
      const Radius.circular(10),
    );

    final neck = RRect.fromRectAndRadius(
      Rect.fromLTWH(
        size.width * 0.40,
        size.height * 0.08,
        size.width * 0.20,
        size.height * 0.25,
      ),
      const Radius.circular(4),
    );

    canvas.drawRRect(body, paint);
    canvas.drawRRect(neck, paint);
    canvas.drawRRect(body, border);
    canvas.drawRRect(neck, border);
  }

  @override
  bool shouldRepaint(covariant CustomPainter oldDelegate) => false;
}
