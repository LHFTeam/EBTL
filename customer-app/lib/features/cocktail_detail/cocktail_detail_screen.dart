import 'package:flutter/material.dart';
import 'package:flutter_markdown/flutter_markdown.dart';
import 'package:google_fonts/google_fonts.dart';

import '../../core/network/api_exception.dart';
import '../../core/theme/ebtl_colors.dart';
import '../../core/theme/ebtl_text_styles.dart';
import '../../core/utils/formatters.dart';
import '../../models/cocktail_detail_models.dart';
import '../../services/api_service.dart';
import '../../shared/widgets/app_state_widgets.dart';
import '../../shared/widgets/bottle_widgets.dart';
import '../../shared/widgets/brand_widgets.dart';
import '../../shared/widgets/ebtl_bottom_nav.dart';
import '../../shared/widgets/ebtl_loading_graphic.dart';
import '../../shared/widgets/ingredient_svg_icon.dart';
import '../../shared/widgets/network_or_asset_image.dart';
import '../../shared/widgets/product_tag_widgets.dart';
import '../../shared/widgets/detail_card.dart';

class CocktailDetailScreen extends StatefulWidget {
  final String slug;
  final String? locationId;
  final String? locationName;
  final String? liquorTypeId;
  final int selectedNavIndex;
  final int initialCartQuantity;
  final VoidCallback onCartChanged;
  final ValueChanged<int> onBottomNavTap;

  const CocktailDetailScreen({
    super.key,
    required this.slug,
    required this.locationId,
    required this.locationName,
    required this.liquorTypeId,
    required this.selectedNavIndex,
    required this.initialCartQuantity,
    required this.onCartChanged,
    required this.onBottomNavTap,
  });

  @override
  State<CocktailDetailScreen> createState() => _CocktailDetailScreenState();
}

class _CocktailDetailScreenState extends State<CocktailDetailScreen> {
  late String activeSlug;
  late Future<CocktailDetailResponse> detailFuture;

  int selectedQuantity = 1;
  int? cartQuantityOverride;
  bool isAddingToCart = false;

  // Local override so the heart reacts immediately; null means "use the value
  // from the loaded detail response".
  bool? favoriteOverride;
  bool isTogglingFavorite = false;

  final Set<String> selectedRemovedRecipeItemIds = <String>{};
  final Map<String, SelectedAddition> selectedAdditionsByVariantId =
      <String, SelectedAddition>{};

  @override
  void initState() {
    super.initState();
    activeSlug = widget.slug;
    detailFuture = loadDetail();
  }

  Future<CocktailDetailResponse> loadDetail() {
    return ApiService.fetchCocktailDetail(
      slug: activeSlug,
      locationId: widget.locationId,
      liquorTypeId: widget.liquorTypeId,
    );
  }

  void reloadDetail() {
    setState(() {
      detailFuture = loadDetail();
    });
  }

  void openRelated(String slug) {
    if (slug.trim().isEmpty || slug == activeSlug) return;

    setState(() {
      activeSlug = slug;
      selectedQuantity = 1;
      favoriteOverride = null;
      selectedRemovedRecipeItemIds.clear();
      selectedAdditionsByVariantId.clear();
      detailFuture = loadDetail();
    });
  }

  Future<void> toggleFavorite(CocktailDetail cocktail) async {
    if (isTogglingFavorite) return;

    final productId = cocktail.id.trim();
    if (productId.isEmpty) return;

    final current = favoriteOverride ?? cocktail.isFavorite;
    final next = !current;

    setState(() {
      isTogglingFavorite = true;
      favoriteOverride = next;
    });

    try {
      if (next) {
        await ApiService.addFavoriteCocktail(productId: productId);
      } else {
        await ApiService.removeFavoriteCocktail(productId: productId);
      }

      if (!mounted) return;
      setState(() => isTogglingFavorite = false);
      showAppSnackBar(
        context,
        next ? 'Added to favorites.' : 'Removed from favorites.',
      );
    } catch (error) {
      if (!mounted) return;
      setState(() {
        isTogglingFavorite = false;
        favoriteOverride = current;
      });
      showAppSnackBar(
        context,
        apiErrorMessage(error, fallback: 'Could not update favorites.'),
      );
    }
  }

  void toggleRemovedIngredient(RemovableIngredient ingredient) {
    final recipeItemId = ingredient.recipeItemId.trim();
    if (recipeItemId.isEmpty) return;

    setState(() {
      if (selectedRemovedRecipeItemIds.contains(recipeItemId)) {
        selectedRemovedRecipeItemIds.remove(recipeItemId);
      } else {
        selectedRemovedRecipeItemIds.add(recipeItemId);
      }
    });
  }

  void toggleAddition(CocktailAdditionOption addition) {
    if (!addition.isOrderable) return;

    final variantId = addition.variantId.trim();
    final productId = addition.productId.trim();

    if (variantId.isEmpty || productId.isEmpty) return;

    setState(() {
      if (selectedAdditionsByVariantId.containsKey(variantId)) {
        selectedAdditionsByVariantId.remove(variantId);
      } else {
        selectedAdditionsByVariantId[variantId] = SelectedAddition(
          productId: productId,
          variantId: variantId,
          quantity: 1,
        );
      }
    });
  }

  double selectedAdditionsUnitTotal(CocktailDetail cocktail) {
    return cocktail.customization.additions.fold<double>(0, (sum, addition) {
      if (!selectedAdditionsByVariantId.containsKey(addition.variantId)) {
        return sum;
      }

      return sum + addition.priceIncVat;
    });
  }

  String? effectiveSelectedLiquorTypeId(CocktailDetail cocktail) {
    final fromDetail = cocktail.selectedLiquor?.id.trim();
    if (fromDetail != null && fromDetail.isNotEmpty) return fromDetail;

    final fromRoute = widget.liquorTypeId?.trim();
    if (fromRoute != null && fromRoute.isNotEmpty) return fromRoute;

    return null;
  }

  String addToCartErrorMessage(Object error) {
    return apiErrorMessage(error, fallback: 'Could not add item to cart.');
  }

  Future<void> addToCart(CocktailDetail cocktail) async {
    if (isAddingToCart) return;

    final locationId = widget.locationId?.trim();
    final variant = cocktail.variant;

    if (locationId == null || locationId.isEmpty) {
      showAppSnackBar(context, 'Choose a beach cart first.');
      return;
    }

    if (variant == null) {
      showAppSnackBar(context, 'No serving size is available.');
      return;
    }

    if (selectedQuantity < 1) {
      showAppSnackBar(context, 'Choose at least 1 item.');
      return;
    }

    if (!cocktail.canAddToCart) {
      showAppSnackBar(context, cocktail.availabilityMessage);
      return;
    }

    setState(() => isAddingToCart = true);

    try {
      final result = await ApiService.addCocktailToCart(
        cocktailId: cocktail.id,
        variantId: variant.id,
        selectedQuantity: selectedQuantity,
        locationId: locationId,
        selectedLiquorTypeId: effectiveSelectedLiquorTypeId(cocktail),
        removedRecipeItemIds: selectedRemovedRecipeItemIds,
        selectedAdditions: selectedAdditionsByVariantId.values.toList(),
      );

      if (!mounted) return;

      setState(() {
        isAddingToCart = false;
        selectedQuantity = 1;
        cartQuantityOverride =
            result.totals?.totalQuantity ?? cartQuantityOverride;
      });

      widget.onCartChanged();

      showAppSnackBar(context, result.successMessage);
      Navigator.of(context).pop();
    } catch (error) {
      if (!mounted) return;

      setState(() => isAddingToCart = false);

      showAppSnackBar(context, addToCartErrorMessage(error));
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: EbtlColors.cream,
      bottomNavigationBar: EbtlBottomNav(
        selectedIndex: widget.selectedNavIndex,
        onTap: widget.onBottomNavTap,
      ),
      body: FutureBuilder<CocktailDetailResponse>(
        future: detailFuture,
        builder: (context, snapshot) {
          if (snapshot.connectionState == ConnectionState.waiting) {
            return const SafeArea(
              child: EbtlLoadingGraphic(label: 'Mixing your cocktail...'),
            );
          }

          if (snapshot.hasError) {
            return CocktailDetailErrorState(
              message: apiErrorMessage(snapshot.error!),
              onRetry: reloadDetail,
            );
          }

          final response = snapshot.data;
          if (response == null) {
            return CocktailDetailErrorState(
              message: 'The backend returned no cocktail details.',
              onRetry: reloadDetail,
            );
          }

          final cocktail = response.cocktail;
          final hasLocation = widget.locationId?.trim().isNotEmpty == true;

          final cartCount =
              cartQuantityOverride ??
              (response.cartContext.totalQuantity > 0
                  ? response.cartContext.totalQuantity
                  : widget.initialCartQuantity);

          return Stack(
            children: [
              CustomScrollView(
                slivers: [
                  SliverToBoxAdapter(
                    child: CocktailDetailHero(
                      cocktail: cocktail,
                      cartCount: cartCount,
                      isFavorite: favoriteOverride ?? cocktail.isFavorite,
                      onBack: () => Navigator.of(context).pop(),
                      onFavorite: () => toggleFavorite(cocktail),
                      onCart: () => widget.onBottomNavTap(3),
                    ),
                  ),
                  SliverToBoxAdapter(
                    child: CocktailDetailContent(
                      response: response,
                      locationId: widget.locationId,
                      locationName: widget.locationName,
                      selectedRemovedRecipeItemIds:
                          selectedRemovedRecipeItemIds,
                      selectedAdditionsByVariantId:
                          selectedAdditionsByVariantId,
                      onRemovedIngredientToggle: toggleRemovedIngredient,
                      onAdditionToggle: toggleAddition,
                      onRelatedTap: openRelated,
                    ),
                  ),
                  const SliverToBoxAdapter(child: SizedBox(height: 118)),
                ],
              ),
              Positioned(
                left: 0,
                right: 0,
                bottom: 0,
                child: CocktailDetailAddBar(
                  cocktail: cocktail,
                  selectedQuantity: selectedQuantity,
                  selectedAdditionsUnitTotal: selectedAdditionsUnitTotal(
                    cocktail,
                  ),
                  hasLocation: hasLocation,
                  isAdding: isAddingToCart,
                  onIncrement: () {
                    if (selectedQuantity >= 99) return;
                    setState(() => selectedQuantity += 1);
                  },
                  onDecrement: () {
                    if (selectedQuantity <= 1) return;
                    setState(() => selectedQuantity -= 1);
                  },
                  onAdd: cocktail.canAddToCart && hasLocation && !isAddingToCart
                      ? () => addToCart(cocktail)
                      : null,
                ),
              ),
            ],
          );
        },
      ),
    );
  }
}

class CocktailDetailHero extends StatelessWidget {
  final CocktailDetail cocktail;
  final int cartCount;
  final bool isFavorite;
  final VoidCallback onBack;
  final VoidCallback onFavorite;
  final VoidCallback onCart;

  const CocktailDetailHero({
    super.key,
    required this.cocktail,
    required this.cartCount,
    required this.isFavorite,
    required this.onBack,
    required this.onFavorite,
    required this.onCart,
  });

  @override
  Widget build(BuildContext context) {
    return SizedBox(
      height: 390,
      child: Stack(
        children: [
          Positioned.fill(
            child: NetworkOrAssetImage(
              imageUrl: cocktail.imageUrl,
              asset: cocktail.imageAsset,
              fit: BoxFit.cover,
            ),
          ),
          Positioned.fill(
            child: DecoratedBox(
              decoration: BoxDecoration(
                gradient: LinearGradient(
                  colors: [
                    Colors.black.withValues(alpha: 0.18),
                    Colors.transparent,
                    Colors.black.withValues(alpha: 0.12),
                  ],
                  begin: Alignment.topCenter,
                  end: Alignment.bottomCenter,
                ),
              ),
            ),
          ),
          Positioned(
            left: 0,
            right: 0,
            bottom: -1,
            child: ClipPath(
              clipper: DetailHeroWaveClipper(),
              child: Container(height: 66, color: EbtlColors.cream),
            ),
          ),
          Positioned(
            left: 22,
            right: 22,
            top: MediaQuery.of(context).padding.top + 10,
            child: Row(
              children: [
                CircleIconButton(icon: Icons.arrow_back, onTap: onBack),
                const Spacer(),
                CircleIconButton(
                  icon: isFavorite ? Icons.favorite : Icons.favorite_border,
                  iconColor: isFavorite ? EbtlColors.coral : Colors.black,
                  onTap: onFavorite,
                ),
                const SizedBox(width: 12),
                Stack(
                  clipBehavior: Clip.none,
                  children: [
                    CircleIconButton(
                      icon: Icons.shopping_cart_outlined,
                      onTap: onCart,
                    ),
                    if (cartCount > 0)
                      Positioned(
                        right: -2,
                        top: -4,
                        child: Container(
                          padding: const EdgeInsets.all(6),
                          decoration: const BoxDecoration(
                            color: EbtlColors.coral,
                            shape: BoxShape.circle,
                          ),
                          child: Text(
                            cartCount > 99 ? '99+' : cartCount.toString(),
                            style: const TextStyle(
                              color: Colors.white,
                              fontSize: 11,
                              fontWeight: FontWeight.w800,
                            ),
                          ),
                        ),
                      ),
                  ],
                ),
              ],
            ),
          ),
          if (cocktail.tagDetails.isNotEmpty)
            Positioned(
              left: 22,
              right: 22,
              bottom: 74,
              child: Wrap(
                spacing: 8,
                runSpacing: 8,
                children: cocktail.tagDetails
                    .map((tag) => ProductTagBadge(tag: tag))
                    .toList(),
              ),
            ),
        ],
      ),
    );
  }
}

class CocktailDetailContent extends StatelessWidget {
  final CocktailDetailResponse response;
  final String? locationId;
  final String? locationName;
  final Set<String> selectedRemovedRecipeItemIds;
  final Map<String, SelectedAddition> selectedAdditionsByVariantId;
  final ValueChanged<RemovableIngredient> onRemovedIngredientToggle;
  final ValueChanged<CocktailAdditionOption> onAdditionToggle;
  final ValueChanged<String> onRelatedTap;

  const CocktailDetailContent({
    super.key,
    required this.response,
    required this.locationId,
    required this.locationName,
    required this.selectedRemovedRecipeItemIds,
    required this.selectedAdditionsByVariantId,
    required this.onRemovedIngredientToggle,
    required this.onAdditionToggle,
    required this.onRelatedTap,
  });

  @override
  Widget build(BuildContext context) {
    final cocktail = response.cocktail;
    final showBottleCard = cocktail.selectedLiquor != null;
    final showRelated = response.relatedCocktails.isNotEmpty;

    return Padding(
      padding: const EdgeInsets.fromLTRB(22, 0, 22, 0),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            cocktail.name,
            style: GoogleFonts.playfairDisplay(
              fontSize: 42,
              height: 1.02,
              fontWeight: FontWeight.w800,
              color: EbtlColors.navy,
            ),
          ),
          if (cocktail.cleanShortDescription.isNotEmpty) ...[
            const SizedBox(height: 8),
            Text(
              cocktail.cleanShortDescription,
              style: GoogleFonts.manrope(
                fontSize: 17,
                height: 1.35,
                fontWeight: FontWeight.w600,
                color: EbtlColors.ink,
              ),
            ),
          ],
          const SizedBox(height: 18),
          Column(
            children: [
              if (showBottleCard) ...[
                CocktailBottleContextCard(cocktail: cocktail),
                const SizedBox(height: 12),
              ],
              CocktailAvailabilityCard(
                cocktail: cocktail,
                locationId: locationId,
                locationName: locationName,
              ),
            ],
          ),

          // Description first.
          if (cocktail.cleanDescription.isNotEmpty) ...[
            const SizedBox(height: 16),
            CocktailVibeCard(cocktail: cocktail),
          ],

          // Then "What's in Your Cocktail" / "How to Make It".
          const SizedBox(height: 16),
          LayoutBuilder(
            builder: (context, constraints) {
              final useColumn = constraints.maxWidth < 380;

              final ingredientsCard = CocktailIngredientsCard(
                ingredients: cocktail.includedIngredients,
              );

              final howToCard = CocktailHowToCard(steps: cocktail.howToMake);

              if (useColumn) {
                return Column(
                  children: [
                    ingredientsCard,
                    const SizedBox(height: 12),
                    howToCard,
                  ],
                );
              }

              return Row(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Expanded(child: ingredientsCard),
                  const SizedBox(width: 12),
                  Expanded(child: howToCard),
                ],
              );
            },
          ),

          // Customization after description and ingredients.
          if (cocktail.customization.shouldShow) ...[
            const SizedBox(height: 20),
            CocktailCustomizationSection(
              customization: cocktail.customization,
              selectedRemovedRecipeItemIds: selectedRemovedRecipeItemIds,
              selectedAdditionsByVariantId: selectedAdditionsByVariantId,
              onRemovedIngredientToggle: onRemovedIngredientToggle,
              onAdditionToggle: onAdditionToggle,
            ),
          ],

          if (showRelated) ...[
            const SizedBox(height: 22),
            RelatedCocktailsSection(
              title: cocktail.copy.relatedTitle,
              relatedCocktails: response.relatedCocktails,
              onTap: onRelatedTap,
            ),
          ],
        ],
      ),
    );
  }
}

class CocktailBottleContextCard extends StatelessWidget {
  final CocktailDetail cocktail;

  const CocktailBottleContextCard({super.key, required this.cocktail});

  @override
  Widget build(BuildContext context) {
    final liquor = cocktail.selectedLiquor!;
    final instruction = liquor.displayInstruction?.trim().isNotEmpty == true
        ? liquor.displayInstruction!.trim()
        : cocktail.copy.bottleNote;

    return DetailCard(
      child: Row(
        children: [
          BottleImage.raw(
            name: liquor.name,
            imageUrl: liquor.imageUrl,
            size: 72,
          ),
          const SizedBox(width: 14),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  cocktail.copy.bringYourBottleTitle,
                  style: GoogleFonts.manrope(
                    fontSize: 16,
                    fontWeight: FontWeight.w900,
                    color: EbtlColors.navy,
                  ),
                ),
                const SizedBox(height: 5),
                Text(
                  liquor.name,
                  style: GoogleFonts.manrope(
                    fontSize: 18,
                    fontWeight: FontWeight.w900,
                    color: EbtlColors.navy,
                  ),
                ),
                const SizedBox(height: 5),
                Text(
                  instruction,
                  style: GoogleFonts.manrope(
                    fontSize: 13,
                    height: 1.25,
                    fontWeight: FontWeight.w600,
                    color: EbtlColors.ink,
                  ),
                ),
                const SizedBox(height: 6),
                Row(
                  children: [
                    const Icon(
                      Icons.info_outline,
                      size: 16,
                      color: EbtlColors.muted,
                    ),
                    const SizedBox(width: 5),
                    Expanded(
                      child: Text(
                        cocktail.copy.bottleNote,
                        style: GoogleFonts.manrope(
                          fontSize: 12,
                          fontWeight: FontWeight.w700,
                          color: EbtlColors.muted,
                        ),
                      ),
                    ),
                  ],
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}

class CocktailAvailabilityCard extends StatelessWidget {
  final CocktailDetail cocktail;
  final String? locationId;
  final String? locationName;

  const CocktailAvailabilityCard({
    super.key,
    required this.cocktail,
    required this.locationId,
    required this.locationName,
  });

  @override
  Widget build(BuildContext context) {
    final hasLocation = locationId != null && locationId!.trim().isNotEmpty;
    final isOrderable = cocktail.availability.isOrderable && hasLocation;
    final isUnavailableWithLocation = hasLocation && !isOrderable;

    final title = !hasLocation
        ? 'Choose a beach cart'
        : isOrderable
        ? 'Available now at'
        : 'Availability update';

    final subtitle = !hasLocation
        ? 'Choose a beach cart to check availability.'
        : isOrderable
        ? (locationName ?? 'your selected beach cart')
        : cocktail.availabilityMessage;

    return DetailCard(
      backgroundColor: EbtlColors.seafoam.withValues(alpha: 0.36),
      child: Row(
        children: [
          Container(
            width: 58,
            height: 58,
            decoration: BoxDecoration(
              color: EbtlColors.white.withValues(alpha: 0.66),
              borderRadius: BorderRadius.circular(18),
            ),
            child: Icon(
              isOrderable ? Icons.storefront_outlined : Icons.info_outline,
              color: EbtlColors.teal,
              size: 31,
            ),
          ),
          const SizedBox(width: 14),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  title,
                  style: GoogleFonts.manrope(
                    fontSize: 13,
                    fontWeight: FontWeight.w700,
                    color: EbtlColors.ink,
                  ),
                ),
                const SizedBox(height: 5),
                Text(
                  subtitle,
                  maxLines: isUnavailableWithLocation ? 4 : 2,
                  overflow: TextOverflow.ellipsis,
                  style: GoogleFonts.manrope(
                    fontSize: isUnavailableWithLocation ? 13 : 16,
                    height: isUnavailableWithLocation ? 1.3 : 1.25,
                    fontWeight: FontWeight.w900,
                    color: EbtlColors.navy,
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

class CocktailCustomizationSection extends StatelessWidget {
  final CocktailCustomizationOptions customization;
  final Set<String> selectedRemovedRecipeItemIds;
  final Map<String, SelectedAddition> selectedAdditionsByVariantId;
  final ValueChanged<RemovableIngredient> onRemovedIngredientToggle;
  final ValueChanged<CocktailAdditionOption> onAdditionToggle;

  const CocktailCustomizationSection({
    super.key,
    required this.customization,
    required this.selectedRemovedRecipeItemIds,
    required this.selectedAdditionsByVariantId,
    required this.onRemovedIngredientToggle,
    required this.onAdditionToggle,
  });

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(
          'Customize your cocktail',
          style: GoogleFonts.manrope(
            fontSize: 26,
            height: 1.08,
            fontWeight: FontWeight.w900,
            color: EbtlColors.navy,
          ),
        ),
        const SizedBox(height: 7),
        Text(
          'Remove anything you don’t want. Add extras if you’d like.',
          style: GoogleFonts.manrope(
            fontSize: 14.5,
            height: 1.34,
            fontWeight: FontWeight.w600,
            color: EbtlColors.muted,
          ),
        ),
        if (customization.removableIngredients.isNotEmpty) ...[
          const SizedBox(height: 16),
          CustomizationPanel(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Row(
                  children: [
                    Expanded(
                      child: Text(
                        'Remove ingredients',
                        style: GoogleFonts.manrope(
                          fontSize: 16,
                          fontWeight: FontWeight.w900,
                          color: EbtlColors.ink,
                        ),
                      ),
                    ),
                    Text(
                      'No charge',
                      style: GoogleFonts.manrope(
                        fontSize: 13,
                        fontWeight: FontWeight.w800,
                        color: EbtlColors.teal,
                      ),
                    ),
                  ],
                ),
                const SizedBox(height: 14),
                Wrap(
                  spacing: 10,
                  runSpacing: 10,
                  children: customization.removableIngredients.map((
                    ingredient,
                  ) {
                    return RemovableIngredientChip(
                      ingredient: ingredient,
                      isSelected: selectedRemovedRecipeItemIds.contains(
                        ingredient.recipeItemId,
                      ),
                      onTap: () => onRemovedIngredientToggle(ingredient),
                    );
                  }).toList(),
                ),
              ],
            ),
          ),
        ],
        if (customization.additions.isNotEmpty) ...[
          const SizedBox(height: 16),
          CustomizationPanel(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Row(
                  children: [
                    Container(
                      width: 28,
                      height: 28,
                      decoration: BoxDecoration(
                        shape: BoxShape.circle,
                        border: Border.all(color: EbtlColors.teal, width: 1.5),
                      ),
                      child: const Icon(
                        Icons.add,
                        size: 20,
                        color: EbtlColors.teal,
                      ),
                    ),
                    const SizedBox(width: 12),
                    Text(
                      'Add extras',
                      style: GoogleFonts.manrope(
                        fontSize: 16,
                        fontWeight: FontWeight.w900,
                        color: EbtlColors.ink,
                      ),
                    ),
                  ],
                ),
                const SizedBox(height: 16),
                Container(
                  decoration: BoxDecoration(
                    color: EbtlColors.white.withValues(alpha: 0.72),
                    borderRadius: BorderRadius.circular(18),
                    border: Border.all(color: EbtlColors.border),
                  ),
                  child: Column(
                    children: [
                      for (
                        var i = 0;
                        i < customization.additions.length;
                        i++
                      ) ...[
                        CocktailAdditionRow(
                          addition: customization.additions[i],
                          isSelected: selectedAdditionsByVariantId.containsKey(
                            customization.additions[i].variantId,
                          ),
                          onTap: () =>
                              onAdditionToggle(customization.additions[i]),
                        ),
                        if (i != customization.additions.length - 1)
                          const Divider(
                            height: 1,
                            thickness: 1,
                            color: EbtlColors.border,
                          ),
                      ],
                    ],
                  ),
                ),
              ],
            ),
          ),
        ],
      ],
    );
  }
}

class CustomizationPanel extends StatelessWidget {
  final Widget child;

  const CustomizationPanel({super.key, required this.child});

  @override
  Widget build(BuildContext context) {
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: EbtlColors.white.withValues(alpha: 0.9),
        borderRadius: BorderRadius.circular(20),
        border: Border.all(color: EbtlColors.border),
        boxShadow: [
          BoxShadow(
            color: Colors.black.withValues(alpha: 0.035),
            blurRadius: 18,
            offset: const Offset(0, 8),
          ),
        ],
      ),
      child: child,
    );
  }
}

class RemovableIngredientChip extends StatelessWidget {
  final RemovableIngredient ingredient;
  final bool isSelected;
  final VoidCallback onTap;

  const RemovableIngredientChip({
    super.key,
    required this.ingredient,
    required this.isSelected,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    final textColor = isSelected ? EbtlColors.ink : EbtlColors.ink;
    final borderColor = isSelected
        ? EbtlColors.coral.withValues(alpha: 0.76)
        : EbtlColors.border;
    final backgroundColor = isSelected
        ? EbtlColors.blush.withValues(alpha: 0.2)
        : EbtlColors.white.withValues(alpha: 0.78);

    return ConstrainedBox(
      constraints: const BoxConstraints(minHeight: 50, minWidth: 132),
      child: Material(
        color: Colors.transparent,
        child: InkWell(
          onTap: onTap,
          borderRadius: BorderRadius.circular(16),
          child: Ink(
            padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
            decoration: BoxDecoration(
              color: backgroundColor,
              borderRadius: BorderRadius.circular(16),
              border: Border.all(color: borderColor),
            ),
            child: Row(
              mainAxisSize: MainAxisSize.min,
              children: [
                Flexible(
                  child: Text(
                    ingredient.name,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: GoogleFonts.manrope(
                      fontSize: 16,
                      height: 1.1,
                      fontWeight: FontWeight.w700,
                      color: textColor,
                    ),
                  ),
                ),
                if (isSelected) ...[
                  const SizedBox(width: 12),
                  Container(
                    width: 24,
                    height: 24,
                    decoration: BoxDecoration(
                      shape: BoxShape.circle,
                      border: Border.all(color: EbtlColors.coral, width: 1.6),
                    ),
                    child: const Icon(
                      Icons.remove,
                      color: EbtlColors.coral,
                      size: 17,
                    ),
                  ),
                ],
              ],
            ),
          ),
        ),
      ),
    );
  }
}

class CocktailAdditionRow extends StatelessWidget {
  final CocktailAdditionOption addition;
  final bool isSelected;
  final VoidCallback onTap;

  const CocktailAdditionRow({
    super.key,
    required this.addition,
    required this.isSelected,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    final unavailableReason = addition.unavailableReason?.trim();
    final isDisabled = !addition.isOrderable;

    return Opacity(
      opacity: isDisabled ? 0.52 : 1,
      child: Material(
        color: Colors.transparent,
        child: InkWell(
          onTap: isDisabled ? null : onTap,
          child: Padding(
            padding: const EdgeInsets.fromLTRB(14, 12, 14, 12),
            child: Row(
              children: [
                AdditionIcon(addition: addition),
                const SizedBox(width: 14),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        addition.name,
                        maxLines: 2,
                        overflow: TextOverflow.ellipsis,
                        style: GoogleFonts.manrope(
                          fontSize: 16,
                          height: 1.15,
                          fontWeight: FontWeight.w700,
                          color: EbtlColors.ink,
                        ),
                      ),
                      const SizedBox(height: 4),
                      Text(
                        isDisabled && unavailableReason != null
                            ? unavailableReason
                            : addition.priceLabel,
                        maxLines: 2,
                        overflow: TextOverflow.ellipsis,
                        style: GoogleFonts.manrope(
                          fontSize: 14,
                          height: 1.2,
                          fontWeight: FontWeight.w900,
                          color: isDisabled
                              ? EbtlColors.muted
                              : EbtlColors.teal,
                        ),
                      ),
                    ],
                  ),
                ),
                const SizedBox(width: 12),
                AdditionSelectPill(
                  isSelected: isSelected,
                  isDisabled: isDisabled,
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}

class AdditionIcon extends StatelessWidget {
  final CocktailAdditionOption addition;

  const AdditionIcon({super.key, required this.addition});

  @override
  Widget build(BuildContext context) {
    final iconKey = fallbackAdditionIconKey(addition.name);

    return Container(
      width: 52,
      height: 52,
      decoration: const BoxDecoration(
        color: EbtlColors.seafoam,
        shape: BoxShape.circle,
      ),
      clipBehavior: Clip.antiAlias,
      child: addition.imageUrl?.trim().isNotEmpty == true
          ? NetworkOrAssetImage(
              imageUrl: addition.imageUrl,
              asset: 'assets/images/cocktail_placeholder.jpg',
              fit: BoxFit.cover,
              fallback: Center(
                child: IngredientSvgIcon(iconKey: iconKey, size: 28),
              ),
            )
          : Center(child: IngredientSvgIcon(iconKey: iconKey, size: 28)),
    );
  }
}

class AdditionSelectPill extends StatelessWidget {
  final bool isSelected;
  final bool isDisabled;

  const AdditionSelectPill({
    super.key,
    required this.isSelected,
    required this.isDisabled,
  });

  @override
  Widget build(BuildContext context) {
    final color = isDisabled ? EbtlColors.muted : EbtlColors.teal;

    return Container(
      height: 42,
      padding: const EdgeInsets.symmetric(horizontal: 14),
      decoration: BoxDecoration(
        color: isSelected
            ? EbtlColors.seafoam.withValues(alpha: 0.55)
            : Colors.transparent,
        borderRadius: BorderRadius.circular(999),
        border: Border.all(color: color.withValues(alpha: 0.9)),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(isSelected ? Icons.check : Icons.add, color: color, size: 20),
          const SizedBox(width: 8),
          Text(
            isSelected ? 'Added' : 'Add',
            style: GoogleFonts.manrope(
              fontSize: 14,
              fontWeight: FontWeight.w800,
              color: color,
            ),
          ),
        ],
      ),
    );
  }
}

String fallbackAdditionIconKey(String name) {
  final lower = name.toLowerCase();
  if (lower.contains('soda')) return 'soda';
  if (lower.contains('tonic')) return 'tonic';
  if (lower.contains('mint')) return 'mint';
  if (lower.contains('lime')) return 'lime';
  if (lower.contains('lemon')) return 'lemon';
  if (lower.contains('orange') || lower.contains('citrus')) return 'orange';
  if (lower.contains('strawberry')) return 'strawberry';
  if (lower.contains('cherry')) return 'cherry';
  if (lower.contains('syrup')) return 'syrup';
  if (lower.contains('grenadine')) return 'grenadine';
  if (lower.contains('salt')) return 'salt';
  if (lower.contains('coconut')) return 'coconut';
  return 'generic';
}

class CocktailVibeCard extends StatelessWidget {
  final CocktailDetail cocktail;

  const CocktailVibeCard({super.key, required this.cocktail});

  @override
  Widget build(BuildContext context) {
    return DetailCard(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text('The vibe', style: detailSectionTitleStyle()),
          const SizedBox(height: 8),
          MarkdownBody(
            data: cocktail.cleanDescription,
            styleSheet: MarkdownStyleSheet(
              p: GoogleFonts.manrope(
                fontSize: 15,
                height: 1.42,
                fontWeight: FontWeight.w600,
                color: EbtlColors.ink,
              ),
              strong: GoogleFonts.manrope(
                fontWeight: FontWeight.w900,
                color: EbtlColors.navy,
              ),
              listBullet: GoogleFonts.manrope(
                fontSize: 15,
                color: EbtlColors.coral,
                fontWeight: FontWeight.w900,
              ),
            ),
          ),
        ],
      ),
    );
  }
}

class CocktailIngredientsCard extends StatelessWidget {
  final List<CocktailIngredient> ingredients;

  const CocktailIngredientsCard({super.key, required this.ingredients});

  @override
  Widget build(BuildContext context) {
    return DetailCard(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text('What’s in Your Cocktail', style: detailSectionTitleStyle()),
          const SizedBox(height: 12),
          if (ingredients.isEmpty)
            Text(
              'Ingredients will appear here soon.',
              style: GoogleFonts.manrope(
                fontSize: 13,
                fontWeight: FontWeight.w600,
                color: EbtlColors.muted,
              ),
            )
          else
            ...ingredients.map(
              (ingredient) => CocktailIngredientRow(ingredient: ingredient),
            ),
          const SizedBox(height: 4),
          Row(
            children: [
              const Icon(Icons.info_outline, size: 17, color: EbtlColors.muted),
              const SizedBox(width: 7),
              Expanded(
                child: Text(
                  'Liquor is not included.',
                  style: GoogleFonts.manrope(
                    fontSize: 12,
                    fontWeight: FontWeight.w800,
                    color: EbtlColors.muted,
                  ),
                ),
              ),
            ],
          ),
        ],
      ),
    );
  }
}

class CocktailIngredientRow extends StatelessWidget {
  final CocktailIngredient ingredient;

  const CocktailIngredientRow({super.key, required this.ingredient});

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 10),
      child: Row(
        children: [
          Container(
            width: 34,
            height: 34,
            decoration: BoxDecoration(
              color: EbtlColors.cream,
              borderRadius: BorderRadius.circular(12),
              border: Border.all(color: EbtlColors.border),
            ),
            alignment: Alignment.center,
            child: IngredientSvgIcon(iconKey: ingredient.iconKey, size: 20),
          ),
          const SizedBox(width: 10),
          Expanded(
            child: Text(
              ingredient.name,
              maxLines: 2,
              overflow: TextOverflow.ellipsis,
              style: GoogleFonts.manrope(
                fontSize: 14,
                height: 1.22,
                fontWeight: FontWeight.w700,
                color: EbtlColors.ink,
              ),
            ),
          ),
        ],
      ),
    );
  }
}

class CocktailHowToCard extends StatelessWidget {
  final List<CocktailHowToStep> steps;

  const CocktailHowToCard({super.key, required this.steps});

  @override
  Widget build(BuildContext context) {
    return DetailCard(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text('How to make it', style: detailSectionTitleStyle()),
          const SizedBox(height: 12),
          if (steps.isEmpty)
            Text(
              'Preparation steps will appear here soon.',
              style: GoogleFonts.manrope(
                fontSize: 13,
                fontWeight: FontWeight.w600,
                color: EbtlColors.muted,
              ),
            )
          else
            ...steps.map(
              (step) => Padding(
                padding: const EdgeInsets.only(bottom: 12),
                child: Row(
                  children: [
                    StepBubble(number: step.step),
                    const SizedBox(width: 11),
                    Expanded(
                      child: Text(
                        step.title,
                        style: GoogleFonts.manrope(
                          fontSize: 13,
                          height: 1.28,
                          fontWeight: FontWeight.w700,
                          color: EbtlColors.ink,
                        ),
                      ),
                    ),
                  ],
                ),
              ),
            ),
        ],
      ),
    );
  }
}

class RelatedCocktailsSection extends StatelessWidget {
  final String title;
  final List<RelatedCocktail> relatedCocktails;
  final ValueChanged<String> onTap;

  const RelatedCocktailsSection({
    super.key,
    required this.title,
    required this.relatedCocktails,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    return Column(
      children: [
        Row(
          children: [
            Expanded(child: Text(title, style: sectionTitleStyle())),
            Text(
              'View all',
              style: GoogleFonts.manrope(
                fontWeight: FontWeight.w800,
                color: EbtlColors.teal,
              ),
            ),
            const SizedBox(width: 5),
            const Icon(Icons.chevron_right, color: EbtlColors.teal),
          ],
        ),
        const SizedBox(height: 12),
        SizedBox(
          height: 112,
          child: ListView.separated(
            scrollDirection: Axis.horizontal,
            itemCount: relatedCocktails.length,
            separatorBuilder: (_, _) => const SizedBox(width: 12),
            itemBuilder: (context, index) {
              final cocktail = relatedCocktails[index];

              return RelatedCocktailCard(
                cocktail: cocktail,
                onTap: () => onTap(cocktail.slug),
              );
            },
          ),
        ),
      ],
    );
  }
}

class RelatedCocktailCard extends StatelessWidget {
  final RelatedCocktail cocktail;
  final VoidCallback onTap;

  const RelatedCocktailCard({
    super.key,
    required this.cocktail,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    return SizedBox(
      width: 210,
      child: Material(
        color: Colors.transparent,
        child: InkWell(
          onTap: onTap,
          borderRadius: BorderRadius.circular(18),
          child: Ink(
            decoration: BoxDecoration(
              color: EbtlColors.white,
              borderRadius: BorderRadius.circular(18),
              border: Border.all(color: EbtlColors.border),
            ),
            child: Row(
              children: [
                ClipRRect(
                  borderRadius: const BorderRadius.horizontal(
                    left: Radius.circular(18),
                  ),
                  child: SizedBox(
                    width: 86,
                    height: double.infinity,
                    child: NetworkOrAssetImage(
                      imageUrl: cocktail.imageUrl,
                      asset: cocktail.imageAsset,
                    ),
                  ),
                ),
                Expanded(
                  child: Padding(
                    padding: const EdgeInsets.fromLTRB(10, 9, 8, 9),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          cocktail.name,
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                          style: GoogleFonts.manrope(
                            fontSize: 11,
                            fontWeight: FontWeight.w900,
                            color: EbtlColors.navy,
                          ),
                        ),
                        const SizedBox(height: 5),
                        if ((cocktail.shortDescription ?? '').trim().isNotEmpty)
                          Text(
                            cocktail.shortDescription!,
                            maxLines: 2,
                            overflow: TextOverflow.ellipsis,
                            style: GoogleFonts.manrope(
                              fontSize: 9,
                              height: 1.28,
                              fontWeight: FontWeight.w600,
                              color: EbtlColors.ink,
                            ),
                          ),
                        const Spacer(),
                        Text(
                          cocktail.priceLabel,
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                          style: GoogleFonts.manrope(
                            fontSize: 11,
                            fontWeight: FontWeight.w900,
                            color: EbtlColors.coral,
                          ),
                        ),
                      ],
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

class CocktailDetailAddBar extends StatelessWidget {
  final CocktailDetail cocktail;
  final int selectedQuantity;
  final double selectedAdditionsUnitTotal;
  final bool hasLocation;
  final bool isAdding;
  final VoidCallback onIncrement;
  final VoidCallback onDecrement;
  final VoidCallback? onAdd;

  const CocktailDetailAddBar({
    super.key,
    required this.cocktail,
    required this.selectedQuantity,
    required this.selectedAdditionsUnitTotal,
    required this.hasLocation,
    required this.isAdding,
    required this.onIncrement,
    required this.onDecrement,
    required this.onAdd,
  });

  @override
  Widget build(BuildContext context) {
    final variant = cocktail.variant;
    final enabled = onAdd != null && !isAdding;

    final price = variant == null
        ? null
        : (variant.priceIncVat + selectedAdditionsUnitTotal) * selectedQuantity;
    final currency = variant?.currency ?? 'EGP';

    final disabledReason = !hasLocation
        ? 'Choose a beach cart to check availability.'
        : cocktail.availabilityMessage;

    final label = isAdding
        ? 'Adding...'
        : enabled && price != null
        ? 'Add · ${formatMoney(price, currency)}'
        : !hasLocation
        ? 'Choose Beach Cart First'
        : 'Unavailable';

    return Container(
      padding: EdgeInsets.fromLTRB(
        22,
        12,
        22,
        12 + MediaQuery.of(context).padding.bottom,
      ),
      decoration: BoxDecoration(
        color: Colors.white.withValues(alpha: 0.98),
        border: const Border(top: BorderSide(color: EbtlColors.border)),
        boxShadow: [
          BoxShadow(
            color: Colors.black.withValues(alpha: 0.08),
            blurRadius: 20,
            offset: const Offset(0, -8),
          ),
        ],
      ),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          if (!enabled && !isAdding) ...[
            Align(
              alignment: Alignment.centerLeft,
              child: Text(
                disabledReason,
                maxLines: 2,
                overflow: TextOverflow.ellipsis,
                style: GoogleFonts.manrope(
                  fontSize: 12,
                  fontWeight: FontWeight.w700,
                  color: EbtlColors.muted,
                ),
              ),
            ),
            const SizedBox(height: 9),
          ],
          Row(
            children: [
              QuantityStepper(
                quantity: selectedQuantity,
                enabled: variant != null && enabled,
                onIncrement: onIncrement,
                onDecrement: onDecrement,
              ),
              const SizedBox(width: 14),
              Expanded(
                child: SizedBox(
                  height: 58,
                  child: ElevatedButton.icon(
                    onPressed: enabled ? onAdd : null,
                    icon: isAdding
                        ? const SizedBox(
                            width: 18,
                            height: 18,
                            child: CircularProgressIndicator(
                              strokeWidth: 2,
                              color: Colors.white,
                            ),
                          )
                        : const Icon(Icons.shopping_bag_outlined),
                    label: Text(label),
                    style: ebtlCoralButtonStyle(
                      withDisabledColors: true,
                      textStyle: GoogleFonts.manrope(
                        fontSize: 16,
                        fontWeight: FontWeight.w900,
                      ),
                    ),
                  ),
                ),
              ),
            ],
          ),
        ],
      ),
    );
  }
}

class QuantityStepper extends StatelessWidget {
  final int quantity;
  final bool enabled;
  final VoidCallback onIncrement;
  final VoidCallback onDecrement;

  const QuantityStepper({
    super.key,
    required this.quantity,
    required this.enabled,
    required this.onIncrement,
    required this.onDecrement,
  });

  @override
  Widget build(BuildContext context) {
    return Container(
      height: 58,
      decoration: BoxDecoration(
        color: EbtlColors.white,
        borderRadius: BorderRadius.circular(18),
        border: Border.all(color: EbtlColors.border),
      ),
      child: Row(
        children: [
          SizedBox(
            width: 50,
            child: IconButton(
              onPressed: enabled && quantity > 1 ? onDecrement : null,
              icon: const Icon(Icons.remove),
              color: EbtlColors.navy,
            ),
          ),
          Container(
            width: 48,
            alignment: Alignment.center,
            decoration: const BoxDecoration(
              border: Border.symmetric(
                vertical: BorderSide(color: EbtlColors.border),
              ),
            ),
            child: Text(
              quantity.toString(),
              style: GoogleFonts.manrope(
                fontSize: 18,
                fontWeight: FontWeight.w900,
                color: enabled ? EbtlColors.navy : EbtlColors.muted,
              ),
            ),
          ),
          SizedBox(
            width: 50,
            child: IconButton(
              onPressed: enabled ? onIncrement : null,
              icon: const Icon(Icons.add),
              color: EbtlColors.navy,
            ),
          ),
        ],
      ),
    );
  }
}

class CocktailDetailErrorState extends StatelessWidget {
  final String message;
  final VoidCallback onRetry;

  const CocktailDetailErrorState({
    super.key,
    required this.message,
    required this.onRetry,
  });

  @override
  Widget build(BuildContext context) {
    return SafeArea(
      child: Padding(
        padding: const EdgeInsets.all(22),
        child: Center(
          child: DetailCard(
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                Text(
                  'Could not load this cocktail.',
                  textAlign: TextAlign.center,
                  style: GoogleFonts.playfairDisplay(
                    fontSize: 30,
                    fontWeight: FontWeight.w800,
                    color: EbtlColors.navy,
                  ),
                ),
                const SizedBox(height: 12),
                Text(
                  message,
                  textAlign: TextAlign.center,
                  style: GoogleFonts.manrope(
                    fontSize: 13,
                    height: 1.35,
                    fontWeight: FontWeight.w600,
                    color: EbtlColors.ink,
                  ),
                ),
                const SizedBox(height: 18),
                SizedBox(
                  height: 52,
                  width: double.infinity,
                  child: ElevatedButton(
                    onPressed: onRetry,
                    style: ebtlCoralButtonStyle(),
                    child: Text(
                      'Try Again',
                      style: GoogleFonts.manrope(fontWeight: FontWeight.w900),
                    ),
                  ),
                ),
                const SizedBox(height: 10),
                TextButton(
                  onPressed: () => Navigator.of(context).pop(),
                  child: Text(
                    'Go back',
                    style: GoogleFonts.manrope(
                      fontWeight: FontWeight.w900,
                      color: EbtlColors.teal,
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

class DetailHeroWaveClipper extends CustomClipper<Path> {
  @override
  Path getClip(Size size) {
    final path = Path();

    path.moveTo(0, size.height * 0.42);
    path.quadraticBezierTo(
      size.width * 0.28,
      size.height * 0.10,
      size.width * 0.58,
      size.height * 0.38,
    );
    path.quadraticBezierTo(
      size.width * 0.82,
      size.height * 0.60,
      size.width,
      size.height * 0.30,
    );
    path.lineTo(size.width, size.height);
    path.lineTo(0, size.height);
    path.close();

    return path;
  }

  @override
  bool shouldReclip(covariant CustomClipper<Path> oldClipper) => false;
}
