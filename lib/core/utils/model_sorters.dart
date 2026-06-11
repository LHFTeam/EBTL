import '../../models/common_models.dart';

List<ProductTag> sortProductTags(List<ProductTag> productTags) {
  final sorted = [...productTags];

  sorted.sort((a, b) {
    final orderCompare = a.displayOrder.compareTo(b.displayOrder);
    if (orderCompare != 0) return orderCompare;

    return a.name.toLowerCase().compareTo(b.name.toLowerCase());
  });

  return sorted;
}

List<LiquorType> sortLiquorTypes(List<LiquorType> liquorTypes) {
  final sorted = [...liquorTypes];

  sorted.sort((a, b) {
    final orderCompare = a.displayOrder.compareTo(b.displayOrder);
    if (orderCompare != 0) return orderCompare;

    return a.name.toLowerCase().compareTo(b.name.toLowerCase());
  });

  return sorted;
}
