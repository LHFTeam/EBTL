import '../core/utils/json_helpers.dart';
import '../core/utils/model_sorters.dart';
import 'cocktail_models.dart';
import 'common_models.dart';
import 'finder_models.dart';

class AppData {
  final HeroContent hero;
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
    required this.serviceAreas,
    required this.featuredCocktails,
    required this.categories,
    required this.liquorTypes,
    required this.finderOptions,
    required this.cartSummary,
    required this.selectedLocationId,
    required this.selectedLocationName,
  });

  factory AppData.fromApi({
    required Map<String, dynamic> homeJson,
    required Map<String, dynamic> optionsJson,
    required String? selectedLocationId,
    required String? selectedLocationName,
  }) {
    final homeLiquorTypes = sortLiquorTypes(
      readMapList(homeJson['liquorTypes']).map(LiquorType.fromJson).toList(),
    );

    final options = FinderOptions.fromJson(optionsJson);

    final effectiveLiquorTypes = options.liquorTypes.isNotEmpty
        ? options.liquorTypes
        : homeLiquorTypes;

    return AppData(
      hero: HeroContent.fromJson(asMap(homeJson['hero'])),
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
