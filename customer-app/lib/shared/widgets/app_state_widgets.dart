import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';

import '../../core/theme/ebtl_colors.dart';
import 'brand_widgets.dart';
import 'ebtl_loading_graphic.dart';

export 'app_toast.dart';

Widget theLoadingScaffold() {
  return const Scaffold(
    backgroundColor: EbtlColors.cream,
    body: SafeArea(
      child: EbtlLoadingGraphic(label: 'Mixing things up...'),
    ),
  );
}

class EbtlLoadingSection extends StatelessWidget {
  const EbtlLoadingSection({
    super.key,
    this.padding = const EdgeInsets.all(28),
    this.size = 86,
    this.label = 'Mixing things up...',
    this.showLabel = true,
  });

  final EdgeInsetsGeometry padding;
  final double size;
  final String label;
  final bool showLabel;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: padding,
      child: EbtlLoadingGraphic(
        size: size,
        label: label,
        showLabel: showLabel,
      ),
    );
  }
}

class EbtlLoadingSliver extends StatelessWidget {
  const EbtlLoadingSliver({
    super.key,
    this.padding = const EdgeInsets.all(28),
    this.size = 86,
    this.label = 'Mixing things up...',
    this.showLabel = true,
  });

  final EdgeInsetsGeometry padding;
  final double size;
  final String label;
  final bool showLabel;

  @override
  Widget build(BuildContext context) {
    return SliverToBoxAdapter(
      child: EbtlLoadingSection(
        padding: padding,
        size: size,
        label: label,
        showLabel: showLabel,
      ),
    );
  }
}

class EmptyStateCard extends StatelessWidget {
  final String message;

  const EmptyStateCard({super.key, required this.message});

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 22),
      child: Container(
        width: double.infinity,
        padding: const EdgeInsets.all(18),
        decoration: BoxDecoration(
          color: EbtlColors.white.withValues(alpha: 0.82),
          borderRadius: BorderRadius.circular(20),
          border: Border.all(color: EbtlColors.border),
        ),
        child: Row(
          children: [
            const Icon(Icons.info_outline, color: EbtlColors.coral),
            const SizedBox(width: 12),
            Expanded(
              child: Text(
                message,
                style: GoogleFonts.manrope(
                  color: EbtlColors.ink,
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

class InlineErrorCard extends StatelessWidget {
  final String message;
  final VoidCallback onRetry;

  const InlineErrorCard({
    super.key,
    required this.message,
    required this.onRetry,
  });

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.all(22),
      child: Container(
        width: double.infinity,
        padding: const EdgeInsets.all(18),
        decoration: BoxDecoration(
          color: EbtlColors.white,
          borderRadius: BorderRadius.circular(20),
          border: Border.all(color: EbtlColors.border),
        ),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              'Could not load cocktails.',
              style: GoogleFonts.manrope(
                color: EbtlColors.navy,
                fontWeight: FontWeight.w900,
                fontSize: 16,
              ),
            ),
            const SizedBox(height: 10),
            Text(
              message,
              style: GoogleFonts.manrope(
                color: EbtlColors.ink,
                fontWeight: FontWeight.w600,
                fontSize: 12,
                height: 1.35,
              ),
            ),
            const SizedBox(height: 14),
            ElevatedButton(
              onPressed: onRetry,
              style: ebtlCoralButtonStyle(radius: 16),
              child: Text(
                'Try Again',
                style: GoogleFonts.manrope(fontWeight: FontWeight.w900),
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class AppErrorScreen extends StatelessWidget {
  final String message;
  final VoidCallback onRetry;

  const AppErrorScreen({
    super.key,
    required this.message,
    required this.onRetry,
  });

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: EbtlColors.cream,
      body: SafeArea(
        child: Padding(
          padding: const EdgeInsets.all(22),
          child: Center(
            child: Container(
              padding: const EdgeInsets.all(20),
              decoration: BoxDecoration(
                color: EbtlColors.white,
                borderRadius: BorderRadius.circular(22),
                border: Border.all(color: EbtlColors.border),
              ),
              child: Column(
                mainAxisSize: MainAxisSize.min,
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    'The app failed to load.',
                    style: GoogleFonts.playfairDisplay(
                      fontSize: 30,
                      fontWeight: FontWeight.w800,
                      color: EbtlColors.navy,
                    ),
                  ),
                  const SizedBox(height: 12),
                  Text(
                    'The customer API did not return the expected response.',
                    style: GoogleFonts.manrope(
                      fontSize: 15,
                      height: 1.4,
                      fontWeight: FontWeight.w600,
                      color: EbtlColors.ink,
                    ),
                  ),
                  const SizedBox(height: 18),
                  Container(
                    width: double.infinity,
                    padding: const EdgeInsets.all(14),
                    decoration: BoxDecoration(
                      color: EbtlColors.sand.withValues(alpha: 0.55),
                      borderRadius: BorderRadius.circular(14),
                    ),
                    child: Text(
                      message,
                      style: GoogleFonts.manrope(
                        fontSize: 12,
                        height: 1.35,
                        color: EbtlColors.ink,
                        fontWeight: FontWeight.w600,
                      ),
                    ),
                  ),
                  const SizedBox(height: 18),
                  SizedBox(
                    width: double.infinity,
                    height: 54,
                    child: ElevatedButton(
                      onPressed: onRetry,
                      style: ebtlCoralButtonStyle(),
                      child: Text(
                        'Try Again',
                        style: GoogleFonts.manrope(
                          fontSize: 15,
                          fontWeight: FontWeight.w900,
                        ),
                      ),
                    ),
                  ),
                ],
              ),
            ),
          ),
        ),
      ),
    );
  }
}
