import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';

import '../../core/navigation/slide_up_route.dart';
import '../../core/theme/ebtl_colors.dart';
import '../../models/favorite_models.dart';
import '../../services/api_service.dart';
import '../../core/network/api_exception.dart';
import '../../shared/widgets/app_state_widgets.dart';
import '../../shared/widgets/detail_card.dart';
import '../../shared/widgets/ebtl_bottom_nav.dart';
import '../../shared/widgets/network_or_asset_image.dart';
import '../cocktail_detail/cocktail_detail_screen.dart';
import 'widgets/profile_widgets.dart';

class FavoriteCocktailsScreen extends StatefulWidget {
  final String? locationId;

  const FavoriteCocktailsScreen({super.key, required this.locationId});

  @override
  State<FavoriteCocktailsScreen> createState() =>
      _FavoriteCocktailsScreenState();
}

class _FavoriteCocktailsScreenState extends State<FavoriteCocktailsScreen> {
  late Future<FavoriteCocktailsResponse> favoritesFuture;
  final Set<String> mutatingIds = <String>{};
  List<FavoriteCocktail>? localFavorites;

  @override
  void initState() {
    super.initState();
    favoritesFuture = loadFavorites();
  }

  Future<FavoriteCocktailsResponse> loadFavorites() async {
    final response = await ApiService.fetchFavoriteCocktails(
      locationId: widget.locationId,
    );
    localFavorites = response.results;
    return response;
  }

  void reload() {
    setState(() {
      favoritesFuture = loadFavorites();
    });
  }

  Future<void> removeFavorite(FavoriteCocktail cocktail) async {
    if (mutatingIds.contains(cocktail.id)) return;

    final previous = localFavorites ?? <FavoriteCocktail>[];

    setState(() {
      mutatingIds.add(cocktail.id);
      localFavorites = previous
          .where((item) => item.id != cocktail.id)
          .toList();
    });

    try {
      await ApiService.removeFavoriteCocktail(productId: cocktail.id);

      if (!mounted) return;

      setState(() => mutatingIds.remove(cocktail.id));
    } catch (error) {
      if (!mounted) return;

      setState(() {
        mutatingIds.remove(cocktail.id);
        localFavorites = previous;
      });

      showAppSnackBar(context, 'Could not remove this favorite.');
    }
  }

  void openDetail(FavoriteCocktail cocktail) {
    if (cocktail.slug.trim().isEmpty) return;

    Navigator.of(context).push(
      slideUpModalRoute(
        CocktailDetailScreen(
          slug: cocktail.slug,
          locationId: widget.locationId,
          locationName: null,
          liquorTypeId: null,
          // Favorites is reached from Profile, so that is the tab to return to.
          selectedNavIndex: EbtlBottomNav.profileIndex,
          initialCartQuantity: 0,
          onCartChanged: ([_]) {},
          onBottomNavTap: (index) => Navigator.of(context).pop(),
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: EbtlColors.cream,
      body: SafeArea(
        child: FutureBuilder<FavoriteCocktailsResponse>(
          future: favoritesFuture,
          builder: (context, snapshot) {
            final items =
                localFavorites ??
                snapshot.data?.results ??
                <FavoriteCocktail>[];

            return CustomScrollView(
              slivers: [
                SliverToBoxAdapter(
                  child: ProfileSubScreenHeader(
                    title: 'Favorites',
                    onBack: () => Navigator.of(context).pop(),
                  ),
                ),
                if (snapshot.connectionState == ConnectionState.waiting &&
                    items.isEmpty)
                  const EbtlLoadingSliver(label: 'Loading favorites...')
                else if (snapshot.hasError && items.isEmpty)
                  SliverToBoxAdapter(
                    child: InlineErrorCard(
                      message: apiErrorMessage(snapshot.error!),
                      onRetry: reload,
                    ),
                  )
                else if (items.isEmpty)
                  const SliverToBoxAdapter(child: FavoriteCocktailsEmptyCard())
                else
                  SliverPadding(
                    padding: const EdgeInsets.fromLTRB(22, 8, 22, 22),
                    sliver: SliverGrid(
                      gridDelegate:
                          const SliverGridDelegateWithFixedCrossAxisCount(
                            crossAxisCount: 2,
                            mainAxisSpacing: 12,
                            crossAxisSpacing: 12,
                            childAspectRatio: 0.70,
                          ),
                      delegate: SliverChildBuilderDelegate((context, index) {
                        final cocktail = items[index];

                        return FavoriteCocktailCard(
                          cocktail: cocktail,
                          isMutating: mutatingIds.contains(cocktail.id),
                          onTap: () => openDetail(cocktail),
                          onRemove: () => removeFavorite(cocktail),
                        );
                      }, childCount: items.length),
                    ),
                  ),
              ],
            );
          },
        ),
      ),
    );
  }
}

class FavoriteCocktailCard extends StatelessWidget {
  final FavoriteCocktail cocktail;
  final bool isMutating;
  final VoidCallback onTap;
  final VoidCallback onRemove;

  const FavoriteCocktailCard({
    super.key,
    required this.cocktail,
    required this.isMutating,
    required this.onTap,
    required this.onRemove,
  });

  @override
  Widget build(BuildContext context) {
    return Material(
      color: Colors.transparent,
      child: InkWell(
        onTap: onTap,
        borderRadius: BorderRadius.circular(18),
        child: Ink(
          decoration: BoxDecoration(
            color: EbtlColors.white,
            borderRadius: BorderRadius.circular(18),
            border: Border.all(color: EbtlColors.border),
            boxShadow: [
              BoxShadow(
                color: Colors.black.withValues(alpha: 0.04),
                blurRadius: 16,
                offset: const Offset(0, 8),
              ),
            ],
          ),
          child: ClipRRect(
            borderRadius: BorderRadius.circular(18),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Expanded(
                  child: Stack(
                    children: [
                      Positioned.fill(
                        child: NetworkOrAssetImage(
                          imageUrl: cocktail.imageUrl,
                          asset: cocktail.imageAsset,
                        ),
                      ),
                      Positioned(
                        top: 8,
                        right: 8,
                        child: Material(
                          color: EbtlColors.white.withValues(alpha: 0.92),
                          shape: const CircleBorder(),
                          child: InkWell(
                            onTap: isMutating ? null : onRemove,
                            customBorder: const CircleBorder(),
                            child: SizedBox(
                              width: 38,
                              height: 38,
                              child: isMutating
                                  ? const Padding(
                                      padding: EdgeInsets.all(10),
                                      child: CircularProgressIndicator(
                                        color: EbtlColors.coral,
                                        strokeWidth: 2,
                                      ),
                                    )
                                  : const Icon(
                                      Icons.favorite,
                                      color: EbtlColors.coral,
                                      size: 22,
                                    ),
                            ),
                          ),
                        ),
                      ),
                    ],
                  ),
                ),
                Padding(
                  padding: const EdgeInsets.all(12),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        cocktail.name,
                        maxLines: 2,
                        overflow: TextOverflow.ellipsis,
                        style: GoogleFonts.manrope(
                          fontSize: 13,
                          height: 1.15,
                          fontWeight: FontWeight.w900,
                          color: EbtlColors.navy,
                        ),
                      ),
                      if ((cocktail.shortDescription ?? '')
                          .trim()
                          .isNotEmpty) ...[
                        const SizedBox(height: 6),
                        Text(
                          cocktail.shortDescription!.trim(),
                          maxLines: 2,
                          overflow: TextOverflow.ellipsis,
                          style: GoogleFonts.manrope(
                            fontSize: 10,
                            height: 1.25,
                            fontWeight: FontWeight.w600,
                            color: EbtlColors.ink,
                          ),
                        ),
                      ],
                    ],
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

class FavoriteCocktailsEmptyCard extends StatelessWidget {
  const FavoriteCocktailsEmptyCard({super.key});

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.all(22),
      child: DetailCard(
        child: Column(
          children: [
            Container(
              width: 72,
              height: 72,
              decoration: BoxDecoration(
                color: EbtlColors.blush.withValues(alpha: 0.54),
                shape: BoxShape.circle,
              ),
              child: const Icon(
                Icons.favorite_border,
                color: EbtlColors.coral,
                size: 34,
              ),
            ),
            const SizedBox(height: 16),
            Text(
              'No favorite cocktails yet.',
              textAlign: TextAlign.center,
              style: GoogleFonts.playfairDisplay(
                fontSize: 30,
                fontWeight: FontWeight.w800,
                color: EbtlColors.navy,
              ),
            ),
            const SizedBox(height: 8),
            Text(
              'Tap the heart on cocktails you love.',
              textAlign: TextAlign.center,
              style: GoogleFonts.manrope(
                fontSize: 14,
                height: 1.4,
                fontWeight: FontWeight.w600,
                color: EbtlColors.ink,
              ),
            ),
          ],
        ),
      ),
    );
  }
}
