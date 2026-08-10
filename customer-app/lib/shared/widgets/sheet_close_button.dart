import 'package:flutter/material.dart';

import '../../core/theme/ebtl_colors.dart';

/// The close control for a full-bleed sheet whose artwork runs under the
/// status bar — the sheet's chrome, so it carries its own scrim rather than
/// relying on the image being light enough behind it. Callers position it
/// themselves (inset by the status bar) over their own artwork.
class SheetCloseButton extends StatelessWidget {
  const SheetCloseButton({super.key});

  @override
  Widget build(BuildContext context) {
    return Material(
      color: EbtlColors.navy.withValues(alpha: 0.55),
      shape: const CircleBorder(),
      child: InkWell(
        onTap: () => Navigator.of(context).pop(),
        customBorder: const CircleBorder(),
        child: const SizedBox(
          width: 36,
          height: 36,
          child: Center(
            child: Icon(
              Icons.close_rounded,
              size: 20,
              color: EbtlColors.white,
            ),
          ),
        ),
      ),
    );
  }
}
