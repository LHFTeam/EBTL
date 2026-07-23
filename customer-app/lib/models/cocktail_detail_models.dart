import '../core/constants/cocktail_assets.dart';
import '../core/utils/formatters.dart';
import '../core/utils/json_helpers.dart';
import '../core/utils/model_sorters.dart';
import 'common_models.dart';
import 'product_models.dart';

class CocktailDetailResponse {
  final CocktailDetail cocktail;
  final CartContext cartContext;
  final List<RelatedCocktail> relatedCocktails;

  const CocktailDetailResponse({
    required this.cocktail,
    required this.cartContext,
    required this.relatedCocktails,
  });

  factory CocktailDetailResponse.fromJson(Map<String, dynamic> json) {
    return CocktailDetailResponse(
      cocktail: CocktailDetail.fromJson(asMap(json['cocktail'])),
      cartContext: CartContext.fromJson(asMap(json['cartContext'])),
      relatedCocktails: readMapList(
        json['relatedCocktails'],
      ).map(RelatedCocktail.fromJson).toList(),
    );
  }
}

class CocktailDetail {
  final String id;
  final String slug;
  final String name;
  final String? shortDescription;
  final String? description;
  final String descriptionFormat;
  final String? imageUrl;
  final String imageAsset;
  final List<String> tags;
  final List<ProductTag> tagDetails;
  final bool isFeatured;
  final bool isFavorite;
  final Category? category;
  final CocktailLiquor? selectedLiquor;
  final List<LiquorCompatibility> compatibleLiquors;
  final ProductVariant? variant;
  final Availability availability;
  final List<CocktailIngredient> ingredients;
  final List<CocktailIngredient> includedIngredients;
  final List<CocktailIngredient> customerSuppliedIngredients;
  final bool customerSuppliesLiquor;
  final bool liquorNotIncluded;
  final List<CocktailHowToStep> howToMake;
  final CocktailRecipe? recipe;
  final CocktailCustomizationOptions customization;
  final CocktailDetailCopy copy;

  const CocktailDetail({
    required this.id,
    required this.slug,
    required this.name,
    required this.shortDescription,
    required this.description,
    required this.descriptionFormat,
    required this.imageUrl,
    required this.imageAsset,
    required this.tags,
    required this.tagDetails,
    required this.isFeatured,
    required this.isFavorite,
    required this.category,
    required this.selectedLiquor,
    required this.compatibleLiquors,
    required this.variant,
    required this.availability,
    required this.ingredients,
    required this.includedIngredients,
    required this.customerSuppliedIngredients,
    required this.customerSuppliesLiquor,
    required this.liquorNotIncluded,
    required this.howToMake,
    required this.recipe,
    required this.customization,
    required this.copy,
  });

  factory CocktailDetail.fromJson(Map<String, dynamic> json) {
    final name = readString(json['name'], fallback: 'Cocktail');
    final variant = json['variant'] is Map
        ? ProductVariant.fromJson(asMap(json['variant']))
        : null;

    final howToMake = readMapList(json['how_to_make'])
        .map(CocktailHowToStep.fromJson)
        .where((step) => step.title.trim().isNotEmpty)
        .toList();

    return CocktailDetail(
      id: readString(json['id']),
      slug: readString(json['slug']),
      name: name,
      shortDescription: nullableString(json['short_description']),
      description: nullableString(json['description']),
      descriptionFormat: readString(
        json['description_format'],
        fallback: 'markdown',
      ),
      imageUrl: nullableString(json['image_url']),
      imageAsset: CocktailAssets.forName(name),
      tags: readStringList(json['tags']),
      tagDetails: sortProductTags(
        readMapList(json['tag_details']).map(ProductTag.fromJson).toList(),
      ),
      isFeatured: readBool(json['is_featured']),
      isFavorite: readBool(json['is_favorite']),
      category: json['category'] is Map<String, dynamic>
          ? Category.fromJson(asMap(json['category']))
          : null,
      selectedLiquor: json['selected_liquor'] is Map
          ? CocktailLiquor.fromJson(asMap(json['selected_liquor']))
          : null,
      compatibleLiquors: readMapList(
        json['compatible_liquors'],
      ).map(LiquorCompatibility.fromJson).toList(),
      variant: variant,
      availability: Availability.fromJson(asMap(json['availability'])),
      ingredients: readMapList(
        json['ingredients'],
      ).map(CocktailIngredient.fromJson).toList(),
      includedIngredients: readMapList(
        json['included_ingredients'],
      ).map(CocktailIngredient.fromJson).toList(),
      customerSuppliedIngredients: readMapList(
        json['customer_supplied_ingredients'],
      ).map(CocktailIngredient.fromJson).toList(),
      customerSuppliesLiquor: readBool(
        json['customer_supplies_liquor'],
        fallback: true,
      ),
      liquorNotIncluded: readBool(json['liquor_not_included'], fallback: true),
      howToMake: howToMake.isEmpty ? CocktailHowToStep.defaults : howToMake,
      recipe: json['recipe'] is Map
          ? CocktailRecipe.fromJson(asMap(json['recipe']))
          : null,
      customization: CocktailCustomizationOptions.fromJson(
        asMap(json['customization']),
      ),
      copy: CocktailDetailCopy.fromJson(asMap(json['copy'])),
    );
  }

  String get cleanShortDescription => shortDescription?.trim() ?? '';

  String get cleanDescription => description?.trim() ?? '';

  bool get canAddToCart {
    final selectedVariant = variant;

    return selectedVariant != null &&
        availability.isOrderable &&
        selectedVariant.availability.isOrderable;
  }

  String get availabilityMessage {
    final cocktailReason = availability.reason?.trim();

    if (!availability.isOrderable &&
        cocktailReason != null &&
        cocktailReason.isNotEmpty) {
      return cocktailReason;
    }

    final selectedVariant = variant;
    final variantReason = selectedVariant?.availability.reason?.trim();

    if (selectedVariant != null && !selectedVariant.availability.isOrderable) {
      if (variantReason != null && variantReason.isNotEmpty) {
        return variantReason;
      }

      return 'This serving size is currently unavailable.';
    }

    return availability.isOrderable ? 'Available now' : 'Currently unavailable';
  }
}

class CocktailCustomizationOptions {
  final bool canCustomize;
  final CustomizationRules rules;
  final List<RemovableIngredient> removableIngredients;
  final List<CocktailAdditionOption> additions;

  const CocktailCustomizationOptions({
    required this.canCustomize,
    required this.rules,
    required this.removableIngredients,
    required this.additions,
  });

  factory CocktailCustomizationOptions.fromJson(Map<String, dynamic> json) {
    return CocktailCustomizationOptions(
      canCustomize: readBool(json['can_customize']),
      rules: CustomizationRules.fromJson(asMap(json['rules'])),
      removableIngredients: readMapList(
        json['removable_ingredients'],
      ).map(RemovableIngredient.fromJson).toList(),
      additions: readMapList(
        json['additions'],
      ).map(CocktailAdditionOption.fromJson).toList(),
    );
  }

  bool get hasOptions =>
      removableIngredients.isNotEmpty || additions.isNotEmpty;

  bool get shouldShow => canCustomize && hasOptions;
}

class CustomizationRules {
  final bool removalsAreFree;
  final bool additionsArePaid;
  final bool substitutionsAllowed;

  const CustomizationRules({
    required this.removalsAreFree,
    required this.additionsArePaid,
    required this.substitutionsAllowed,
  });

  factory CustomizationRules.fromJson(Map<String, dynamic> json) {
    return CustomizationRules(
      removalsAreFree: readBool(json['removals_are_free'], fallback: true),
      additionsArePaid: readBool(json['additions_are_paid'], fallback: true),
      substitutionsAllowed: readBool(json['substitutions_allowed']),
    );
  }
}

class RemovableIngredient {
  final String recipeItemId;
  final String ingredientId;
  final String name;
  final num? quantity;
  final String? unit;
  final String? iconKey;
  final bool isOptional;

  const RemovableIngredient({
    required this.recipeItemId,
    required this.ingredientId,
    required this.name,
    required this.quantity,
    required this.unit,
    required this.iconKey,
    required this.isOptional,
  });

  factory RemovableIngredient.fromJson(Map<String, dynamic> json) {
    return RemovableIngredient(
      recipeItemId: readString(json['recipe_item_id']),
      ingredientId: readString(json['ingredient_id']),
      name: readString(json['name'], fallback: 'Ingredient'),
      quantity: readDouble(json['quantity']),
      unit: nullableString(json['unit']),
      iconKey: nullableString(json['icon_key']),
      isOptional: readBool(json['is_optional']),
    );
  }
}

class CocktailAdditionOption {
  final String productId;
  final String variantId;
  final String name;
  final String? shortDescription;
  final String? imageUrl;
  final String? variantName;
  final double priceIncVat;
  final String currency;
  final bool isOrderable;
  final String? unavailableReason;

  const CocktailAdditionOption({
    required this.productId,
    required this.variantId,
    required this.name,
    required this.shortDescription,
    required this.imageUrl,
    required this.variantName,
    required this.priceIncVat,
    required this.currency,
    required this.isOrderable,
    required this.unavailableReason,
  });

  factory CocktailAdditionOption.fromJson(Map<String, dynamic> json) {
    final availability = asMap(json['availability']);

    return CocktailAdditionOption(
      productId: readString(json['product_id']),
      variantId: readString(json['variant_id']),
      name: readString(json['name'], fallback: 'Add-on'),
      shortDescription: nullableString(json['short_description']),
      imageUrl: nullableString(json['image_url']),
      variantName: nullableString(json['variant_name']),
      priceIncVat: readDouble(json['price_inc_vat']) ?? 0,
      currency: readString(json['currency'], fallback: 'EGP'),
      isOrderable: readBool(
        availability['is_orderable'] ?? availability['is_available'],
        fallback: true,
      ),
      unavailableReason: nullableString(availability['reason']),
    );
  }

  String get priceLabel => '+${formatMoney(priceIncVat, currency)}';
}

class SelectedAddition {
  final String productId;
  final String variantId;
  final int quantity;

  const SelectedAddition({
    required this.productId,
    required this.variantId,
    this.quantity = 1,
  });

  Map<String, dynamic> toCartJson() {
    return {
      'addon_product_id': productId,
      'addon_variant_id': variantId,
      'quantity': quantity,
    };
  }
}

class CocktailLiquor {
  final String id;
  final String name;
  final String? imageUrl;
  final int displayOrder;
  final double? requiredMlPerServing;
  final String? displayInstruction;

  const CocktailLiquor({
    required this.id,
    required this.name,
    required this.imageUrl,
    required this.displayOrder,
    required this.requiredMlPerServing,
    required this.displayInstruction,
  });

  factory CocktailLiquor.fromJson(Map<String, dynamic> json) {
    return CocktailLiquor(
      id: readString(json['id']),
      name: readString(json['name'], fallback: 'Bottle'),
      imageUrl: nullableString(json['image_url']),
      displayOrder: readInt(json['display_order']),
      requiredMlPerServing: readDouble(json['required_ml_per_serving']),
      displayInstruction: nullableString(json['display_instruction']),
    );
  }
}

class CocktailIngredient {
  final String id;
  final String name;
  final String? category;
  final String? iconKey;
  final bool isOptional;
  final bool isCustomerSupplied;

  const CocktailIngredient({
    required this.id,
    required this.name,
    required this.category,
    required this.iconKey,
    required this.isOptional,
    required this.isCustomerSupplied,
  });

  factory CocktailIngredient.fromJson(Map<String, dynamic> json) {
    return CocktailIngredient(
      id: readString(json['id']),
      name: readString(json['name'], fallback: 'Ingredient'),
      category: nullableString(json['category']),
      iconKey: nullableString(json['icon_key']),
      isOptional: readBool(json['is_optional']),
      isCustomerSupplied: readBool(json['is_customer_supplied']),
    );
  }
}

class CocktailHowToStep {
  final int step;
  final String title;

  const CocktailHowToStep({required this.step, required this.title});

  factory CocktailHowToStep.fromJson(Map<String, dynamic> json) {
    return CocktailHowToStep(
      step: readInt(json['step']),
      title: readString(json['title']),
    );
  }

  static const defaults = [
    CocktailHowToStep(step: 1, title: 'Add your liquor over ice'),
    CocktailHowToStep(step: 2, title: 'Pour in your EBTL cocktail mix'),
    CocktailHowToStep(step: 3, title: 'Garnish, sip & enjoy'),
  ];
}

class CocktailRecipe {
  final String id;
  final int version;
  final int yieldServings;

  const CocktailRecipe({
    required this.id,
    required this.version,
    required this.yieldServings,
  });

  factory CocktailRecipe.fromJson(Map<String, dynamic> json) {
    return CocktailRecipe(
      id: readString(json['id']),
      version: readInt(json['version'], fallback: 1),
      yieldServings: readInt(json['yield_servings'], fallback: 1),
    );
  }
}

class CocktailDetailCopy {
  final String bringYourBottleTitle;
  final String bringYourBottleName;
  final String bottleNote;
  final String relatedTitle;

  const CocktailDetailCopy({
    required this.bringYourBottleTitle,
    required this.bringYourBottleName,
    required this.bottleNote,
    required this.relatedTitle,
  });

  factory CocktailDetailCopy.fromJson(Map<String, dynamic> json) {
    return CocktailDetailCopy(
      bringYourBottleTitle: readString(
        json['bring_your_bottle_title'],
        fallback: 'Bring your bottle',
      ),
      bringYourBottleName: readString(json['bring_your_bottle_name']),
      bottleNote: readString(
        json['bottle_note'],
        fallback: 'Bottle not included.',
      ),
      relatedTitle: readString(
        json['related_title'],
        fallback: 'More cocktails',
      ),
    );
  }
}

class CartContext {
  final String? cartId;
  final String? selectedVariantId;
  final int quantityForSelectedVariant;
  final Map<String, int> quantitiesByVariant;
  final int totalQuantity;

  const CartContext({
    required this.cartId,
    required this.selectedVariantId,
    required this.quantityForSelectedVariant,
    required this.quantitiesByVariant,
    required this.totalQuantity,
  });

  factory CartContext.fromJson(Map<String, dynamic> json) {
    final rawQuantities = asMap(json['quantities_by_variant']);
    final quantities = <String, int>{};

    rawQuantities.forEach((key, value) {
      quantities[key] = readInt(value);
    });

    return CartContext(
      cartId: nullableString(json['cart_id']),
      selectedVariantId: nullableString(json['selected_variant_id']),
      quantityForSelectedVariant: readInt(
        json['quantity_for_selected_variant'],
      ),
      quantitiesByVariant: quantities,
      totalQuantity: readInt(json['total_quantity']),
    );
  }
}

class RelatedCocktail {
  final String id;
  final String slug;
  final String name;
  final String? shortDescription;
  final String? imageUrl;
  final String imageAsset;
  final List<ProductTag> tagDetails;
  final ProductVariant? variant;
  final double? startingPriceIncVat;
  final String currency;

  const RelatedCocktail({
    required this.id,
    required this.slug,
    required this.name,
    required this.shortDescription,
    required this.imageUrl,
    required this.imageAsset,
    required this.tagDetails,
    required this.variant,
    required this.startingPriceIncVat,
    required this.currency,
  });

  factory RelatedCocktail.fromJson(Map<String, dynamic> json) {
    final name = readString(json['name'], fallback: 'Cocktail');

    return RelatedCocktail(
      id: readString(json['id']),
      slug: readString(json['slug']),
      name: name,
      shortDescription: nullableString(json['short_description']),
      imageUrl: nullableString(json['image_url']),
      imageAsset: CocktailAssets.forName(name),
      tagDetails: sortProductTags(
        readMapList(json['tag_details']).map(ProductTag.fromJson).toList(),
      ),
      variant: json['variant'] is Map
          ? ProductVariant.fromJson(asMap(json['variant']))
          : null,
      startingPriceIncVat: readDouble(json['starting_price_inc_vat']),
      currency: readString(json['currency'], fallback: 'EGP'),
    );
  }

  double? get priceIncVat => variant?.priceIncVat ?? startingPriceIncVat;

  String get priceLabel => formatOptionalPrice(priceIncVat, currency);
}
