import 'package:clarity_flutter/clarity_flutter.dart';
import 'package:flutter/material.dart';
import 'package:flutter_svg/flutter_svg.dart';
import 'package:google_fonts/google_fonts.dart';

import '../../core/theme/ebtl_colors.dart';
import '../../models/profile_models.dart';
import '../../services/social_auth_service.dart';
import '../../shared/widgets/app_state_widgets.dart';

/// The app's one and only sign-in surface.
///
/// It sits on the order confirmation screen and nowhere else, deliberately.
/// Everything it offers is a reason to keep an account, never a reason the
/// order needed one — a customer who dismisses this has lost nothing, and the
/// screen around it reads as finished without it.
class SocialSignInCard extends StatefulWidget {
  final String orderNumber;

  const SocialSignInCard({super.key, required this.orderNumber});

  @override
  State<SocialSignInCard> createState() => _SocialSignInCardState();
}

class _SocialSignInCardState extends State<SocialSignInCard> {
  /// Which provider is mid-flight. Only one at a time — the others go flat
  /// while it runs so a second sheet cannot be opened behind the first.
  SocialProvider? pending;

  CustomerProfile? linkedProfile;
  bool dismissed = false;

  Future<void> signIn(SocialProvider provider) async {
    if (pending != null) return;

    setState(() => pending = provider);

    try {
      final profile = await SocialAuthService.signIn(provider);
      if (!mounted) return;
      setState(() {
        linkedProfile = profile;
        pending = null;
      });
    } on SocialAuthException catch (error) {
      if (!mounted) return;
      setState(() => pending = null);

      // Backing out of a provider sheet is not a failure and gets no message.
      if (error.cancelled) return;
      showAppSnackBar(context, error.message);
    } catch (error) {
      if (!mounted) return;
      setState(() => pending = null);
      showAppSnackBar(context, 'Could not sign in: $error');
    }
  }

  @override
  Widget build(BuildContext context) {
    if (dismissed && linkedProfile == null) return const SizedBox.shrink();

    final profile = linkedProfile;
    if (profile != null) return _SignedInStrip(profile: profile);

    return ClarityMask(
      child: Container(
        padding: const EdgeInsets.fromLTRB(20, 20, 20, 16),
        decoration: BoxDecoration(
          color: EbtlColors.navy,
          borderRadius: BorderRadius.circular(22),
          boxShadow: [
            BoxShadow(
              color: EbtlColors.navy.withValues(alpha: 0.22),
              blurRadius: 30,
              offset: const Offset(0, 16),
            ),
          ],
        ),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Text(
              'Keep this order',
              style: GoogleFonts.playfairDisplay(
                fontSize: 26,
                height: 1.1,
                fontWeight: FontWeight.w800,
                color: EbtlColors.cream,
              ),
            ),
            const SizedBox(height: 8),
            Text(
              'Order ${widget.orderNumber} is saved to this phone only. Sign in '
              'and it follows you — with everything else you have built up here.',
              style: GoogleFonts.manrope(
                fontSize: 13.5,
                height: 1.4,
                fontWeight: FontWeight.w500,
                color: EbtlColors.cream.withValues(alpha: 0.78),
              ),
            ),
            const SizedBox(height: 18),
            const _BenefitRow(
              icon: Icons.receipt_long_outlined,
              accent: EbtlColors.blush,
              title: 'Your order history',
              subtitle: 'Every order, on any phone you sign in on',
            ),
            const _BenefitRow(
              icon: Icons.local_bar_outlined,
              accent: EbtlColors.seafoam,
              title: 'Your spirits and favourites',
              subtitle: 'The bottles you own, kept for the Cocktail Finder',
            ),
            const _BenefitRow(
              icon: Icons.stars_outlined,
              accent: EbtlColors.gold,
              title: 'Loyalty points',
              subtitle: 'Earn points on every order and spend them on kits',
            ),
            const _BenefitRow(
              icon: Icons.card_giftcard_outlined,
              accent: EbtlColors.blush,
              title: 'Your referral bonuses',
              subtitle: 'Credit you have earned stays yours',
            ),
            const SizedBox(height: 18),
            _ProviderButton(
              provider: SocialProvider.facebook,
              assetPath: 'assets/images/social/facebook.svg',
              background: const Color(0xFF1877F2),
              foreground: EbtlColors.white,
              isBusy: pending == SocialProvider.facebook,
              isEnabled: pending == null,
              onPressed: () => signIn(SocialProvider.facebook),
            ),
            if (SocialAuthService.supportsGoogle) ...[
              const SizedBox(height: 10),
              _ProviderButton(
                provider: SocialProvider.google,
                assetPath: 'assets/images/social/google.svg',
                background: EbtlColors.white,
                foreground: EbtlColors.ink,
                isBusy: pending == SocialProvider.google,
                isEnabled: pending == null,
                onPressed: () => signIn(SocialProvider.google),
              ),
            ],
            if (SocialAuthService.supportsApple) ...[
              const SizedBox(height: 10),
              _ProviderButton(
                provider: SocialProvider.apple,
                assetPath: 'assets/images/social/apple.svg',
                background: Colors.black,
                foreground: EbtlColors.white,
                isBusy: pending == SocialProvider.apple,
                isEnabled: pending == null,
                onPressed: () => signIn(SocialProvider.apple),
              ),
            ],
            const SizedBox(height: 6),
            TextButton(
              onPressed: pending != null
                  ? null
                  : () => setState(() => dismissed = true),
              style: TextButton.styleFrom(
                foregroundColor: EbtlColors.cream.withValues(alpha: 0.7),
                minimumSize: const Size.fromHeight(44),
              ),
              child: Text(
                'Not now',
                style: GoogleFonts.manrope(
                  fontSize: 14,
                  fontWeight: FontWeight.w700,
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _BenefitRow extends StatelessWidget {
  final IconData icon;
  final Color accent;
  final String title;
  final String subtitle;

  const _BenefitRow({
    required this.icon,
    required this.accent,
    required this.title,
    required this.subtitle,
  });

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 12),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Container(
            width: 38,
            height: 38,
            decoration: BoxDecoration(
              color: accent.withValues(alpha: 0.16),
              shape: BoxShape.circle,
            ),
            child: Icon(icon, size: 20, color: accent),
          ),
          const SizedBox(width: 14),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  title,
                  style: GoogleFonts.manrope(
                    fontSize: 14.5,
                    height: 1.2,
                    fontWeight: FontWeight.w800,
                    color: EbtlColors.cream,
                  ),
                ),
                const SizedBox(height: 2),
                Text(
                  subtitle,
                  style: GoogleFonts.manrope(
                    fontSize: 12.5,
                    height: 1.3,
                    fontWeight: FontWeight.w500,
                    color: EbtlColors.cream.withValues(alpha: 0.66),
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

class _ProviderButton extends StatelessWidget {
  final SocialProvider provider;
  final String assetPath;
  final Color background;
  final Color foreground;
  final bool isBusy;
  final bool isEnabled;
  final VoidCallback onPressed;

  const _ProviderButton({
    required this.provider,
    required this.assetPath,
    required this.background,
    required this.foreground,
    required this.isBusy,
    required this.isEnabled,
    required this.onPressed,
  });

  @override
  Widget build(BuildContext context) {
    return Opacity(
      // A provider that is not the one running goes quiet rather than
      // disappearing, so the row does not reflow mid-flow.
      opacity: isEnabled || isBusy ? 1 : 0.45,
      child: SizedBox(
        height: 52,
        child: ElevatedButton(
          onPressed: isEnabled ? onPressed : null,
          style: ElevatedButton.styleFrom(
            backgroundColor: background,
            foregroundColor: foreground,
            disabledBackgroundColor: background,
            disabledForegroundColor: foreground,
            elevation: 0,
            // The default 16pt side padding leaves too little for "Continue
            // with Facebook" inside a card that is already inset twice on a
            // 390pt screen.
            padding: const EdgeInsets.symmetric(horizontal: 12),
            shape: RoundedRectangleBorder(
              borderRadius: BorderRadius.circular(14),
            ),
          ),
          child: isBusy
              ? SizedBox(
                  width: 22,
                  height: 22,
                  child: CircularProgressIndicator(
                    strokeWidth: 2.5,
                    color: foreground,
                  ),
                )
              : Row(
                  mainAxisAlignment: MainAxisAlignment.center,
                  children: [
                    SvgPicture.asset(assetPath, width: 21, height: 21),
                    const SizedBox(width: 12),
                    Flexible(
                      child: Text(
                        'Continue with ${provider.displayName}',
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: GoogleFonts.manrope(
                          fontSize: 15,
                          fontWeight: FontWeight.w800,
                        ),
                      ),
                    ),
                  ],
                ),
        ),
      ),
    );
  }
}

/// What the card becomes once an identity is attached: a single quiet line,
/// not a second celebration. The order is still the point of the screen.
class _SignedInStrip extends StatelessWidget {
  final CustomerProfile profile;

  const _SignedInStrip({required this.profile});

  @override
  Widget build(BuildContext context) {
    final name = profile.fullName?.trim() ?? '';
    final email = profile.email?.trim() ?? '';
    final who = name.isNotEmpty
        ? name
        : email.isNotEmpty
        ? email
        : 'your account';

    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 18, vertical: 16),
      decoration: BoxDecoration(
        color: EbtlColors.seafoam.withValues(alpha: 0.42),
        borderRadius: BorderRadius.circular(20),
        border: Border.all(color: EbtlColors.teal.withValues(alpha: 0.2)),
      ),
      child: Row(
        children: [
          Container(
            width: 42,
            height: 42,
            decoration: BoxDecoration(
              color: EbtlColors.white.withValues(alpha: 0.6),
              shape: BoxShape.circle,
            ),
            child: const Icon(
              Icons.check_rounded,
              color: EbtlColors.teal,
              size: 22,
            ),
          ),
          const SizedBox(width: 14),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  'Saved to $who',
                  style: GoogleFonts.manrope(
                    fontSize: 15,
                    height: 1.2,
                    fontWeight: FontWeight.w900,
                    color: EbtlColors.teal,
                  ),
                ),
                const SizedBox(height: 2),
                Text(
                  'Your orders, spirits and credit follow you from here.',
                  style: GoogleFonts.manrope(
                    fontSize: 12.5,
                    height: 1.3,
                    fontWeight: FontWeight.w600,
                    color: EbtlColors.ink.withValues(alpha: 0.72),
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
