class FulfillmentTypes {
  static const pickupAtCart = 'pickup_at_cart';
  static const deliveryToUnit = 'delivery_to_unit';

  static String labelFor(String value) {
    switch (value) {
      case deliveryToUnit:
        return 'Delivery to Unit';
      case pickupAtCart:
      default:
        return 'Pickup at Cart';
    }
  }

  static String helperFor(String value) {
    switch (value) {
      case deliveryToUnit:
        return 'Delivery fee is calculated by the backend.';
      case pickupAtCart:
      default:
        return 'Collect your cocktail kit directly from the beach cart.';
    }
  }
}
