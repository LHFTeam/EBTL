import '../core/utils/json_helpers.dart';

class Availability {
  final bool isOrderable;
  final String? reason;

  const Availability({required this.isOrderable, required this.reason});

  factory Availability.fromJson(Map<String, dynamic> json) {
    return Availability(
      isOrderable: readBool(json['is_orderable']),
      reason: nullableString(json['reason']),
    );
  }
}

class ProductVariant {
  final String id;
  final String name;
  final int servingCount;
  final double priceIncVat;
  final String currency;
  final bool isActive;
  final Availability availability;

  const ProductVariant({
    required this.id,
    required this.name,
    required this.servingCount,
    required this.priceIncVat,
    required this.currency,
    required this.isActive,
    required this.availability,
  });

  factory ProductVariant.fromJson(Map<String, dynamic> json) {
    return ProductVariant(
      id: readString(json['id']),
      name: readString(json['name'], fallback: 'Variant'),
      servingCount: readInt(json['serving_count'], fallback: 1),
      priceIncVat: readDouble(json['price_inc_vat']) ?? 0,
      currency: readString(json['currency'], fallback: 'EGP'),
      isActive: readBool(json['is_active'], fallback: true),
      availability: Availability.fromJson(asMap(json['availability'])),
    );
  }
}

class LiquorCompatibility {
  final String liquorTypeId;
  final String liquorTypeName;
  final String? liquorTypeImageUrl;
  final double? requiredMlPerServing;
  final String? displayInstruction;

  const LiquorCompatibility({
    required this.liquorTypeId,
    required this.liquorTypeName,
    required this.liquorTypeImageUrl,
    required this.requiredMlPerServing,
    required this.displayInstruction,
  });

  factory LiquorCompatibility.fromJson(Map<String, dynamic> json) {
    return LiquorCompatibility(
      liquorTypeId: readString(json['liquor_type_id']),
      liquorTypeName: readString(json['liquor_type_name'], fallback: 'Bottle'),
      liquorTypeImageUrl: nullableString(json['liquor_type_image_url']),
      requiredMlPerServing: readDouble(json['required_ml_per_serving']),
      displayInstruction: nullableString(json['display_instruction']),
    );
  }
}
