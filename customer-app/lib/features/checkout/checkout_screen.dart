import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';

import '../../core/constants/fulfillment_types.dart';
import '../../core/constants/order_confirmation_assets.dart';
import '../../core/network/api_exception.dart';
import '../../core/theme/ebtl_colors.dart';
import '../../core/utils/formatters.dart';
import '../../models/checkout_models.dart';
import '../../services/api_service.dart';
import '../../shared/widgets/app_state_widgets.dart';
import '../../shared/widgets/brand_widgets.dart';
import '../../shared/widgets/network_or_asset_image.dart';
import '../../shared/widgets/detail_card.dart';
import '../../shared/widgets/checkout_input_field.dart';

class CheckoutScreen extends StatefulWidget {
  final String locationId;
  final String fulfillmentType;
  final VoidCallback onEditCart;
  final VoidCallback onCartChanged;
  final VoidCallback onOrderCompleted;

  const CheckoutScreen({
    super.key,
    required this.locationId,
    required this.fulfillmentType,
    required this.onEditCart,
    required this.onCartChanged,
    required this.onOrderCompleted,
  });

  @override
  State<CheckoutScreen> createState() => _CheckoutScreenState();
}

class _CheckoutScreenState extends State<CheckoutScreen> {
  static final RegExp egyptMobileRegex = RegExp(r'^0\d{10}$');

  final TextEditingController nameController = TextEditingController();
  final TextEditingController phoneController = TextEditingController();
  final TextEditingController addressController = TextEditingController();
  final TextEditingController promoController = TextEditingController();

  late Future<CheckoutPageResponse> checkoutFuture;

  CheckoutQuote? quoteOverride;
  String? selectedPaymentMethodKey;
  String? promoError;
  String? activeIdempotencyKey;

  bool isApplyingPromo = false;
  bool isPlacingOrder = false;
  bool showValidationErrors = false;

  @override
  void initState() {
    super.initState();
    checkoutFuture = loadCheckout();
  }

  @override
  void dispose() {
    nameController.dispose();
    phoneController.dispose();
    addressController.dispose();
    promoController.dispose();
    super.dispose();
  }

  Future<CheckoutPageResponse> loadCheckout() async {
    final response = await ApiService.fetchCheckout(
      locationId: widget.locationId,
      fulfillmentType: widget.fulfillmentType,
      promoCode: promoController.text.trim(),
    );

    await prefillCustomerDetails(response.checkout.customer);

    final enabledMethods = response.checkout.enabledPaymentMethods;
    if (enabledMethods.isNotEmpty &&
        response.checkout.paymentMethodByKey(selectedPaymentMethodKey) ==
            null) {
      selectedPaymentMethodKey = enabledMethods.first.key;
    }

    return response;
  }

  Future<void> prefillCustomerDetails(CheckoutCustomer checkoutCustomer) async {
    final checkoutName = checkoutCustomer.name?.trim();
    final checkoutPhone = checkoutCustomer.phone?.trim();

    if (nameController.text.trim().isEmpty &&
        checkoutName != null &&
        checkoutName.isNotEmpty) {
      nameController.text = checkoutName;
    }

    if (phoneController.text.trim().isEmpty &&
        checkoutPhone != null &&
        checkoutPhone.isNotEmpty) {
      phoneController.text = checkoutPhone;
    }

    final needsProfileFallback =
        nameController.text.trim().isEmpty ||
        phoneController.text.trim().isEmpty;

    if (!needsProfileFallback) return;

    try {
      final profileResponse = await ApiService.fetchCustomerProfile();
      final profile = profileResponse.customer;
      final profileName = profile.fullName?.trim();
      final profilePhone = profile.phone?.trim();

      if (nameController.text.trim().isEmpty &&
          profileName != null &&
          profileName.isNotEmpty) {
        nameController.text = profileName;
      }

      if (phoneController.text.trim().isEmpty &&
          profilePhone != null &&
          profilePhone.isNotEmpty) {
        phoneController.text = profilePhone;
      }
    } catch (_) {
      // Do not block checkout if the profile fallback cannot be loaded.
    }
  }

  void reloadCheckout() {
    setState(() {
      quoteOverride = null;
      promoError = null;
      checkoutFuture = loadCheckout();
    });
  }

  CheckoutSummary effectiveSummary(CheckoutData checkout) {
    return quoteOverride?.summary ?? checkout.summary;
  }

  CheckoutValidation effectiveValidation(CheckoutData checkout) {
    return quoteOverride?.validation ?? checkout.validation;
  }

  CheckoutPromotion? effectivePromotion(CheckoutData checkout) {
    return quoteOverride?.promotion ?? checkout.promotion;
  }

  CheckoutPaymentMethod? selectedPaymentMethod(CheckoutData checkout) {
    return checkout.paymentMethodByKey(selectedPaymentMethodKey);
  }

  bool get isCustomerNameValid => nameController.text.trim().isNotEmpty;

  bool get isPhoneValid {
    return egyptMobileRegex.hasMatch(phoneController.text.trim());
  }

  bool isAddressValid(CheckoutData checkout) {
    if (!checkout.fulfillment.isDelivery) return true;
    return addressController.text.trim().isNotEmpty;
  }

  String? firstLocalBlockingReason(CheckoutData checkout) {
    if (!isCustomerNameValid) return 'Enter your name.';
    if (!isPhoneValid) {
      return 'Enter an Egyptian mobile number, 11 digits, starting with 0.';
    }
    if (!isAddressValid(checkout)) return 'Enter your delivery address.';
    if (selectedPaymentMethod(checkout) == null) {
      return 'Choose an available payment method.';
    }

    final backendReason = effectiveValidation(checkout).firstBlockingReason;
    if (!effectiveValidation(checkout).canPlaceOrder &&
        backendReason != null &&
        backendReason.trim().isNotEmpty) {
      return backendReason;
    }

    if (!effectiveValidation(checkout).canPlaceOrder) {
      return 'This order cannot be placed yet.';
    }

    return null;
  }

  bool canPlaceOrder(CheckoutData checkout) {
    return !isPlacingOrder && firstLocalBlockingReason(checkout) == null;
  }

  String generateIdempotencyKey() {
    return 'checkout-${DateTime.now().microsecondsSinceEpoch}';
  }

  String errorMessage(Object error) => apiErrorMessage(error);

  Future<void> applyPromo(CheckoutData checkout) async {
    if (isApplyingPromo) return;

    final code = promoController.text.trim();

    if (code.isEmpty) {
      setState(() {
        quoteOverride = null;
        promoError = null;
      });
      return;
    }

    setState(() {
      isApplyingPromo = true;
      promoError = null;
    });

    try {
      final quoteResponse = await ApiService.quoteCheckout(
        cartId: checkout.cartId,
        locationId: widget.locationId,
        fulfillmentType: checkout.fulfillment.type,
        address: addressController.text.trim(),
        promoCode: code,
      );

      if (!mounted) return;

      setState(() {
        quoteOverride = quoteResponse.quote;
        isApplyingPromo = false;
        promoError = null;
      });
    } catch (error) {
      if (!mounted) return;

      setState(() {
        quoteOverride = null;
        isApplyingPromo = false;
        promoError = error is ApiException
            ? error.message
            : 'Could not apply this promo code.';
      });
    }
  }

  Future<PaymentStatusResponse> pollPaymentStatus(String orderId) async {
    PaymentStatusResponse? latest;

    for (int i = 0; i < 10; i += 1) {
      latest = await ApiService.fetchOrderPaymentStatus(orderId: orderId);

      if (latest.isFinal) return latest;

      await Future<void>.delayed(const Duration(seconds: 2));
    }

    return latest ?? await ApiService.fetchOrderPaymentStatus(orderId: orderId);
  }

  void openOrderConfirmed(
    CheckoutOrder order, {
    CheckoutLocation? location,
    double? paidAmount,
    String? paidAmountCurrency,
    String? paymentStatusOverride,
  }) {
    if (!mounted) return;

    setState(() => isPlacingOrder = false);

    Navigator.of(context).pushReplacement(
      MaterialPageRoute(
        builder: (_) => OrderConfirmedScreen(
          order: order,
          location: location,
          paidAmount: paidAmount,
          paidAmountCurrency: paidAmountCurrency,
          paymentStatusOverride: paymentStatusOverride,
          onDone: widget.onOrderCompleted,
        ),
      ),
    );
  }

  Future<void> startGeideaSdkAndRefresh(
    PlaceOrderResponse response,
    CheckoutData checkout,
  ) async {
    /*
      IMPORTANT:
      This project file does not yet include the actual Geidea Flutter package/imports.
      Keep this method as the only integration point.

      Once the Geidea package is installed, replace the dialog below with the real SDK call
      using response.payment.geidea.sessionId, then keep the payment-status polling below.
    */

    final geidea = response.payment.geidea;

    await showModalBottomSheet<void>(
      context: context,
      backgroundColor: Colors.transparent,
      builder: (context) {
        return SafeArea(
          child: Container(
            margin: const EdgeInsets.all(16),
            padding: const EdgeInsets.all(20),
            decoration: BoxDecoration(
              color: EbtlColors.white,
              borderRadius: BorderRadius.circular(26),
              border: Border.all(color: EbtlColors.border),
            ),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                Container(
                  width: 58,
                  height: 58,
                  decoration: const BoxDecoration(
                    color: EbtlColors.seafoam,
                    shape: BoxShape.circle,
                  ),
                  child: const Icon(
                    Icons.credit_card,
                    color: EbtlColors.navy,
                    size: 30,
                  ),
                ),
                const SizedBox(height: 14),
                Text(
                  'Payment session ready',
                  textAlign: TextAlign.center,
                  style: GoogleFonts.playfairDisplay(
                    fontSize: 28,
                    fontWeight: FontWeight.w800,
                    color: EbtlColors.navy,
                  ),
                ),
                const SizedBox(height: 8),
                Text(
                  'Geidea session ID was created by the backend. Replace this sheet with the Geidea SDK start call once the SDK dependency is installed.',
                  textAlign: TextAlign.center,
                  style: GoogleFonts.manrope(
                    fontSize: 13,
                    height: 1.4,
                    fontWeight: FontWeight.w600,
                    color: EbtlColors.ink,
                  ),
                ),
                const SizedBox(height: 10),
                SelectableText(
                  geidea.sessionId,
                  textAlign: TextAlign.center,
                  style: GoogleFonts.manrope(
                    fontSize: 12,
                    color: EbtlColors.muted,
                    fontWeight: FontWeight.w700,
                  ),
                ),
                const SizedBox(height: 16),
                SizedBox(
                  width: double.infinity,
                  height: 52,
                  child: ElevatedButton(
                    onPressed: () => Navigator.of(context).pop(),
                    style: ebtlCoralButtonStyle(),
                    child: Text(
                      'Check Payment Status',
                      style: GoogleFonts.manrope(fontWeight: FontWeight.w900),
                    ),
                  ),
                ),
              ],
            ),
          ),
        );
      },
    );

    final status = await pollPaymentStatus(response.order.id);

    if (!mounted) return;

    if (status.isPaid) {
      openOrderConfirmed(
        response.order,
        location: checkout.location,
        paidAmount: status.payment.amount,
        paidAmountCurrency: status.payment.currency,
        paymentStatusOverride: status.paymentStatus,
      );
      return;
    }

    Navigator.of(context).pushReplacement(
      MaterialPageRoute(
        builder: (_) => CheckoutResultScreen(
          status: status,
          onDone: () {
            Navigator.of(context).pop();
          },
        ),
      ),
    );
  }

  Future<void> placeOrder(CheckoutData checkout) async {
    setState(() => showValidationErrors = true);

    final localReason = firstLocalBlockingReason(checkout);
    if (localReason != null) {
      showAppSnackBar(context, localReason);
      return;
    }

    final method = selectedPaymentMethod(checkout);
    if (method == null) return;

    setState(() => isPlacingOrder = true);

    activeIdempotencyKey ??= generateIdempotencyKey();

    try {
      final response = await ApiService.placeCheckoutOrder(
        cartId: checkout.cartId,
        locationId: widget.locationId,
        fulfillmentType: checkout.fulfillment.type,
        address: addressController.text.trim(),
        customerName: nameController.text.trim(),
        customerPhone: phoneController.text.trim(),
        paymentMethod: method.key,
        idempotencyKey: activeIdempotencyKey!,
        promoCode: promoController.text.trim(),
      );

      if (!mounted) return;

      widget.onCartChanged();

      if (response.nextScreen == 'order_confirmed' ||
          response.payment.provider == 'demo' ||
          !response.payment.requiredPayment) {
        openOrderConfirmed(response.order, location: checkout.location);
        return;
      }

      await startGeideaSdkAndRefresh(response, checkout);
    } catch (error) {
      if (!mounted) return;

      setState(() => isPlacingOrder = false);

      showAppSnackBar(context, errorMessage(error));
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: EbtlColors.cream,
      body: SafeArea(
        child: FutureBuilder<CheckoutPageResponse>(
          future: checkoutFuture,
          builder: (context, snapshot) {
            if (snapshot.connectionState == ConnectionState.waiting) {
              return const EbtlLoadingSection(
                label: 'Preparing checkout...',
              );
            }

            if (snapshot.hasError) {
              return CustomScrollView(
                slivers: [
                  SliverToBoxAdapter(
                    child: CheckoutTopHeader(
                      onBack: () => Navigator.of(context).pop(),
                    ),
                  ),
                  SliverToBoxAdapter(
                    child: InlineErrorCard(
                      message: snapshot.error.toString(),
                      onRetry: reloadCheckout,
                    ),
                  ),
                ],
              );
            }

            final response = snapshot.data;
            if (response == null) {
              return CustomScrollView(
                slivers: [
                  SliverToBoxAdapter(
                    child: CheckoutTopHeader(
                      onBack: () => Navigator.of(context).pop(),
                    ),
                  ),
                  SliverToBoxAdapter(
                    child: InlineErrorCard(
                      message: 'The backend returned no checkout data.',
                      onRetry: reloadCheckout,
                    ),
                  ),
                ],
              );
            }

            final checkout = response.checkout;
            final enabledMethods = checkout.enabledPaymentMethods;

            if (enabledMethods.isNotEmpty &&
                checkout.paymentMethodByKey(selectedPaymentMethodKey) == null) {
              selectedPaymentMethodKey = enabledMethods.first.key;
            }

            final summary = effectiveSummary(checkout);
            final promotion = effectivePromotion(checkout);
            final validation = effectiveValidation(checkout);
            final placeEnabled = canPlaceOrder(checkout);

            return CustomScrollView(
              slivers: [
                SliverToBoxAdapter(
                  child: CheckoutTopHeader(
                    onBack: () => Navigator.of(context).pop(),
                  ),
                ),
                const SliverToBoxAdapter(
                  child: CheckoutProgressBar(activeStepIndex: 1),
                ),
                SliverToBoxAdapter(
                  child: CheckoutLocationSummaryCard(
                    location: checkout.location,
                    fulfillmentType: checkout.fulfillment.type,
                  ),
                ),
                SliverToBoxAdapter(
                  child: CheckoutOrderStrip(
                    items: checkout.items,
                    itemWarnings: checkout.itemWarnings,
                    onEditCart: widget.onEditCart,
                  ),
                ),
                SliverToBoxAdapter(
                  child: CheckoutCustomerDetailsCard(
                    nameController: nameController,
                    phoneController: phoneController,
                    addressController: addressController,
                    showAddress: checkout.fulfillment.isDelivery,
                    showErrors: showValidationErrors,
                    isNameValid: isCustomerNameValid,
                    isPhoneValid: isPhoneValid,
                    isAddressValid: isAddressValid(checkout),
                    onChanged: () {
                      setState(() {
                        activeIdempotencyKey = null;
                      });
                    },
                  ),
                ),
                SliverToBoxAdapter(
                  child: CheckoutPromoCard(
                    controller: promoController,
                    isApplying: isApplyingPromo,
                    promoError: promoError,
                    promotion: promotion,
                    onChanged: (_) {
                      setState(() {
                        promoError = null;
                        quoteOverride = null;
                        activeIdempotencyKey = null;
                      });
                    },
                    onApply: () => applyPromo(checkout),
                    onRemove: () {
                      promoController.clear();
                      setState(() {
                        quoteOverride = null;
                        promoError = null;
                        activeIdempotencyKey = null;
                      });
                    },
                  ),
                ),
                SliverToBoxAdapter(
                  child: CheckoutPaymentMethodSection(
                    methods: enabledMethods,
                    selectedKey: selectedPaymentMethodKey,
                    onSelected: (key) {
                      setState(() {
                        selectedPaymentMethodKey = key;
                        activeIdempotencyKey = null;
                      });
                    },
                  ),
                ),
                if (!validation.canPlaceOrder ||
                    validation.blockingReasons.isNotEmpty)
                  SliverToBoxAdapter(
                    child: CheckoutBlockingReasonsCard(
                      reasons: validation.blockingReasons,
                      onEditCart: widget.onEditCart,
                    ),
                  ),
                SliverToBoxAdapter(
                  child: CheckoutSummaryCard(
                    summary: summary,
                    promotion: promotion,
                    canPlaceOrder: placeEnabled,
                    isPlacingOrder: isPlacingOrder,
                    onPlaceOrder: () => placeOrder(checkout),
                  ),
                ),
                const SliverToBoxAdapter(child: SizedBox(height: 20)),
              ],
            );
          },
        ),
      ),
    );
  }
}

class CheckoutTopHeader extends StatelessWidget {
  final VoidCallback onBack;

  const CheckoutTopHeader({super.key, required this.onBack});

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.fromLTRB(22, 12, 22, 8),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.center,
        children: [
          CircleIconButton(icon: Icons.arrow_back, onTap: onBack),
          Expanded(
            child: Center(
              child: Text(
                'Checkout',
                style: GoogleFonts.playfairDisplay(
                  fontSize: 30,
                  height: 1,
                  fontWeight: FontWeight.w800,
                  color: EbtlColors.navy,
                ),
              ),
            ),
          ),
          const SizedBox(width: 56),
        ],
      ),
    );
  }
}

class CheckoutProgressBar extends StatelessWidget {
  final int activeStepIndex;

  const CheckoutProgressBar({super.key, required this.activeStepIndex});

  @override
  Widget build(BuildContext context) {
    final steps = [
      (Icons.shopping_cart_outlined, 'Cart'),
      (Icons.credit_card, 'Payment'),
      (Icons.check, 'Confirm'),
    ];

    return Padding(
      padding: const EdgeInsets.fromLTRB(30, 6, 30, 20),
      child: Row(
        children: [
          for (int index = 0; index < steps.length; index += 1) ...[
            Expanded(
              child: CheckoutProgressStep(
                icon: steps[index].$1,
                label: '${index + 1}. ${steps[index].$2}',
                isActive: index == activeStepIndex,
                isComplete: index < activeStepIndex,
              ),
            ),
            if (index < steps.length - 1)
              Container(
                width: 42,
                height: 1,
                margin: const EdgeInsets.only(bottom: 20),
                color: EbtlColors.navy.withValues(alpha: 0.28),
              ),
          ],
        ],
      ),
    );
  }
}

class CheckoutProgressStep extends StatelessWidget {
  final IconData icon;
  final String label;
  final bool isActive;
  final bool isComplete;

  const CheckoutProgressStep({
    super.key,
    required this.icon,
    required this.label,
    required this.isActive,
    required this.isComplete,
  });

  @override
  Widget build(BuildContext context) {
    final color = isActive
        ? EbtlColors.coral
        : isComplete
        ? EbtlColors.teal
        : EbtlColors.navy.withValues(alpha: 0.65);

    return Column(
      children: [
        Container(
          width: 42,
          height: 42,
          decoration: BoxDecoration(
            color: EbtlColors.white.withValues(alpha: 0.72),
            shape: BoxShape.circle,
            border: Border.all(color: color, width: isActive ? 1.4 : 1),
          ),
          child: Icon(icon, color: color, size: 20),
        ),
        const SizedBox(height: 7),
        Text(
          label,
          textAlign: TextAlign.center,
          style: GoogleFonts.manrope(
            fontSize: 11,
            fontWeight: FontWeight.w800,
            color: color,
          ),
        ),
      ],
    );
  }
}

class CheckoutLocationSummaryCard extends StatelessWidget {
  final CheckoutLocation? location;
  final String fulfillmentType;

  const CheckoutLocationSummaryCard({
    super.key,
    required this.location,
    required this.fulfillmentType,
  });

  @override
  Widget build(BuildContext context) {
    final selectedLocation = location;
    final isDelivery = fulfillmentType == FulfillmentTypes.deliveryToUnit;

    return Padding(
      padding: const EdgeInsets.fromLTRB(22, 0, 22, 12),
      child: Column(
        children: [
          CheckoutSectionTitle(
            title: isDelivery ? 'Delivery Location' : 'Pickup Location',
            actionText: 'Edit',
            onAction: () => Navigator.of(context).pop(),
          ),
          Container(
            height: 88,
            decoration: BoxDecoration(
              color: EbtlColors.white.withValues(alpha: 0.92),
              borderRadius: BorderRadius.circular(18),
              border: Border.all(color: EbtlColors.border),
              boxShadow: [
                BoxShadow(
                  color: Colors.black.withValues(alpha: 0.035),
                  blurRadius: 18,
                  offset: const Offset(0, 8),
                ),
              ],
            ),
            clipBehavior: Clip.antiAlias,
            child: Row(
              children: [
                const SizedBox(width: 14),
                const Icon(
                  Icons.location_on_outlined,
                  color: EbtlColors.navy,
                  size: 24,
                ),
                const SizedBox(width: 10),
                Expanded(
                  child: Padding(
                    padding: const EdgeInsets.symmetric(vertical: 13),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          selectedLocation?.name ?? 'Selected Beach Cart',
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                          style: GoogleFonts.manrope(
                            fontSize: 14,
                            height: 1.15,
                            fontWeight: FontWeight.w900,
                            color: EbtlColors.navy,
                          ),
                        ),
                        const SizedBox(height: 4),
                        Text(
                          selectedLocation?.subtitle ?? 'Selected location',
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                          style: GoogleFonts.manrope(
                            fontSize: 11,
                            fontWeight: FontWeight.w600,
                            color: EbtlColors.muted,
                          ),
                        ),
                        const SizedBox(height: 4),
                        Text(
                          selectedLocation?.currentStatus.label ??
                              'Opening hours unavailable',
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                          style: GoogleFonts.manrope(
                            fontSize: 11,
                            fontWeight: FontWeight.w800,
                            color: EbtlColors.teal,
                          ),
                        ),
                      ],
                    ),
                  ),
                ),
                SizedBox(
                  width: 132,
                  height: double.infinity,
                  child: NetworkOrAssetImage(
                    imageUrl: selectedLocation?.bannerImageUrl,
                    asset: 'assets/images/location_banner_placeholder.jpg',
                    fit: BoxFit.cover,
                  ),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}

class CheckoutOrderStrip extends StatelessWidget {
  final List<CheckoutItem> items;
  final List<CheckoutItemWarning> itemWarnings;
  final VoidCallback onEditCart;

  const CheckoutOrderStrip({
    super.key,
    required this.items,
    required this.itemWarnings,
    required this.onEditCart,
  });

  @override
  Widget build(BuildContext context) {
    final totalQuantity = items.fold<int>(
      0,
      (sum, item) => sum + item.quantity,
    );

    return Padding(
      padding: const EdgeInsets.fromLTRB(22, 6, 0, 12),
      child: Column(
        children: [
          Padding(
            padding: const EdgeInsets.only(right: 22),
            child: CheckoutSectionTitle(
              title: 'Your Order',
              subtitle: '($totalQuantity item${totalQuantity == 1 ? '' : 's'})',
              actionText: 'Edit Cart',
              onAction: onEditCart,
            ),
          ),
          SizedBox(
            height: 112,
            child: ListView.separated(
              scrollDirection: Axis.horizontal,
              itemCount: items.length,
              separatorBuilder: (_, _) => const SizedBox(width: 12),
              itemBuilder: (context, index) {
                return CheckoutOrderMiniCard(item: items[index]);
              },
            ),
          ),
          if (itemWarnings.isNotEmpty) ...[
            const SizedBox(height: 10),
            Padding(
              padding: const EdgeInsets.only(right: 22),
              child: CheckoutWarningBox(
                message: itemWarnings
                    .map(
                      (warning) => '${warning.productName}: ${warning.reason}',
                    )
                    .join('\n'),
              ),
            ),
          ],
        ],
      ),
    );
  }
}

class CheckoutOrderMiniCard extends StatelessWidget {
  final CheckoutItem item;

  const CheckoutOrderMiniCard({super.key, required this.item});

  @override
  Widget build(BuildContext context) {
    final customizationSummary = item.cleanCustomizationSummary;
    final variantName = item.variantName.trim();

    return SizedBox(
      width: 192,
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.center,
        children: [
          ClipRRect(
            borderRadius: BorderRadius.circular(13),
            child: SizedBox(
              width: 62,
              height: 76,
              child: NetworkOrAssetImage(
                imageUrl: item.imageUrl,
                asset: item.imageAsset,
                fit: BoxFit.cover,
              ),
            ),
          ),
          const SizedBox(width: 9),
          Expanded(
            child: Padding(
              padding: const EdgeInsets.symmetric(vertical: 8),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    item.productName,
                    maxLines: 2,
                    overflow: TextOverflow.ellipsis,
                    style: GoogleFonts.manrope(
                      fontSize: 11.5,
                      height: 1.12,
                      fontWeight: FontWeight.w900,
                      color: EbtlColors.navy,
                    ),
                  ),
                  const SizedBox(height: 3),
                  if (variantName.isNotEmpty) ...[
                    Text(
                      variantName,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: GoogleFonts.manrope(
                        fontSize: 10.5,
                        fontWeight: FontWeight.w700,
                        color: EbtlColors.muted,
                      ),
                    ),
                    const SizedBox(height: 2),
                  ],
                  if (customizationSummary != null) ...[
                    Text(
                      customizationSummary,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: GoogleFonts.manrope(
                        fontSize: 10.5,
                        fontWeight: FontWeight.w800,
                        color: EbtlColors.teal,
                      ),
                    ),
                    const SizedBox(height: 2),
                  ],
                  Text(
                    'Qty ${item.quantity}',
                    style: GoogleFonts.manrope(
                      fontSize: 10.5,
                      fontWeight: FontWeight.w700,
                      color: EbtlColors.muted,
                    ),
                  ),
                  const Spacer(),
                  Text(
                    item.lineTotalLabel,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: GoogleFonts.manrope(
                      fontSize: 12,
                      fontWeight: FontWeight.w900,
                      color: item.isAvailable
                          ? EbtlColors.navy
                          : EbtlColors.coral,
                    ),
                  ),
                ],
              ),
            ),
          ),
        ],
      ),
    );
  }
}

class CheckoutCustomerDetailsCard extends StatelessWidget {
  final TextEditingController nameController;
  final TextEditingController phoneController;
  final TextEditingController addressController;
  final bool showAddress;
  final bool showErrors;
  final bool isNameValid;
  final bool isPhoneValid;
  final bool isAddressValid;
  final VoidCallback onChanged;

  const CheckoutCustomerDetailsCard({
    super.key,
    required this.nameController,
    required this.phoneController,
    required this.addressController,
    required this.showAddress,
    required this.showErrors,
    required this.isNameValid,
    required this.isPhoneValid,
    required this.isAddressValid,
    required this.onChanged,
  });

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.fromLTRB(22, 4, 22, 12),
      child: Column(
        children: [
          const CheckoutSectionTitle(title: 'Customer Details'),
          DetailCard(
            child: Column(
              children: [
                CheckoutInputField(
                  controller: nameController,
                  label: 'Name',
                  hintText: 'Your name',
                  icon: Icons.person_outline,
                  textInputAction: TextInputAction.next,
                  errorText: showErrors && !isNameValid
                      ? 'Name is required.'
                      : null,
                  onChanged: (_) => onChanged(),
                ),
                const SizedBox(height: 12),
                CheckoutInputField(
                  controller: phoneController,
                  label: 'Phone Number',
                  hintText: '01012345678',
                  icon: Icons.phone_outlined,
                  keyboardType: TextInputType.phone,
                  textInputAction: showAddress
                      ? TextInputAction.next
                      : TextInputAction.done,
                  maxLength: 11,
                  errorText: showErrors && !isPhoneValid
                      ? 'Use 11 digits starting with 0.'
                      : null,
                  onChanged: (_) => onChanged(),
                ),
                if (showAddress) ...[
                  const SizedBox(height: 12),
                  CheckoutInputField(
                    controller: addressController,
                    label: 'Address',
                    hintText: 'Cabana, unit, or delivery notes',
                    icon: Icons.home_outlined,
                    keyboardType: TextInputType.streetAddress,
                    textInputAction: TextInputAction.done,
                    maxLines: 2,
                    maxLength: 500,
                    errorText: showErrors && !isAddressValid
                        ? 'Address is required for delivery.'
                        : null,
                    onChanged: (_) => onChanged(),
                  ),
                ],
              ],
            ),
          ),
        ],
      ),
    );
  }
}

class CheckoutPromoCard extends StatelessWidget {
  final TextEditingController controller;
  final bool isApplying;
  final String? promoError;
  final CheckoutPromotion? promotion;
  final VoidCallback onApply;
  final VoidCallback onRemove;
  final ValueChanged<String> onChanged;

  const CheckoutPromoCard({
    super.key,
    required this.controller,
    required this.isApplying,
    required this.promoError,
    required this.promotion,
    required this.onApply,
    required this.onRemove,
    required this.onChanged,
  });

  @override
  Widget build(BuildContext context) {
    final hasPromotion = promotion != null;

    return Padding(
      padding: const EdgeInsets.fromLTRB(22, 0, 22, 12),
      child: Column(
        children: [
          const CheckoutSectionTitle(title: 'Promo Code'),
          DetailCard(
            child: Column(
              children: [
                Row(
                  children: [
                    Expanded(
                      child: CheckoutInputField(
                        controller: controller,
                        label: 'Promo Code',
                        hintText: 'Enter code',
                        icon: Icons.local_offer_outlined,
                        textInputAction: TextInputAction.done,
                        errorText: promoError,
                        onChanged: onChanged,
                      ),
                    ),
                    const SizedBox(width: 10),
                    SizedBox(
                      height: 56,
                      child: ElevatedButton(
                        onPressed: isApplying
                            ? null
                            : hasPromotion
                            ? onRemove
                            : onApply,
                        style: ElevatedButton.styleFrom(
                          backgroundColor: hasPromotion
                              ? EbtlColors.teal
                              : EbtlColors.coral,
                          disabledBackgroundColor: EbtlColors.sand,
                          foregroundColor: Colors.white,
                          elevation: 0,
                          shape: RoundedRectangleBorder(
                            borderRadius: BorderRadius.circular(18),
                          ),
                        ),
                        child: isApplying
                            ? const SizedBox(
                                width: 18,
                                height: 18,
                                child: CircularProgressIndicator(
                                  strokeWidth: 2,
                                  color: Colors.white,
                                ),
                              )
                            : Text(
                                hasPromotion ? 'Remove' : 'Apply',
                                style: GoogleFonts.manrope(
                                  fontWeight: FontWeight.w900,
                                ),
                              ),
                      ),
                    ),
                  ],
                ),
                if (hasPromotion) ...[
                  const SizedBox(height: 10),
                  Row(
                    children: [
                      const Icon(
                        Icons.check_circle,
                        color: EbtlColors.teal,
                        size: 18,
                      ),
                      const SizedBox(width: 8),
                      Expanded(
                        child: Text(
                          '${promotion!.code} applied · ${formatMoney(promotion!.discountAmount, promotion!.currency)} off',
                          style: GoogleFonts.manrope(
                            fontSize: 12,
                            fontWeight: FontWeight.w800,
                            color: EbtlColors.teal,
                          ),
                        ),
                      ),
                    ],
                  ),
                ],
              ],
            ),
          ),
        ],
      ),
    );
  }
}

class CheckoutPaymentMethodSection extends StatelessWidget {
  final List<CheckoutPaymentMethod> methods;
  final String? selectedKey;
  final ValueChanged<String> onSelected;

  const CheckoutPaymentMethodSection({
    super.key,
    required this.methods,
    required this.selectedKey,
    required this.onSelected,
  });

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.fromLTRB(22, 0, 22, 12),
      child: Column(
        children: [
          const CheckoutSectionTitle(title: 'Payment Method'),
          Container(
            decoration: BoxDecoration(
              color: EbtlColors.white.withValues(alpha: 0.92),
              borderRadius: BorderRadius.circular(20),
              border: Border.all(
                color: EbtlColors.coral.withValues(alpha: 0.7),
              ),
            ),
            child: methods.isEmpty
                ? Padding(
                    padding: const EdgeInsets.all(16),
                    child: CheckoutWarningBox(
                      message:
                          'No online payment method is available right now.',
                    ),
                  )
                : Column(
                    children: [
                      for (int index = 0; index < methods.length; index += 1)
                        CheckoutPaymentMethodTile(
                          method: methods[index],
                          selected: methods[index].key == selectedKey,
                          showDivider: index < methods.length - 1,
                          onTap: () => onSelected(methods[index].key),
                        ),
                    ],
                  ),
          ),
        ],
      ),
    );
  }
}

class CheckoutPaymentMethodTile extends StatelessWidget {
  final CheckoutPaymentMethod method;
  final bool selected;
  final bool showDivider;
  final VoidCallback onTap;

  const CheckoutPaymentMethodTile({
    super.key,
    required this.method,
    required this.selected,
    required this.showDivider,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    final icon = method.isApplePay ? Icons.phone_iphone : Icons.credit_card;

    return Material(
      color: Colors.transparent,
      child: InkWell(
        onTap: onTap,
        borderRadius: BorderRadius.vertical(
          top: const Radius.circular(20),
          bottom: Radius.circular(showDivider ? 0 : 20),
        ),
        child: Column(
          children: [
            Padding(
              padding: const EdgeInsets.fromLTRB(16, 14, 16, 14),
              child: Row(
                children: [
                  Container(
                    width: 20,
                    height: 20,
                    decoration: BoxDecoration(
                      shape: BoxShape.circle,
                      border: Border.all(
                        color: selected ? EbtlColors.coral : EbtlColors.muted,
                        width: 1.3,
                      ),
                    ),
                    child: selected
                        ? Center(
                            child: Container(
                              width: 10,
                              height: 10,
                              decoration: const BoxDecoration(
                                color: EbtlColors.coral,
                                shape: BoxShape.circle,
                              ),
                            ),
                          )
                        : null,
                  ),
                  const SizedBox(width: 16),
                  Icon(icon, color: EbtlColors.navy, size: 28),
                  const SizedBox(width: 14),
                  Expanded(
                    child: Text(
                      method.label,
                      style: GoogleFonts.manrope(
                        fontSize: 14,
                        fontWeight: FontWeight.w900,
                        color: EbtlColors.navy,
                      ),
                    ),
                  ),
                  if (method.isCard)
                    Row(
                      children: [
                        Text(
                          'VISA',
                          style: GoogleFonts.manrope(
                            fontSize: 12,
                            fontWeight: FontWeight.w900,
                            color: EbtlColors.navy,
                          ),
                        ),
                        const SizedBox(width: 6),
                        const Icon(
                          Icons.circle,
                          color: EbtlColors.coral,
                          size: 14,
                        ),
                        const Icon(
                          Icons.circle,
                          color: EbtlColors.gold,
                          size: 14,
                        ),
                      ],
                    ),
                ],
              ),
            ),
            if (showDivider)
              Divider(
                height: 1,
                indent: 52,
                endIndent: 16,
                color: EbtlColors.border.withValues(alpha: 0.8),
              ),
          ],
        ),
      ),
    );
  }
}

class CheckoutBlockingReasonsCard extends StatelessWidget {
  final List<String> reasons;
  final VoidCallback onEditCart;

  const CheckoutBlockingReasonsCard({
    super.key,
    required this.reasons,
    required this.onEditCart,
  });

  @override
  Widget build(BuildContext context) {
    if (reasons.isEmpty) return const SizedBox.shrink();

    return Padding(
      padding: const EdgeInsets.fromLTRB(22, 0, 22, 12),
      child: DetailCard(
        backgroundColor: EbtlColors.blush.withValues(alpha: 0.34),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            CheckoutWarningBox(message: reasons.join('\n')),
            const SizedBox(height: 12),
            SizedBox(
              height: 46,
              width: double.infinity,
              child: OutlinedButton.icon(
                onPressed: onEditCart,
                icon: const Icon(Icons.edit_outlined),
                label: const Text('Edit Cart'),
                style: OutlinedButton.styleFrom(
                  foregroundColor: EbtlColors.coral,
                  side: const BorderSide(color: EbtlColors.coral),
                  shape: RoundedRectangleBorder(
                    borderRadius: BorderRadius.circular(16),
                  ),
                  textStyle: GoogleFonts.manrope(fontWeight: FontWeight.w900),
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class CheckoutSummaryCard extends StatelessWidget {
  final CheckoutSummary summary;
  final CheckoutPromotion? promotion;
  final bool canPlaceOrder;
  final bool isPlacingOrder;
  final VoidCallback onPlaceOrder;

  const CheckoutSummaryCard({
    super.key,
    required this.summary,
    required this.promotion,
    required this.canPlaceOrder,
    required this.isPlacingOrder,
    required this.onPlaceOrder,
  });

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.fromLTRB(22, 2, 22, 8),
      child: Column(
        children: [
          const CheckoutSectionTitle(title: 'Summary'),
          DetailCard(
            backgroundColor: EbtlColors.cream.withValues(alpha: 0.55),
            child: Column(
              children: [
                CheckoutSummaryLine(
                  label: 'Subtotal',
                  value: summary.subtotalLabel,
                ),
                const SizedBox(height: 8),
                CheckoutSummaryLine(
                  label: 'Delivery fee',
                  value: summary.deliveryFeeLabel,
                  showInfo: true,
                ),
                if (summary.discountAmount > 0) ...[
                  const SizedBox(height: 8),
                  CheckoutSummaryLine(
                    label: promotion == null
                        ? 'Discount'
                        : 'Discount (${promotion!.code})',
                    value: summary.discountLabel,
                    valueColor: EbtlColors.teal,
                  ),
                ],
                const SizedBox(height: 12),
                Divider(color: EbtlColors.border.withValues(alpha: 0.9)),
                const SizedBox(height: 10),
                Row(
                  children: [
                    Expanded(
                      child: RichText(
                        text: TextSpan(
                          text: 'Total ',
                          style: GoogleFonts.playfairDisplay(
                            fontSize: 20,
                            fontWeight: FontWeight.w800,
                            color: EbtlColors.navy,
                          ),
                          children: [
                            TextSpan(
                              text: '(incl. VAT)',
                              style: GoogleFonts.manrope(
                                fontSize: 12,
                                fontWeight: FontWeight.w700,
                                color: EbtlColors.ink,
                              ),
                            ),
                          ],
                        ),
                      ),
                    ),
                    Text(
                      summary.totalLabel,
                      style: GoogleFonts.playfairDisplay(
                        fontSize: 23,
                        fontWeight: FontWeight.w900,
                        color: EbtlColors.navy,
                      ),
                    ),
                  ],
                ),
                const SizedBox(height: 22),
                SizedBox(
                  width: double.infinity,
                  height: 60,
                  child: ElevatedButton(
                    onPressed: canPlaceOrder && !isPlacingOrder
                        ? onPlaceOrder
                        : null,
                    style: ebtlCoralButtonStyle(withDisabledColors: true),
                    child: isPlacingOrder
                        ? const SizedBox(
                            width: 22,
                            height: 22,
                            child: CircularProgressIndicator(
                              strokeWidth: 2.4,
                              color: Colors.white,
                            ),
                          )
                        : Row(
                            children: [
                              const Icon(Icons.lock_outline, size: 22),
                              const SizedBox(width: 14),
                              Text(
                                'Place Order',
                                style: GoogleFonts.manrope(
                                  fontSize: 16,
                                  fontWeight: FontWeight.w900,
                                ),
                              ),
                              const Spacer(),
                              Text(
                                summary.totalLabel,
                                style: GoogleFonts.manrope(
                                  fontSize: 16,
                                  fontWeight: FontWeight.w900,
                                ),
                              ),
                            ],
                          ),
                  ),
                ),
                const SizedBox(height: 14),
                Row(
                  mainAxisAlignment: MainAxisAlignment.center,
                  children: [
                    const Icon(
                      Icons.verified_user_outlined,
                      size: 18,
                      color: EbtlColors.teal,
                    ),
                    const SizedBox(width: 8),
                    Text(
                      'Secure checkout. Your details are safe with us.',
                      style: GoogleFonts.manrope(
                        fontSize: 12,
                        fontWeight: FontWeight.w700,
                        color: EbtlColors.ink,
                      ),
                    ),
                  ],
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}

class CheckoutSummaryLine extends StatelessWidget {
  final String label;
  final String value;
  final bool showInfo;
  final Color? valueColor;

  const CheckoutSummaryLine({
    super.key,
    required this.label,
    required this.value,
    this.showInfo = false,
    this.valueColor,
  });

  @override
  Widget build(BuildContext context) {
    return Row(
      children: [
        Text(
          label,
          style: GoogleFonts.manrope(
            fontSize: 14,
            fontWeight: FontWeight.w700,
            color: EbtlColors.ink,
          ),
        ),
        if (showInfo) ...[
          const SizedBox(width: 6),
          const Icon(Icons.info_outline, size: 15, color: EbtlColors.muted),
        ],
        const Spacer(),
        Text(
          value,
          style: GoogleFonts.manrope(
            fontSize: 14,
            fontWeight: FontWeight.w900,
            color: valueColor ?? EbtlColors.navy,
          ),
        ),
      ],
    );
  }
}

class CheckoutSectionTitle extends StatelessWidget {
  final String title;
  final String? subtitle;
  final String? actionText;
  final VoidCallback? onAction;

  const CheckoutSectionTitle({
    super.key,
    required this.title,
    this.subtitle,
    this.actionText,
    this.onAction,
  });

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 9),
      child: Row(
        children: [
          Text(
            title,
            style: GoogleFonts.playfairDisplay(
              fontSize: 21,
              height: 1,
              fontWeight: FontWeight.w800,
              color: EbtlColors.navy,
            ),
          ),
          if (subtitle != null) ...[
            const SizedBox(width: 6),
            Text(
              subtitle!,
              style: GoogleFonts.manrope(
                fontSize: 13,
                fontWeight: FontWeight.w800,
                color: EbtlColors.ink,
              ),
            ),
          ],
          const Spacer(),
          if (actionText != null && onAction != null)
            TextButton(
              onPressed: onAction,
              style: TextButton.styleFrom(
                padding: EdgeInsets.zero,
                minimumSize: const Size(40, 30),
                tapTargetSize: MaterialTapTargetSize.shrinkWrap,
              ),
              child: Text(
                actionText!,
                style: GoogleFonts.manrope(
                  fontSize: 13,
                  fontWeight: FontWeight.w900,
                  color: EbtlColors.teal,
                ),
              ),
            ),
        ],
      ),
    );
  }
}

class CheckoutWarningBox extends StatelessWidget {
  final String message;

  const CheckoutWarningBox({super.key, required this.message});

  @override
  Widget build(BuildContext context) {
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: EbtlColors.blush.withValues(alpha: 0.36),
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: EbtlColors.coral.withValues(alpha: 0.25)),
      ),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const Icon(Icons.info_outline, color: EbtlColors.coral, size: 18),
          const SizedBox(width: 8),
          Expanded(
            child: Text(
              message,
              style: GoogleFonts.manrope(
                fontSize: 12,
                height: 1.32,
                fontWeight: FontWeight.w700,
                color: EbtlColors.navy,
              ),
            ),
          ),
        ],
      ),
    );
  }
}

class OrderConfirmedScreen extends StatelessWidget {
  final CheckoutOrder order;
  final CheckoutLocation? location;
  final double? paidAmount;
  final String? paidAmountCurrency;
  final String? paymentStatusOverride;
  final VoidCallback onDone;

  const OrderConfirmedScreen({
    super.key,
    required this.order,
    required this.onDone,
    this.location,
    this.paidAmount,
    this.paidAmountCurrency,
    this.paymentStatusOverride,
  });

  String get paymentStatus {
    final status = paymentStatusOverride?.trim();
    if (status != null && status.isNotEmpty) return status;
    return order.paymentStatus.trim().isEmpty ? 'paid' : order.paymentStatus;
  }

  String get paymentStatusLabel {
    final normalized = paymentStatus.toLowerCase().replaceAll('_', ' ');
    if (normalized == 'paid') return 'Paid';
    if (normalized == 'pending') return 'Pending';
    if (normalized == 'unpaid') return 'Unpaid';
    if (normalized == 'failed') return 'Failed';
    if (normalized == 'refunded') return 'Refunded';
    if (normalized.isEmpty) return 'Paid';
    return normalized[0].toUpperCase() + normalized.substring(1);
  }

  String get pickupLocationName {
    final locationName = location?.name.trim();
    if (locationName != null && locationName.isNotEmpty) return locationName;

    final address = order.address?.trim();
    if (address != null && address.isNotEmpty) return address;

    return 'your selected EBTL cart';
  }

  bool get hasTotalPaid {
    if (order.hasTotals) return true;
    return paidAmount != null;
  }

  String get totalPaidLabel {
    if (order.hasTotals) return order.totals.totalLabel;
    return formatMoney(paidAmount ?? 0, paidAmountCurrency ?? 'EGP');
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: EbtlColors.cream,
      body: Stack(
        children: [
          const Positioned.fill(child: _OrderConfirmedBackground()),
          SafeArea(
            child: LayoutBuilder(
              builder: (context, constraints) {
                final compactHeight = constraints.maxHeight < 720;

                return SingleChildScrollView(
                  padding: EdgeInsets.fromLTRB(
                    28,
                    compactHeight ? 18 : 26,
                    28,
                    22,
                  ),
                  child: ConstrainedBox(
                    constraints: BoxConstraints(
                      minHeight: constraints.maxHeight -
                          (compactHeight ? 40 : 48),
                    ),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.stretch,
                      children: [
                        const _OrderConfirmationLogo(),
                        SizedBox(height: compactHeight ? 18 : 34),
                        Image.asset(
                          OrderConfirmationAssets.headerGraphic,
                          height: compactHeight ? 160 : 218,
                          fit: BoxFit.contain,
                          filterQuality: FilterQuality.high,
                        ),
                        SizedBox(height: compactHeight ? 8 : 18),
                        Text(
                          'Order Confirmed',
                          textAlign: TextAlign.center,
                          style: GoogleFonts.playfairDisplay(
                            fontSize: compactHeight ? 38 : 44,
                            height: 1.02,
                            fontWeight: FontWeight.w800,
                            color: EbtlColors.navy,
                          ),
                        ),
                        const SizedBox(height: 10),
                        Text(
                          'Your payment went through successfully.',
                          textAlign: TextAlign.center,
                          style: GoogleFonts.manrope(
                            fontSize: 18,
                            height: 1.22,
                            fontWeight: FontWeight.w500,
                            color: EbtlColors.navy,
                          ),
                        ),
                        const SizedBox(height: 22),
                        const Center(child: _CoralDash()),
                        const SizedBox(height: 24),
                        Text(
                          'We’ll notify you when your order is ready for pickup.',
                          textAlign: TextAlign.center,
                          style: GoogleFonts.manrope(
                            fontSize: 15.5,
                            height: 1.35,
                            fontWeight: FontWeight.w500,
                            color: EbtlColors.ink.withValues(alpha: 0.78),
                          ),
                        ),
                        SizedBox(height: compactHeight ? 22 : 30),
                        _OrderConfirmationSummaryCard(
                          orderNumber: order.orderNumber,
                          totalPaidLabel: hasTotalPaid ? totalPaidLabel : null,
                          paymentStatusLabel: paymentStatusLabel,
                        ),
                        SizedBox(height: compactHeight ? 22 : 34),
                        Semantics(
                          label:
                              'Preparing your order. Pick up from $pickupLocationName. You’ll receive a notification when it’s ready.',
                          image: true,
                          child: ClipRRect(
                            borderRadius: BorderRadius.circular(24),
                            child: Image.asset(
                              OrderConfirmationAssets.preparingBanner,
                              fit: BoxFit.fitWidth,
                              filterQuality: FilterQuality.high,
                            ),
                          ),
                        ),
                        const SizedBox(height: 30),
                        Text(
                          'Tap Ok to return home.',
                          textAlign: TextAlign.center,
                          style: GoogleFonts.manrope(
                            fontSize: 14.5,
                            fontWeight: FontWeight.w500,
                            color: EbtlColors.ink.withValues(alpha: 0.72),
                          ),
                        ),
                        const SizedBox(height: 18),
                        SizedBox(
                          height: 58,
                          child: ElevatedButton(
                            onPressed: onDone,
                            style: ebtlCoralButtonStyle(
                              radius: 30,
                              shadowColor: Colors.transparent,
                            ),
                            child: Text(
                              'Ok',
                              style: GoogleFonts.manrope(
                                fontSize: 22,
                                fontWeight: FontWeight.w800,
                              ),
                            ),
                          ),
                        ),
                      ],
                    ),
                  ),
                );
              },
            ),
          ),
        ],
      ),
    );
  }
}

class _OrderConfirmedBackground extends StatelessWidget {
  const _OrderConfirmedBackground();

  @override
  Widget build(BuildContext context) {
    return DecoratedBox(
      decoration: BoxDecoration(
        color: EbtlColors.cream,
        gradient: LinearGradient(
          begin: Alignment.topCenter,
          end: Alignment.bottomCenter,
          colors: [
            EbtlColors.cream,
            EbtlColors.white.withValues(alpha: 0.92),
            EbtlColors.cream,
          ],
          stops: const [0, 0.5, 1],
        ),
      ),
      child: Stack(
        children: [
          Positioned(
            top: -110,
            right: -96,
            child: _SoftGlow(
              size: 330,
              color: EbtlColors.gold.withValues(alpha: 0.24),
            ),
          ),
          Positioned(
            top: 250,
            left: -140,
            child: _SoftGlow(
              size: 320,
              color: EbtlColors.blush.withValues(alpha: 0.2),
            ),
          ),
          Positioned(
            bottom: 90,
            right: -150,
            child: _SoftGlow(
              size: 340,
              color: EbtlColors.seafoam.withValues(alpha: 0.24),
            ),
          ),
        ],
      ),
    );
  }
}

class _SoftGlow extends StatelessWidget {
  final double size;
  final Color color;

  const _SoftGlow({required this.size, required this.color});

  @override
  Widget build(BuildContext context) {
    return Container(
      width: size,
      height: size,
      decoration: BoxDecoration(
        shape: BoxShape.circle,
        gradient: RadialGradient(
          colors: [color, color.withValues(alpha: 0)],
        ),
      ),
    );
  }
}

class _OrderConfirmationLogo extends StatelessWidget {
  const _OrderConfirmationLogo();

  @override
  Widget build(BuildContext context) {
    return Align(
      alignment: Alignment.centerLeft,
      child: Transform.scale(
        scale: 0.9,
        alignment: Alignment.centerLeft,
        child: const EbtlLogo(),
      ),
    );
  }
}

class _CoralDash extends StatelessWidget {
  const _CoralDash();

  @override
  Widget build(BuildContext context) {
    return Container(
      width: 34,
      height: 2.5,
      decoration: BoxDecoration(
        color: EbtlColors.coral,
        borderRadius: BorderRadius.circular(999),
      ),
    );
  }
}

class _OrderConfirmationSummaryCard extends StatelessWidget {
  final String orderNumber;
  final String? totalPaidLabel;
  final String paymentStatusLabel;

  const _OrderConfirmationSummaryCard({
    required this.orderNumber,
    required this.totalPaidLabel,
    required this.paymentStatusLabel,
  });

  @override
  Widget build(BuildContext context) {
    final rows = <Widget>[
      _OrderConfirmationInfoRow(
        icon: Icons.receipt_long_outlined,
        iconColor: EbtlColors.coral,
        iconBackground: EbtlColors.blush.withValues(alpha: 0.32),
        label: 'Order Number',
        value: orderNumber,
        valueStyle: GoogleFonts.manrope(
          fontSize: 17,
          fontWeight: FontWeight.w800,
          color: EbtlColors.navy,
        ),
      ),
      if (totalPaidLabel != null) ...[
        const _OrderConfirmationDivider(),
        _OrderConfirmationInfoRow(
          icon: Icons.account_balance_wallet_outlined,
          iconColor: EbtlColors.coral,
          iconBackground: EbtlColors.blush.withValues(alpha: 0.22),
          label: 'Total Paid',
          value: totalPaidLabel!,
          valueStyle: GoogleFonts.manrope(
            fontSize: 29,
            height: 1,
            fontWeight: FontWeight.w900,
            color: EbtlColors.coral,
          ),
        ),
      ],
      const _OrderConfirmationDivider(),
      _OrderConfirmationInfoRow(
        icon: Icons.verified_user_outlined,
        iconColor: EbtlColors.teal,
        iconBackground: EbtlColors.seafoam.withValues(alpha: 0.42),
        label: 'Payment Status',
        trailing: _PaidStatusPill(label: paymentStatusLabel),
      ),
    ];

    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 16),
      decoration: BoxDecoration(
        color: EbtlColors.white.withValues(alpha: 0.88),
        borderRadius: BorderRadius.circular(20),
        border: Border.all(color: EbtlColors.white.withValues(alpha: 0.72)),
        boxShadow: [
          BoxShadow(
            color: EbtlColors.navy.withValues(alpha: 0.07),
            blurRadius: 28,
            offset: const Offset(0, 18),
          ),
          BoxShadow(
            color: EbtlColors.gold.withValues(alpha: 0.08),
            blurRadius: 42,
            offset: const Offset(0, 8),
          ),
        ],
      ),
      child: Column(children: rows),
    );
  }
}

class _OrderConfirmationInfoRow extends StatelessWidget {
  final IconData icon;
  final Color iconColor;
  final Color iconBackground;
  final String label;
  final String? value;
  final TextStyle? valueStyle;
  final Widget? trailing;

  const _OrderConfirmationInfoRow({
    required this.icon,
    required this.iconColor,
    required this.iconBackground,
    required this.label,
    this.value,
    this.valueStyle,
    this.trailing,
  });

  @override
  Widget build(BuildContext context) {
    return minHeightRow(
      minHeight: 64,
      child: Row(
        children: [
          Container(
            width: 54,
            height: 54,
            decoration: BoxDecoration(
              color: iconBackground,
              shape: BoxShape.circle,
            ),
            child: Icon(icon, color: iconColor, size: 26),
          ),
          const SizedBox(width: 18),
          Expanded(
            child: Text(
              label,
              style: GoogleFonts.manrope(
                fontSize: 16,
                height: 1.15,
                fontWeight: FontWeight.w700,
                color: EbtlColors.navy,
              ),
            ),
          ),
          const SizedBox(width: 12),
          if (trailing != null)
            trailing!
          else
            Flexible(
              child: Text(
                value ?? '',
                textAlign: TextAlign.right,
                overflow: TextOverflow.ellipsis,
                maxLines: 1,
                style: valueStyle,
              ),
            ),
        ],
      ),
    );
  }

  Widget minHeightRow({required double minHeight, required Widget child}) {
    return ConstrainedBox(
      constraints: BoxConstraints(minHeight: minHeight),
      child: Center(child: child),
    );
  }
}

class _OrderConfirmationDivider extends StatelessWidget {
  const _OrderConfirmationDivider();

  @override
  Widget build(BuildContext context) {
    return Container(
      height: 1,
      margin: const EdgeInsets.symmetric(vertical: 12),
      color: EbtlColors.border.withValues(alpha: 0.82),
    );
  }
}

class _PaidStatusPill extends StatelessWidget {
  final String label;

  const _PaidStatusPill({required this.label});

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 13, vertical: 8),
      decoration: BoxDecoration(
        color: EbtlColors.seafoam.withValues(alpha: 0.42),
        borderRadius: BorderRadius.circular(999),
        border: Border.all(color: EbtlColors.teal.withValues(alpha: 0.15)),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Container(
            width: 20,
            height: 20,
            decoration: BoxDecoration(
              color: EbtlColors.white.withValues(alpha: 0.55),
              shape: BoxShape.circle,
              border: Border.all(color: EbtlColors.teal.withValues(alpha: 0.7)),
            ),
            child: const Icon(Icons.check_rounded, size: 14, color: EbtlColors.teal),
          ),
          const SizedBox(width: 8),
          Text(
            label,
            style: GoogleFonts.manrope(
              fontSize: 16,
              height: 1,
              fontWeight: FontWeight.w800,
              color: EbtlColors.teal,
            ),
          ),
        ],
      ),
    );
  }
}

class CheckoutResultScreen extends StatelessWidget {
  final PaymentStatusResponse status;
  final VoidCallback onDone;

  const CheckoutResultScreen({
    super.key,
    required this.status,
    required this.onDone,
  });

  @override
  Widget build(BuildContext context) {
    final paid = status.isPaid;
    final failed = status.isFailed;

    final title = paid
        ? 'Order Confirmed'
        : failed
        ? 'Payment Failed'
        : 'Payment Processing';

    final message = paid
        ? 'Your order ${status.orderNumber} is confirmed.'
        : failed
        ? 'Payment failed. Please return to checkout and try again.'
        : 'Your payment is still being confirmed. You can refresh the order status shortly.';

    final icon = paid
        ? Icons.check
        : failed
        ? Icons.close
        : Icons.hourglass_empty;

    final iconColor = paid
        ? EbtlColors.teal
        : failed
        ? EbtlColors.coral
        : EbtlColors.gold;

    return Scaffold(
      backgroundColor: EbtlColors.cream,
      body: SafeArea(
        child: Padding(
          padding: const EdgeInsets.all(22),
          child: Center(
            child: DetailCard(
              child: Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  Container(
                    width: 72,
                    height: 72,
                    decoration: BoxDecoration(
                      color: iconColor.withValues(alpha: 0.14),
                      shape: BoxShape.circle,
                    ),
                    child: Icon(icon, color: iconColor, size: 38),
                  ),
                  const SizedBox(height: 18),
                  Text(
                    title,
                    textAlign: TextAlign.center,
                    style: GoogleFonts.playfairDisplay(
                      fontSize: 34,
                      fontWeight: FontWeight.w800,
                      color: EbtlColors.navy,
                    ),
                  ),
                  const SizedBox(height: 10),
                  Text(
                    message,
                    textAlign: TextAlign.center,
                    style: GoogleFonts.manrope(
                      fontSize: 15,
                      height: 1.4,
                      fontWeight: FontWeight.w600,
                      color: EbtlColors.ink,
                    ),
                  ),
                  const SizedBox(height: 20),
                  SizedBox(
                    width: double.infinity,
                    height: 54,
                    child: ElevatedButton(
                      onPressed: onDone,
                      style: ebtlCoralButtonStyle(),
                      child: Text(
                        'Done',
                        style: GoogleFonts.manrope(fontWeight: FontWeight.w900),
                      ),
                    ),
                  ),
                ],
              ),
            ),
          ),
        ),
      ),
    );
  }
}
