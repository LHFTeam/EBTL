import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';

import '../../../core/theme/ebtl_colors.dart';

/// The last onboarding page: why EBTL wants to send notifications.
///
/// It is a pre-permission primer, not the permission itself. Finishing
/// onboarding mounts `RootShell`, whose `initState` calls
/// `PushNotificationService.initialize()` and raises the OS dialog — so this
/// page is the last thing read before that dialog, and it may only promise what
/// the backend actually pushes: the order-ready notification
/// (`notifyOrderReadyForPickup`) and the referral-credit one
/// (`referral_reward`). Nothing else is sent, so nothing else is claimed.
///
/// Unlike the four artwork pages before it this one is drawn rather than a
/// bundled image, so it follows the splash layout by hand: gold frond, EBTL
/// wordmark in Playfair over the letter-spaced gold tagline, coral eyebrow,
/// serif headline carrying exactly one coral word, teal palm divider, then
/// Manrope body copy.
///
/// Everything above the fold is deliberate: the shared onboarding button floats
/// 58 above the safe area and is 66 tall, so the content has to end above it —
/// see the layout test in `test/onboarding_notification_page_test.dart`. The
/// scroll view underneath is the safety net for large text scaling, not a
/// licence to let the copy run under the button at default scale.
class NotificationPermissionPage extends StatelessWidget {
  const NotificationPermissionPage({super.key});

  /// Space kept clear at the bottom for the shared onboarding button and the
  /// page dots below it.
  static const double controlsReserve = 150;

  /// The reassurance under the benefits. Pinned here because the layout test
  /// measures against it — it is the last thing that must stay above the
  /// button.
  static const String reassurance =
      'Order updates and rewards only. Turn them off any time in your phone '
      'settings.';

  @override
  Widget build(BuildContext context) {
    final bottomPadding = MediaQuery.paddingOf(context).bottom;

    return ColoredBox(
      color: EbtlColors.cream,
      child: SafeArea(
        bottom: false,
        child: SingleChildScrollView(
          padding: EdgeInsets.fromLTRB(
            24,
            12,
            24,
            bottomPadding + controlsReserve,
          ),
          child: Column(
            children: [
              const _SplashWordmark(),
              const SizedBox(height: 14),
              Container(
                width: 60,
                height: 60,
                decoration: BoxDecoration(
                  color: EbtlColors.seafoam,
                  shape: BoxShape.circle,
                  border: Border.all(color: EbtlColors.white, width: 5),
                  boxShadow: [
                    BoxShadow(
                      color: EbtlColors.navy.withValues(alpha: 0.12),
                      blurRadius: 24,
                      offset: const Offset(0, 12),
                    ),
                  ],
                ),
                child: const Icon(
                  Icons.notifications_active_rounded,
                  color: EbtlColors.teal,
                  size: 30,
                ),
              ),
              const SizedBox(height: 14),
              Text(
                'Your cocktail is ready! ✨',
                textAlign: TextAlign.center,
                style: GoogleFonts.playfairDisplay(
                  color: EbtlColors.coral,
                  fontSize: 15,
                  fontStyle: FontStyle.italic,
                  fontWeight: FontWeight.w600,
                ),
              ),
              const SizedBox(height: 8),
              Text.rich(
                const TextSpan(
                  children: [
                    TextSpan(text: 'Never miss\nthe '),
                    TextSpan(
                      text: 'magic.',
                      style: TextStyle(color: EbtlColors.coral),
                    ),
                  ],
                ),
                textAlign: TextAlign.center,
                style: GoogleFonts.playfairDisplay(
                  color: EbtlColors.navy,
                  fontSize: 24,
                  height: 1.15,
                  fontWeight: FontWeight.w600,
                ),
              ),
              const SizedBox(height: 8),
              const _PalmDivider(),
              const SizedBox(height: 8),
              Text(
                'Turn on notifications and we’ll tell you the moment your order '
                'is ready.',
                textAlign: TextAlign.center,
                style: GoogleFonts.manrope(
                  color: EbtlColors.ink,
                  fontSize: 15,
                  height: 1.5,
                  fontWeight: FontWeight.w500,
                ),
              ),
              const SizedBox(height: 12),
              const _NotificationBenefit(
                icon: Icons.schedule_rounded,
                title: 'Pick up at the perfect time',
                body: 'No waiting or checking the app.',
              ),
              const SizedBox(height: 10),
              const _NotificationBenefit(
                icon: Icons.card_giftcard_rounded,
                title: 'Store credit when friends order',
                body: 'The moment a referral reward lands.',
              ),
              const SizedBox(height: 10),
              Text(
                reassurance,
                textAlign: TextAlign.center,
                style: GoogleFonts.manrope(
                  color: EbtlColors.muted,
                  fontSize: 11.5,
                  height: 1.4,
                  fontWeight: FontWeight.w600,
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

/// The masthead every splash page opens with: gold frond, EBTL in Playfair,
/// letter-spaced gold tagline. Matches `EbtlLogo`'s type choice rather than
/// setting the wordmark in Manrope.
class _SplashWordmark extends StatelessWidget {
  const _SplashWordmark();

  @override
  Widget build(BuildContext context) {
    return Column(
      children: [
        const Icon(Icons.spa_rounded, size: 18, color: EbtlColors.gold),
        const SizedBox(height: 6),
        Text(
          'EBTL',
          style: GoogleFonts.playfairDisplay(
            color: EbtlColors.navy,
            fontSize: 34,
            height: 1,
            letterSpacing: 8,
            fontWeight: FontWeight.w600,
          ),
        ),
        const SizedBox(height: 6),
        Text(
          'EVERYTHING BUT THE LIQUOR',
          style: GoogleFonts.manrope(
            color: EbtlColors.gold,
            fontSize: 9,
            letterSpacing: 2.6,
            fontWeight: FontWeight.w700,
          ),
        ),
      ],
    );
  }
}

/// The line–palm–line rule the artwork pages set between headline and body.
class _PalmDivider extends StatelessWidget {
  const _PalmDivider();

  @override
  Widget build(BuildContext context) {
    final rule = Container(
      width: 44,
      height: 1,
      color: EbtlColors.teal.withValues(alpha: 0.4),
    );

    return Row(
      mainAxisAlignment: MainAxisAlignment.center,
      children: [
        rule,
        const Padding(
          padding: EdgeInsets.symmetric(horizontal: 10),
          child: Icon(
            Icons.beach_access_rounded,
            size: 16,
            color: EbtlColors.teal,
          ),
        ),
        rule,
      ],
    );
  }
}

class _NotificationBenefit extends StatelessWidget {
  const _NotificationBenefit({
    required this.icon,
    required this.title,
    required this.body,
  });

  final IconData icon;
  final String title;
  final String body;

  @override
  Widget build(BuildContext context) {
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: EbtlColors.white.withValues(alpha: 0.72),
        borderRadius: BorderRadius.circular(20),
        border: Border.all(color: EbtlColors.sand),
      ),
      child: Row(
        children: [
          Container(
            width: 40,
            height: 40,
            decoration: const BoxDecoration(
              color: EbtlColors.seafoam,
              shape: BoxShape.circle,
            ),
            child: Icon(icon, color: EbtlColors.teal, size: 21),
          ),
          const SizedBox(width: 14),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  title,
                  style: GoogleFonts.manrope(
                    color: EbtlColors.navy,
                    fontSize: 15,
                    fontWeight: FontWeight.w800,
                  ),
                ),
                const SizedBox(height: 3),
                Text(
                  body,
                  style: GoogleFonts.manrope(
                    color: EbtlColors.muted,
                    fontSize: 13,
                    height: 1.35,
                    fontWeight: FontWeight.w500,
                  ),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}
