import '../core/utils/json_helpers.dart';

class CustomerAddress {
  final String id;
  final String? label;
  final String? compoundName;
  final String? beachName;
  final String? unitNumber;
  final String? building;
  final String? floor;
  final String? deliveryNotes;
  final double? latitude;
  final double? longitude;
  final bool isDefault;

  const CustomerAddress({
    required this.id,
    required this.label,
    required this.compoundName,
    required this.beachName,
    required this.unitNumber,
    required this.building,
    required this.floor,
    required this.deliveryNotes,
    required this.latitude,
    required this.longitude,
    required this.isDefault,
  });

  factory CustomerAddress.fromJson(Map<String, dynamic> json) {
    return CustomerAddress(
      id: readString(json['id']),
      label: nullableString(json['label']),
      compoundName: nullableString(json['compound_name']),
      beachName: nullableString(json['beach_name']),
      unitNumber: nullableString(json['unit_number']),
      building: nullableString(json['building']),
      floor: nullableString(json['floor']),
      deliveryNotes: nullableString(json['delivery_notes']),
      latitude: json['latitude'] == null ? null : readDouble(json['latitude']),
      longitude:
          json['longitude'] == null ? null : readDouble(json['longitude']),
      isDefault: readBool(json['is_default']),
    );
  }

  /// Best label to show as the card heading.
  String get title {
    final labelText = label?.trim();
    if (labelText != null && labelText.isNotEmpty) return labelText;

    final compound = compoundName?.trim();
    if (compound != null && compound.isNotEmpty) return compound;

    final beach = beachName?.trim();
    if (beach != null && beach.isNotEmpty) return beach;

    return 'Address';
  }

  /// Human-readable one-line description of the location details.
  String get summary {
    final parts = <String>[
      if ((compoundName ?? '').trim().isNotEmpty) compoundName!.trim(),
      if ((beachName ?? '').trim().isNotEmpty) beachName!.trim(),
      if ((building ?? '').trim().isNotEmpty) 'Building ${building!.trim()}',
      if ((floor ?? '').trim().isNotEmpty) 'Floor ${floor!.trim()}',
      if ((unitNumber ?? '').trim().isNotEmpty) 'Unit ${unitNumber!.trim()}',
    ];

    return parts.join(' · ');
  }
}

class CustomerAddressesResponse {
  final List<CustomerAddress> addresses;

  const CustomerAddressesResponse({required this.addresses});

  factory CustomerAddressesResponse.fromJson(Map<String, dynamic> json) {
    return CustomerAddressesResponse(
      addresses: readMapList(
        json['addresses'],
      ).map(CustomerAddress.fromJson).toList(),
    );
  }
}
