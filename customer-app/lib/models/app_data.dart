import '../core/utils/json_helpers.dart';
import '../core/utils/model_sorters.dart';
import 'cocktail_models.dart';
import 'common_models.dart';
import 'finder_models.dart';
import 'golden_hour_models.dart';
import 'spotlight_models.dart';

class AppData {
  final HeroContent hero;

  /// CMS-driven slides for the Home hero carousel, in display order. Empty
  /// means marketing has none live and the carousel shows its bundled slides.
  final List<HomeHeroBanner> heroBanners;

  /// CMS-driven banners for Home's "The Spotlight" rail, in display order. Empty
  /// means marketing has none live and Home renders no rail — there is no
  /// fallback, because a Spotlight banner's whole purpose is a curated product
  /// set only the dashboard can define.
  final List<SpotlightBanner> spotlightBanners;

  /// How long each hero slide dwells before the carousel advances itself, set
  /// in the dashboard. Falls back to [HomeHeroBanner.defaultRotation].
  final Duration heroRotation;
  /// The launch modal for the hour it is now in Cairo, resolved by the
  /// backend. Null when no mode is live, or when the customer has no beach cart
  /// chosen yet — [RootShell] only opens it in that second case.
  final GoldenHourModal? goldenHour;

  final List<ServiceLocation> serviceAreas;
  final List<Cocktail> featuredCocktails;
  final List<Category> categories;
  final List<LiquorType> liquorTypes;
  final FinderOptions finderOptions;
  final CartSummary? cartSummary;
  final String? selectedLocationId;
  final String? selectedLocationName;

  const AppData({
    required this.hero,
    required this.heroBanners,
    required this.spotlightBanners,
    required this.heroRotation,
    required this.goldenHour,
    required this.serviceAreas,
    required this.featuredCocktails,
    required this.categories,
    required this.liquorTypes,
    required this.finderOptions,
    required this.cartSummary,
    required this.selectedLocationId,
    required this.selectedLocationName,
  });

  /// The same payload with a newer cart summary.
  ///
  /// Cart writes return the new summary, so the shell can swap it in rather
  /// than refetching `/home` — the rest of the payload (hero, catalog, finder
  /// options) cannot have changed as a result of a cart write.
  AppData withCartSummary(CartSummary? summary) {
    return AppData(
      hero: hero,
      heroBanners: heroBanners,
      spotlightBanners: spotlightBanners,
      heroRotation: heroRotation,
      goldenHour: goldenHour,
      serviceAreas: serviceAreas,
      featuredCocktails: featuredCocktails,
      categories: categories,
      liquorTypes: liquorTypes,
      finderOptions: finderOptions,
      cartSummary: summary,
      selectedLocationId: selectedLocationId,
      selectedLocationName: selectedLocationName,
    );
  }

  /// Builds app data from the `/home` payload.
  ///
  /// Supply either [optionsJson] (a fresh cocktail-finder options response) or
  /// [reusedOptions] (the options already held from an earlier load). The
  /// options payload is static for the lifetime of a session, so refreshes that
  /// only need live data can carry it over and skip a request.
  factory AppData.fromApi({
    required Map<String, dynamic> homeJson,
    Map<String, dynamic>? optionsJson,
    FinderOptions? reusedOptions,
    required String? selectedLocationId,
    required String? selectedLocationName,
  }) {
    assert(
      optionsJson != null || reusedOptions != null,
      'AppData.fromApi needs either optionsJson or reusedOptions.',
    );

    final homeLiquorTypes = sortLiquorTypes(
      readMapList(homeJson['liquorTypes']).map(LiquorType.fromJson).toList(),
    );

    final options =
        reusedOptions ?? FinderOptions.fromJson(optionsJson ?? const {});

    final effectiveLiquorTypes = options.liquorTypes.isNotEmpty
        ? options.liquorTypes
        : homeLiquorTypes;

    return AppData(
      hero: HeroContent.fromJson(asMap(homeJson['hero'])),
      heroRotation: readHeroRotation(asMap(homeJson['heroCarousel'])),
      goldenHour: GoldenHourModal.fromJson(asMap(homeJson['goldenHour'])),
      heroBanners: sortHeroBanners(
        readMapList(homeJson['heroBanners'])
            .map(HomeHeroBanner.fromJson)
            .where((banner) => banner.isRenderable)
            .toList(),
      ),
      spotlightBanners: sortSpotlightBanners(
        readMapList(homeJson['spotlightBanners'])
            .map(SpotlightBanner.fromJson)
            .where((banner) => banner.isRenderable)
            .toList(),
      ),
      serviceAreas: readMapList(
        homeJson['serviceAreas'],
      ).map(ServiceLocation.fromJson).toList(),
      featuredCocktails: readMapList(
        homeJson['featuredCocktails'],
      ).map(Cocktail.fromCustomerJson).toList(),
      categories: readMapList(
        homeJson['categories'],
      ).map(Category.fromJson).toList(),
      liquorTypes: sortLiquorTypes(effectiveLiquorTypes),
      finderOptions: options,
      cartSummary: homeJson['cartSummary'] is Map<String, dynamic>
          ? CartSummary.fromJson(asMap(homeJson['cartSummary']))
          : null,
      selectedLocationId: selectedLocationId,
      selectedLocationName: selectedLocationName,
    );
  }
}
