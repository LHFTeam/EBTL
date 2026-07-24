import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';

import '../../core/theme/ebtl_colors.dart';

/// The app's primary coral filled-button style: white foreground, no
/// elevation, rounded corners of [radius]. Set [withDisabledColors] to add
/// the sand/muted disabled palette. [textStyle] and [shadowColor] are passed
/// through when provided so call sites keep their exact appearance.
ButtonStyle ebtlCoralButtonStyle({
  double radius = 18,
  bool withDisabledColors = false,
  TextStyle? textStyle,
  Color? shadowColor,
}) {
  return ElevatedButton.styleFrom(
    backgroundColor: EbtlColors.coral,
    disabledBackgroundColor: withDisabledColors ? EbtlColors.sand : null,
    foregroundColor: Colors.white,
    disabledForegroundColor: withDisabledColors ? EbtlColors.muted : null,
    elevation: 0,
    shadowColor: shadowColor,
    shape: RoundedRectangleBorder(
      borderRadius: BorderRadius.circular(radius),
    ),
    textStyle: textStyle,
  );
}

class EbtlLogo extends StatelessWidget {
  const EbtlLogo({super.key});

  @override
  Widget build(BuildContext context) {
    return Row(
      children: [
        const Icon(Icons.beach_access, color: EbtlColors.coral, size: 30),
        const SizedBox(width: 10),
        Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              'EBTL',
              style: GoogleFonts.playfairDisplay(
                fontSize: 38,
                height: 0.9,
                letterSpacing: 6,
                color: EbtlColors.navy,
                fontWeight: FontWeight.w700,
              ),
            ),
            Text(
              'EVERYTHING BUT THE LIQUOR',
              style: GoogleFonts.manrope(
                fontSize: 7,
                letterSpacing: 1.7,
                color: EbtlColors.coral,
                fontWeight: FontWeight.w900,
              ),
            ),
          ],
        ),
      ],
    );
  }
}

class CircleIconButton extends StatelessWidget {
  final IconData icon;
  final VoidCallback onTap;
  final Color iconColor;

  const CircleIconButton({
    super.key,
    required this.icon,
    required this.onTap,
    this.iconColor = Colors.black,
  });

  @override
  Widget build(BuildContext context) {
    return Material(
      color: EbtlColors.white.withValues(alpha: 0.78),
      shape: const CircleBorder(),
      child: InkWell(
        customBorder: const CircleBorder(),
        onTap: onTap,
        child: SizedBox(
          width: 56,
          height: 56,
          child: Icon(icon, color: iconColor, size: 28),
        ),
      ),
    );
  }
}

/// A circular notifications button with an unread badge counter. Used in the
/// top bar of screens (home, shop) in place of the old search/cart shortcuts.
class NotificationsIconButton extends StatelessWidget {
  final int unreadCount;
  final VoidCallback onTap;

  const NotificationsIconButton({
    super.key,
    required this.unreadCount,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    return Stack(
      clipBehavior: Clip.none,
      children: [
        CircleIconButton(
          icon: Icons.notifications_none,
          onTap: onTap,
          iconColor: EbtlColors.navy,
        ),
        if (unreadCount > 0)
          Positioned(
            right: -2,
            top: -4,
            child: IgnorePointer(
              child: Container(
                constraints: const BoxConstraints(minWidth: 20),
                height: 20,
                padding: const EdgeInsets.symmetric(horizontal: 5),
                alignment: Alignment.center,
                decoration: BoxDecoration(
                  color: EbtlColors.coral,
                  borderRadius: BorderRadius.circular(999),
                  border: Border.all(color: EbtlColors.white, width: 1.5),
                ),
                child: Text(
                  unreadCount > 9 ? '9+' : '$unreadCount',
                  style: GoogleFonts.manrope(
                    color: Colors.white,
                    fontSize: 11,
                    height: 1,
                    fontWeight: FontWeight.w900,
                  ),
                ),
              ),
            ),
          ),
      ],
    );
  }
}

class StepBubble extends StatelessWidget {
  final int number;

  const StepBubble({super.key, required this.number});

  @override
  Widget build(BuildContext context) {
    return Container(
      width: 34,
      height: 34,
      decoration: const BoxDecoration(
        color: EbtlColors.coral,
        shape: BoxShape.circle,
      ),
      alignment: Alignment.center,
      child: Text(
        number.toString(),
        style: GoogleFonts.manrope(
          color: Colors.white,
          fontSize: 14,
          fontWeight: FontWeight.w900,
        ),
      ),
    );
  }
}
