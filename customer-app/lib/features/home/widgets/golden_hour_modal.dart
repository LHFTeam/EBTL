import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';

import '../../../core/constants/cocktail_assets.dart';
import '../../../core/network/api_exception.dart';
import '../../../core/theme/ebtl_colors.dart';
import '../../../models/common_models.dart';
import '../../../models/golden_hour_models.dart';
import '../../../services/analytics_service.dart';
import '../../../services/api_service.dart';
import '../../../shared/widgets/app_toast.dart';
import '../../../shared/widgets/network_or_asset_image.dart';

/// The Golden Hour card, shown once on launch when the customer already has a
/// beach cart chosen.
///
/// Everything on it — copy, image, cocktail, pills, and which of the four
/// time-of-day modes is showing — comes from Marketing → Golden Hour in the
/// dashboard. The app draws whatever it is given and owns only the colours
/// behind the pill scheme names.
///
/// Resolves when the card closes. [onCartChanged] fires before that if the
/// customer added the cocktail, so the shell's badge is current by the time the
/// card is gone.
Future<void> showGoldenHourModal({
  required BuildContext context,
  required GoldenHourModal modal,
  required String locationId,
  required ValueChanged<CartSummary?> onCartChanged,
  required VoidCallback onOpenCocktail,
}) {
  return showDialog<void>(
    context: context,
    barrierColor: EbtlColors.navy.withValues(alpha: 0.55),
    builder: (dialogContext) => _GoldenHourDialog(
      modal: modal,
      locationId: locationId,
      onCartChanged: onCartChanged,
      onOpenCocktail: onOpenCocktail,
    ),
  );
}

class _GoldenHourDialog extends StatefulWidget {
  final GoldenHourModal modal;
  final String locationId;
  final ValueChanged<CartSummary?> onCartChanged;
  final VoidCallback onOpenCocktail;

  const _GoldenHourDialog({
    required this.modal,
    required this.locationId,
    required this.onCartChanged,
    required this.onOpenCocktail,
  });

  @override
  State<_GoldenHourDialog> createState() => _GoldenHourDialogState();
}

class _GoldenHourDialogState extends State<_GoldenHourDialog> {
  bool isAdding = false;

  /// Adds the card's cocktail to the cart.
  ///
  /// The card carries a slug, not a variant, so the cocktail is loaded first —
  /// the same route "Order It Again" takes on Home. That costs a request but
  /// means the kit is added at today's price and availability for this beach
  /// cart, rather than whatever was true when marketing wrote the card.
  Future<void> addToCart() async {
    if (isAdding) return;
    setState(() => isAdding = true);

    try {
      final detail = await ApiService.fetchCocktailDetail(
        slug: widget.modal.cocktail.slug,
        locationId: widget.locationId,
      );
      final cocktail = detail.cocktail;
      final variant = cocktail.variant;

      if (variant == null || !cocktail.canAddToCart) {
        if (!mounted) return;
        setState(() => isAdding = false);
        showAppSnackBar(context, cocktail.availabilityMessage);
        return;
      }

      final result = await ApiService.addCocktailToCart(
        cocktailId: cocktail.id,
        variantId: variant.id,
        selectedQuantity: 1,
        locationId: widget.locationId,
      );

      AnalyticsService.logAddToCart(
        AnalyticsItem(
          id: cocktail.id,
          name: cocktail.name,
          category: cocktail.category?.name ?? 'cocktail',
          variant: variant.name,
          price: variant.priceIncVat,
          quantity: 1,
          currency: variant.currency,
        ),
      );

      if (!mounted) return;

      widget.onCartChanged(result.totals);
      Navigator.of(context).pop();
    } catch (error) {
      if (!mounted) return;

      setState(() => isAdding = false);
      showAppSnackBar(
        context,
        apiErrorMessage(error, fallback: 'Could not add this to your cart.'),
      );
    }
  }

  @override
  Widget build(BuildContext context) {
    final modal = widget.modal;
    final subtitle = modal.subtitle?.trim();
    final caption = modal.imageCaption?.trim();

    return Dialog(
      backgroundColor: EbtlColors.cream,
      insetPadding: const EdgeInsets.symmetric(horizontal: 20, vertical: 40),
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(28)),
      clipBehavior: Clip.antiAlias,
      child: ConstrainedBox(
        // Tall copy or a long pill row must scroll inside the card rather than
        // push it past the screen — the modal is opened before the customer has
        // done anything, so it can never be the thing that blocks the app.
        constraints: BoxConstraints(
          maxHeight: MediaQuery.sizeOf(context).height * 0.85,
        ),
        child: SingleChildScrollView(
          child: Padding(
            padding: const EdgeInsets.fromLTRB(22, 14, 22, 22),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Align(
                  alignment: Alignment.centerRight,
                  child: IconButton(
                    onPressed: () => Navigator.of(context).pop(),
                    icon: const Icon(Icons.close_rounded),
                    color: EbtlColors.muted,
                    tooltip: 'Close',
                    padding: EdgeInsets.zero,
                    constraints: const BoxConstraints(
                      minWidth: 40,
                      minHeight: 40,
                    ),
                  ),
                ),

                Text(
                  modal.title,
                  style: GoogleFonts.playfairDisplay(
                    fontSize: 26,
                    height: 1.15,
                    fontWeight: FontWeight.w800,
                    color: EbtlColors.navy,
                  ),
                ),

                if (subtitle != null && subtitle.isNotEmpty) ...[
                  const SizedBox(height: 8),
                  Text(
                    subtitle,
                    style: GoogleFonts.manrope(
                      fontSize: 14,
                      height: 1.45,
                      color: EbtlColors.muted,
                    ),
                  ),
                ],

                if (modal.hasImage) ...[
                  const SizedBox(height: 18),
                  ClipRRect(
                    borderRadius: BorderRadius.circular(20),
                    child: AspectRatio(
                      aspectRatio: 4 / 3,
                      child: NetworkOrAssetImage(
                        imageUrl: modal.imageUrl,
                        // The bundled cocktail art is keyed by name, so a card
                        // whose image fails to load still shows its drink.
                        asset: CocktailAssets.forName(modal.cocktail.name),
                      ),
                    ),
                  ),
                ],

                if (caption != null && caption.isNotEmpty) ...[
                  const SizedBox(height: 10),
                  Text(
                    caption,
                    style: GoogleFonts.manrope(
                      fontSize: 13,
                      height: 1.4,
                      fontWeight: FontWeight.w600,
                      color: EbtlColors.ink,
                    ),
                  ),
                ],

                const SizedBox(height: 16),
                _PillRow(modal: modal),

                const SizedBox(height: 20),
                SizedBox(
                  width: double.infinity,
                  height: 52,
                  child: ElevatedButton(
                    onPressed: isAdding ? null : addToCart,
                    style: ElevatedButton.styleFrom(
                      backgroundColor: EbtlColors.coral,
                      foregroundColor: EbtlColors.white,
                      disabledBackgroundColor: EbtlColors.coral.withValues(
                        alpha: 0.6,
                      ),
                      disabledForegroundColor: EbtlColors.white,
                      elevation: 0,
                      shape: RoundedRectangleBorder(
                        borderRadius: BorderRadius.circular(16),
                      ),
                    ),
                    child: isAdding
                        ? const SizedBox(
                            width: 20,
                            height: 20,
                            child: CircularProgressIndicator(
                              strokeWidth: 2.2,
                              color: EbtlColors.white,
                            ),
                          )
                        : Text(
                            'Add to cart',
                            style: GoogleFonts.manrope(
                              fontSize: 15,
                              fontWeight: FontWeight.w800,
                            ),
                          ),
                  ),
                ),

                const SizedBox(height: 6),
                Center(
                  child: TextButton(
                    onPressed: isAdding
                        ? null
                        : () {
                            Navigator.of(context).pop();
                            widget.onOpenCocktail();
                          },
                    child: Text(
                      'See the recipe',
                      style: GoogleFonts.manrope(
                        fontSize: 14,
                        fontWeight: FontWeight.w700,
                        color: EbtlColors.teal,
                      ),
                    ),
                  ),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}

/// The spirit pill, then whatever marketing put after it. Wraps rather than
/// scrolls: the backend caps the list at four, and a pill that fell off the
/// edge would be a pill nobody reads.
class _PillRow extends StatelessWidget {
  final GoldenHourModal modal;

  const _PillRow({required this.modal});

  @override
  Widget build(BuildContext context) {
    final pills = <GoldenHourPill>[modal.spiritPill, ...modal.pills]
        .where((pill) => pill.label.isNotEmpty)
        .toList(growable: false);

    if (pills.isEmpty) return const SizedBox.shrink();

    return Wrap(
      spacing: 8,
      runSpacing: 8,
      children: pills.map((pill) {
        final colors = pill.colors;

        return Container(
          padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 7),
          decoration: BoxDecoration(
            color: colors.background,
            borderRadius: BorderRadius.circular(999),
          ),
          child: Text(
            pill.label,
            style: GoogleFonts.manrope(
              fontSize: 13,
              fontWeight: FontWeight.w700,
              color: colors.foreground,
            ),
          ),
        );
      }).toList(growable: false),
    );
  }
}
