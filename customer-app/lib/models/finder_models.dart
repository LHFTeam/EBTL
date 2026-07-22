import '../core/utils/json_helpers.dart';
import '../core/utils/model_sorters.dart';
import 'common_models.dart';

class FinderOptions {
  final List<LiquorType> liquorTypes;
  final List<Category> categories;
  final List<String> tags;
  final List<ProductTag> productTags;
  final List<SortOption> sortOptions;

  const FinderOptions({
    required this.liquorTypes,
    required this.categories,
    required this.tags,
    required this.productTags,
    required this.sortOptions,
  });

  factory FinderOptions.fromJson(Map<String, dynamic> json) {
    final sortOptions = readMapList(
      json['sortOptions'],
    ).map(SortOption.fromJson).toList();

    final liquorTypes = sortLiquorTypes(
      readMapList(json['liquorTypes']).map(LiquorType.fromJson).toList(),
    );

    final productTags = sortProductTags(
      readMapList(json['productTags']).map(ProductTag.fromJson).toList(),
    );

    return FinderOptions(
      liquorTypes: liquorTypes,
      categories: readMapList(
        json['categories'],
      ).map(Category.fromJson).toList(),
      tags: readStringList(json['tags']),
      productTags: productTags,
      sortOptions: sortOptions.isEmpty ? SortOption.defaults : sortOptions,
    );
  }
}

class SortOption {
  final String value;
  final String label;

  const SortOption({required this.value, required this.label});

  factory SortOption.fromJson(Map<String, dynamic> json) {
    return SortOption(
      value: readString(json['value'], fallback: 'featured'),
      label: readString(json['label'], fallback: 'Featured'),
    );
  }

  static const defaults = [
    SortOption(value: 'featured', label: 'Featured'),
    SortOption(value: 'price_asc', label: 'Price: Low to High'),
    SortOption(value: 'prep_time', label: 'Fastest to Prepare'),
  ];
}
