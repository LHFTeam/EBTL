import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';

import '../../core/constants/onboarding_assets.dart';
import '../../core/theme/ebtl_colors.dart';
import '../../services/analytics_service.dart';

class OnboardingScreen extends StatefulWidget {
  const OnboardingScreen({super.key, required this.onCompleted});

  final Future<void> Function() onCompleted;

  @override
  State<OnboardingScreen> createState() => _OnboardingScreenState();
}

class _OnboardingScreenState extends State<OnboardingScreen> {
  static const _pageCount = 5;

  final PageController _pageController = PageController();
  int _currentPage = 0;
  bool _isCompleting = false;

  @override
  void initState() {
    super.initState();
    AnalyticsService.logScreenView('onboarding');
  }

  @override
  void dispose() {
    _pageController.dispose();
    super.dispose();
  }

  Future<void> _handlePrimaryAction() async {
    if (_isCompleting) return;

    if (_currentPage < _pageCount - 1) {
      await _pageController.nextPage(
        duration: const Duration(milliseconds: 360),
        curve: Curves.easeOutCubic,
      );
      return;
    }

    setState(() => _isCompleting = true);
    try {
      await widget.onCompleted();
    } finally {
      if (mounted) {
        setState(() => _isCompleting = false);
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    final bottomPadding = MediaQuery.paddingOf(context).bottom;
    final isLastPage = _currentPage == _pageCount - 1;

    return Scaffold(
      backgroundColor: EbtlColors.cream,
      body: Stack(
        fit: StackFit.expand,
        children: [
          PageView.builder(
            controller: _pageController,
            itemCount: _pageCount,
            onPageChanged: (index) => setState(() => _currentPage = index),
            itemBuilder: (context, index) {
              if (index == _pageCount - 1) {
                return const _NotificationPermissionPage();
              }

              return Image.asset(
                OnboardingAssets.all[index],
                fit: BoxFit.fitWidth,
                alignment: Alignment.topCenter,
                semanticLabel: _semanticLabelFor(index),
              );
            },
          ),
          Positioned(
            left: 24,
            right: 24,
            bottom: bottomPadding + 58,
            child: _OnboardingButton(
              label: isLastPage ? 'Enable Notifications' : 'Next',
              isLoading: _isCompleting,
              onPressed: _handlePrimaryAction,
            ),
          ),
          Positioned(
            left: 0,
            right: 0,
            bottom: bottomPadding + 24,
            child: _OnboardingDots(
              count: _pageCount,
              activeIndex: _currentPage,
            ),
          ),
        ],
      ),
    );
  }

  String _semanticLabelFor(int index) {
    switch (index) {
      case 0:
        return 'Welcome to EBTL. You bring the bottle. We bring the magic.';
      case 1:
        return 'Step 1. Choose your bottle. Pick the liquor you already have.';
      case 2:
        return 'Step 2. Find cocktails you can make with your bottles.';
      case 3:
        return 'Step 3. Order and pick up. Pay and get notified when your order is ready.';
      case 4:
        return 'Enable notifications to know the moment your order is ready for pickup.';
      default:
        return 'EBTL onboarding screen';
    }
  }
}

class _NotificationPermissionPage extends StatelessWidget {
  const _NotificationPermissionPage();

  @override
  Widget build(BuildContext context) {
    return ColoredBox(
      color: EbtlColors.cream,
      child: SafeArea(
        bottom: false,
        child: SingleChildScrollView(
          padding: const EdgeInsets.fromLTRB(28, 44, 28, 180),
          child: Column(
            children: [
              Text(
                'EBTL',
                style: GoogleFonts.manrope(
                  color: EbtlColors.navy,
                  fontSize: 38,
                  fontWeight: FontWeight.w800,
                  letterSpacing: 8,
                ),
              ),
              const SizedBox(height: 44),
              Container(
                width: 116,
                height: 116,
                decoration: BoxDecoration(
                  color: EbtlColors.seafoam,
                  shape: BoxShape.circle,
                  border: Border.all(color: EbtlColors.white, width: 6),
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
                  size: 56,
                ),
              ),
              const SizedBox(height: 34),
              Text(
                'Your cocktail is ready! ✨',
                textAlign: TextAlign.center,
                style: GoogleFonts.manrope(
                  color: EbtlColors.coral,
                  fontSize: 16,
                  fontWeight: FontWeight.w800,
                  letterSpacing: 0.4,
                ),
              ),
              const SizedBox(height: 12),
              Text(
                'Never miss\nthe magic.',
                textAlign: TextAlign.center,
                style: GoogleFonts.manrope(
                  color: EbtlColors.navy,
                  fontSize: 40,
                  height: 1.08,
                  fontWeight: FontWeight.w800,
                  letterSpacing: -1.2,
                ),
              ),
              const SizedBox(height: 20),
              Text(
                'Turn on notifications and we’ll let you know the moment your order is ready for pickup.',
                textAlign: TextAlign.center,
                style: GoogleFonts.manrope(
                  color: EbtlColors.ink,
                  fontSize: 17,
                  height: 1.55,
                  fontWeight: FontWeight.w500,
                ),
              ),
              const SizedBox(height: 28),
              const _NotificationBenefit(
                icon: Icons.schedule_rounded,
                title: 'Pick up at the perfect time',
                body: 'No waiting around or checking the app.',
              ),
              const SizedBox(height: 14),
              const _NotificationBenefit(
                icon: Icons.local_bar_rounded,
                title: 'Keep every order on your radar',
                body: 'Get the updates that matter while you enjoy the beach.',
              ),
            ],
          ),
        ),
      ),
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
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: EbtlColors.white.withValues(alpha: 0.72),
        borderRadius: BorderRadius.circular(20),
        border: Border.all(color: EbtlColors.sand),
      ),
      child: Row(
        children: [
          Container(
            width: 46,
            height: 46,
            decoration: const BoxDecoration(
              color: EbtlColors.seafoam,
              shape: BoxShape.circle,
            ),
            child: Icon(icon, color: EbtlColors.teal, size: 24),
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

class _OnboardingButton extends StatelessWidget {
  const _OnboardingButton({
    required this.label,
    required this.isLoading,
    required this.onPressed,
  });

  final String label;
  final bool isLoading;
  final VoidCallback onPressed;

  @override
  Widget build(BuildContext context) {
    return Semantics(
      button: true,
      label: label,
      child: SizedBox(
        height: 66,
        child: DecoratedBox(
          decoration: BoxDecoration(
            borderRadius: BorderRadius.circular(28),
            boxShadow: [
              BoxShadow(
                color: EbtlColors.navy.withValues(alpha: 0.16),
                blurRadius: 18,
                offset: const Offset(0, 8),
              ),
            ],
          ),
          child: ElevatedButton(
            onPressed: isLoading ? null : onPressed,
            style: ElevatedButton.styleFrom(
              elevation: 0,
              backgroundColor: EbtlColors.coral,
              disabledBackgroundColor: EbtlColors.coral.withValues(alpha: 0.72),
              foregroundColor: EbtlColors.white,
              disabledForegroundColor: EbtlColors.white,
              shape: RoundedRectangleBorder(
                borderRadius: BorderRadius.circular(28),
                side: BorderSide(
                  color: EbtlColors.white.withValues(alpha: 0.9),
                  width: 1.4,
                ),
              ),
              padding: const EdgeInsets.symmetric(horizontal: 24),
            ),
            child: Stack(
              alignment: Alignment.center,
              children: [
                Center(
                  child: AnimatedSwitcher(
                    duration: const Duration(milliseconds: 180),
                    child: isLoading
                        ? const SizedBox(
                            key: ValueKey('loading'),
                            width: 22,
                            height: 22,
                            child: CircularProgressIndicator(
                              strokeWidth: 2.5,
                              color: EbtlColors.white,
                            ),
                          )
                        : Text(
                            label,
                            key: ValueKey(label),
                            style: GoogleFonts.manrope(
                              fontSize: 22,
                              fontWeight: FontWeight.w700,
                              letterSpacing: -0.2,
                            ),
                          ),
                  ),
                ),
                if (!isLoading)
                  const Positioned(
                    right: 4,
                    child: Icon(Icons.arrow_forward_rounded, size: 30),
                  ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}

class _OnboardingDots extends StatelessWidget {
  const _OnboardingDots({required this.count, required this.activeIndex});

  final int count;
  final int activeIndex;

  @override
  Widget build(BuildContext context) {
    return Row(
      mainAxisAlignment: MainAxisAlignment.center,
      children: List.generate(count, (index) {
        final isActive = index == activeIndex;

        return AnimatedContainer(
          duration: const Duration(milliseconds: 220),
          curve: Curves.easeOutCubic,
          width: isActive ? 14 : 12,
          height: isActive ? 14 : 12,
          margin: const EdgeInsets.symmetric(horizontal: 12),
          decoration: BoxDecoration(
            shape: BoxShape.circle,
            color: isActive ? EbtlColors.coral : EbtlColors.sand,
            border: Border.all(
              color: isActive
                  ? EbtlColors.coral
                  : EbtlColors.gold.withValues(alpha: 0.22),
              width: 1,
            ),
          ),
        );
      }),
    );
  }
}
