import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';

import '../../core/constants/onboarding_assets.dart';
import '../../core/theme/ebtl_colors.dart';

class OnboardingScreen extends StatefulWidget {
  const OnboardingScreen({super.key, required this.onCompleted});

  final Future<void> Function() onCompleted;

  @override
  State<OnboardingScreen> createState() => _OnboardingScreenState();
}

class _OnboardingScreenState extends State<OnboardingScreen> {
  static const _pageCount = 4;

  final PageController _pageController = PageController();
  int _currentPage = 0;
  bool _isCompleting = false;

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
              label: isLastPage ? 'Get Started' : 'Next',
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
      default:
        return 'EBTL onboarding screen';
    }
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
