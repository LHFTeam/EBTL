import '../core/utils/json_helpers.dart';
import 'common_models.dart';

class AddToCartResult {
  final String actionType;
  final CartSummary? totals;
  final List<String> blockingReasons;

  const AddToCartResult({
    required this.actionType,
    required this.totals,
    required this.blockingReasons,
  });

  factory AddToCartResult.fromJson(Map<String, dynamic> json) {
    final action = asMap(json['action']);
    final checkoutReadiness = asMap(
      json['checkoutReadiness'] ?? json['checkout_readiness'],
    );

    final totalsMap = json['totals'] is Map
        ? asMap(json['totals'])
        : asMap(json['cartSummary'] ?? json['cart_summary']);

    return AddToCartResult(
      actionType: readString(action['type'], fallback: 'item_added'),
      totals: totalsMap.isEmpty ? null : CartSummary.fromJson(totalsMap),
      blockingReasons: readStringList(checkoutReadiness['blocking_reasons']),
    );
  }

  String get successMessage {
    if (actionType == 'quantity_incremented') {
      return 'Cart quantity updated.';
    }

    return 'Added to cart.';
  }
}
