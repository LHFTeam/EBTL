import 'package:flutter_test/flutter_test.dart';

import 'package:ebtl_customer_app/core/utils/model_sorters.dart';
import 'package:ebtl_customer_app/models/common_models.dart';

void main() {
  test('selected liquor types come first while preserving preset order', () {
    const liquorTypes = [
      LiquorType(id: 'wine', name: 'Wine', imageUrl: null, displayOrder: 5),
      LiquorType(id: 'vodka', name: 'Vodka', imageUrl: null, displayOrder: 3),
      LiquorType(
        id: 'tequila',
        name: 'Tequila',
        imageUrl: null,
        displayOrder: 1,
      ),
      LiquorType(
        id: 'whiskey',
        name: 'Whiskey',
        imageUrl: null,
        displayOrder: 6,
      ),
      LiquorType(id: 'rum', name: 'Rum', imageUrl: null, displayOrder: 2),
      LiquorType(id: 'gin', name: 'Gin', imageUrl: null, displayOrder: 4),
    ];

    final sorted = sortLiquorTypesWithSelectedFirst(liquorTypes, {
      'vodka',
      'whiskey',
    });

    expect(sorted.map((type) => type.id), [
      'vodka',
      'whiskey',
      'tequila',
      'rum',
      'gin',
      'wine',
    ]);
  });
}
