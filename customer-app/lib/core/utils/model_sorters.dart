import '../../models/common_models.dart';

/// Returns a copy of [items] sorted by [order] ascending, then by [name]
/// case-insensitively. Shared by the app's display-order sorters.
List<T> sortByOrderThenName<T>(
  List<T> items,
  int Function(T) order,
  String Function(T) name,
) {
  final sorted = [...items];

  sorted.sort((a, b) {
    final orderCompare = order(a).compareTo(order(b));
    if (orderCompare != 0) return orderCompare;

    return name(a).toLowerCase().compareTo(name(b).toLowerCase());
  });

  return sorted;
}

List<ProductTag> sortProductTags(List<ProductTag> productTags) {
  return sortByOrderThenName(productTags, (t) => t.displayOrder, (t) => t.name);
}

/// Hero banners sort on `display_order` alone — the tie-break is the id rather
/// than a name, since a slide need not carry any text at all.
List<HomeHeroBanner> sortHeroBanners(List<HomeHeroBanner> banners) {
  return sortByOrderThenName(banners, (b) => b.displayOrder, (b) => b.id);
}

List<LiquorType> sortLiquorTypes(List<LiquorType> liquorTypes) {
  return sortByOrderThenName(liquorTypes, (t) => t.displayOrder, (t) => t.name);
}

List<LiquorType> sortLiquorTypesWithSelectedFirst(
  List<LiquorType> liquorTypes,
  Set<String> selectedLiquorTypeIds,
) {
  final sorted = sortLiquorTypes(liquorTypes);

  return [
    ...sorted.where((type) => selectedLiquorTypeIds.contains(type.id)),
    ...sorted.where((type) => !selectedLiquorTypeIds.contains(type.id)),
  ];
}
