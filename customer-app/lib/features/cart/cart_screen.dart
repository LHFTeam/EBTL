import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';

import '../../core/constants/fulfillment_types.dart';
import '../../core/network/api_exception.dart';
import '../../core/theme/ebtl_colors.dart';
import '../../models/app_data.dart';
import '../../models/cart_models.dart';
import '../../services/api_service.dart';
import '../../shared/widgets/app_state_widgets.dart';
import '../../shared/widgets/brand_widgets.dart';
import '../../shared/widgets/network_or_asset_image.dart';
import '../../shared/widgets/detail_card.dart';

typedef OpenCheckoutCallback =
    void Function({
      required String locationId,
      required String fulfillmentType,
      required VoidCallback onCartChanged,
    });

class CartScreen extends StatefulWidget {
  final AppData data;
  final VoidCallback onOpenFinder;
  final VoidCallback onGoHome;
  final VoidCallback onCartChanged;
  final OpenCheckoutCallback onOpenCheckout;

  const CartScreen({
    super.key,
    required this.data,
    required this.onOpenFinder,
    required this.onGoHome,
    required this.onCartChanged,
    required this.onOpenCheckout,
  });

  @override
  State<CartScreen> createState() => _CartScreenState();
}

class _CartScreenState extends State<CartScreen> {
  String fulfillmentType = FulfillmentTypes.pickupAtCart;
  late Future<CartPageResponse> cartFuture;

  final Set<String> mutatingItemIds = <String>{};
  bool isClearing = false;

  @override
  void initState() {
    super.initState();
    cartFuture = loadCart();
  }

  @override
  void didUpdateWidget(covariant CartScreen oldWidget) {
    super.didUpdateWidget(oldWidget);

    if (oldWidget.data.selectedLocationId != widget.data.selectedLocationId) {
      cartFuture = loadCart();
    }
  }

  Future<CartPageResponse> loadCart() {
    return ApiService.fetchCart(
      locationId: widget.data.selectedLocationId,
      fulfillmentType: fulfillmentType,
    );
  }

  void reloadCart({bool refreshAppData = false}) {
    setState(() {
      cartFuture = loadCart();
    });

    if (refreshAppData) {
      widget.onCartChanged();
    }
  }

  void setFulfillmentType(String value) {
    // Delivery is not launched yet: it is shown as "Coming soon" and is not
    // selectable in the toggle. Guard here as well so it can never become the
    // active fulfillment type even if this is called with it.
    if (value == FulfillmentTypes.deliveryToUnit) return;

    if (value == fulfillmentType) return;

    setState(() {
      fulfillmentType = value;
      cartFuture = loadCart();
    });
  }

  String mutationErrorMessage(Object error) {
    return apiErrorMessage(error, fallback: 'Could not update your cart.');
  }

  Future<void> updateQuantity(CartPageItem item, int quantity) async {
    if (mutatingItemIds.contains(item.id)) return;

    setState(() => mutatingItemIds.add(item.id));

    try {
      await ApiService.updateCartItemQuantity(
        itemId: item.id,
        quantity: quantity.clamp(0, 99),
      );

      if (!mounted) return;
      setState(() => mutatingItemIds.remove(item.id));
      reloadCart(refreshAppData: true);
    } catch (error) {
      if (!mounted) return;
      setState(() => mutatingItemIds.remove(item.id));
      showAppSnackBar(context, mutationErrorMessage(error));
    }
  }

  Future<void> deleteItem(CartPageItem item) async {
    if (mutatingItemIds.contains(item.id)) return;

    setState(() => mutatingItemIds.add(item.id));

    try {
      await ApiService.deleteCartItem(itemId: item.id);

      if (!mounted) return;
      setState(() => mutatingItemIds.remove(item.id));
      reloadCart(refreshAppData: true);
    } catch (error) {
      if (!mounted) return;
      setState(() => mutatingItemIds.remove(item.id));
      showAppSnackBar(context, mutationErrorMessage(error));
    }
  }

  Future<void> clearCart() async {
    if (isClearing) return;

    setState(() => isClearing = true);

    try {
      await ApiService.clearCart();

      if (!mounted) return;
      setState(() => isClearing = false);
      reloadCart(refreshAppData: true);
    } catch (error) {
      if (!mounted) return;
      setState(() => isClearing = false);
      showAppSnackBar(context, mutationErrorMessage(error));
    }
  }

  void proceedToCheckout(CartPageResponse cart) {
    final cartId = cart.cart?.id.trim();
    final locationId = widget.data.selectedLocationId?.trim();

    if (cartId == null || cartId.isEmpty) return;

    if (locationId == null || locationId.isEmpty) {
      showAppSnackBar(context, 'Choose a beach cart first.');
      return;
    }

    widget.onOpenCheckout(
      locationId: locationId,
      fulfillmentType: fulfillmentType,
      onCartChanged: () {
        widget.onCartChanged();
        reloadCart(refreshAppData: false);
      },
    );
  }

  @override
  Widget build(BuildContext context) {
    return SafeArea(
      child: FutureBuilder<CartPageResponse>(
        future: cartFuture,
        builder: (context, snapshot) {
          if (snapshot.connectionState == ConnectionState.waiting) {
            return const CartLoadingState();
          }

          if (snapshot.hasError) {
            return CustomScrollView(
              slivers: [
                SliverToBoxAdapter(
                  child: CartScreenHeader(
                    totalQuantity: widget.data.cartSummary?.totalQuantity ?? 0,
                    onClear: null,
                  ),
                ),
                SliverToBoxAdapter(
                  child: InlineErrorCard(
                    message: snapshot.error.toString(),
                    onRetry: () => reloadCart(),
                  ),
                ),
              ],
            );
          }

          final cart = snapshot.data;

          if (cart == null) {
            return CustomScrollView(
              slivers: [
                SliverToBoxAdapter(
                  child: CartScreenHeader(
                    totalQuantity: widget.data.cartSummary?.totalQuantity ?? 0,
                    onClear: null,
                  ),
                ),
                SliverToBoxAdapter(
                  child: InlineErrorCard(
                    message: 'The backend returned no cart data.',
                    onRetry: () => reloadCart(),
                  ),
                ),
              ],
            );
          }

          final canClear = cart.items.isNotEmpty && !isClearing;

          return CustomScrollView(
            slivers: [
              SliverToBoxAdapter(
                child: CartScreenHeader(
                  totalQuantity: cart.items.fold<int>(
                    0,
                    (sum, item) => sum + item.quantity,
                  ),
                  onClear: canClear ? clearCart : null,
                ),
              ),
              SliverToBoxAdapter(
                child: CartFulfillmentToggle(
                  fulfillmentType: fulfillmentType,
                  onChanged: setFulfillmentType,
                ),
              ),
              SliverToBoxAdapter(
                child: CartLocationCard(
                  location: cart.selectedLocation,
                  fallbackLocationName: widget.data.selectedLocationName,
                  hasSelectedLocation:
                      widget.data.selectedLocationId?.trim().isNotEmpty == true,
                  onChooseLocation: widget.onGoHome,
                ),
              ),
              if (cart.items.isEmpty)
                SliverToBoxAdapter(
                  child: CartEmptyState(
                    reason: cart.checkoutReadiness.firstBlockingReason,
                    onOpenFinder: widget.onOpenFinder,
                  ),
                )
              else ...[
                SliverPadding(
                  padding: const EdgeInsets.fromLTRB(22, 12, 22, 0),
                  sliver: SliverList(
                    delegate: SliverChildBuilderDelegate(
                      (context, index) {
                        if (index.isOdd) return const SizedBox(height: 12);

                        final itemIndex = index ~/ 2;
                        final item = cart.items[itemIndex];
                        final isMutating = mutatingItemIds.contains(item.id);

                        return CartItemCard(
                          item: item,
                          isMutating: isMutating,
                          onIncrement: () =>
                              updateQuantity(item, item.quantity + 1),
                          onDecrement: () =>
                              updateQuantity(item, item.quantity - 1),
                          onDelete: () => deleteItem(item),
                        );
                      },
                      childCount: cart.items.isEmpty
                          ? 0
                          : (cart.items.length * 2) - 1,
                    ),
                  ),
                ),
              ],
              SliverToBoxAdapter(
                child: CartOrderSummaryCard(
                  totals: cart.totals,
                  checkoutReadiness: cart.checkoutReadiness,
                  onCheckout: cart.checkoutReadiness.canCheckout
                      ? () => proceedToCheckout(cart)
                      : null,
                ),
              ),
              const SliverToBoxAdapter(child: SizedBox(height: 24)),
            ],
          );
        },
      ),
    );
  }
}

class CartLoadingState extends StatelessWidget {
  const CartLoadingState({super.key});

  @override
  Widget build(BuildContext context) {
    return CustomScrollView(
      slivers: [
        SliverToBoxAdapter(
          child: CartScreenHeader(totalQuantity: 0, onClear: null),
        ),
        const EbtlLoadingSliver(label: 'Loading your cart...'),
      ],
    );
  }
}

class CartScreenHeader extends StatelessWidget {
  final int totalQuantity;
  final VoidCallback? onClear;

  const CartScreenHeader({
    super.key,
    required this.totalQuantity,
    required this.onClear,
  });

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.fromLTRB(22, 14, 22, 8),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              const EbtlLogo(),
              const Spacer(),
              if (onClear != null)
                TextButton.icon(
                  onPressed: onClear,
                  icon: const Icon(Icons.delete_outline, size: 18),
                  label: const Text('Clear'),
                  style: TextButton.styleFrom(
                    foregroundColor: EbtlColors.coral,
                    textStyle: GoogleFonts.manrope(fontWeight: FontWeight.w900),
                  ),
                ),
            ],
          ),
          const SizedBox(height: 24),
          Row(
            children: [
              Expanded(
                child: Text(
                  'Your Cart',
                  style: GoogleFonts.playfairDisplay(
                    fontSize: 40,
                    height: 1.02,
                    fontWeight: FontWeight.w800,
                    color: EbtlColors.navy,
                  ),
                ),
              ),
              Container(
                padding: const EdgeInsets.symmetric(
                  horizontal: 13,
                  vertical: 8,
                ),
                decoration: BoxDecoration(
                  color: EbtlColors.blush.withValues(alpha: 0.62),
                  borderRadius: BorderRadius.circular(999),
                  border: Border.all(color: EbtlColors.border),
                ),
                child: Text(
                  '$totalQuantity item${totalQuantity == 1 ? '' : 's'}',
                  style: GoogleFonts.manrope(
                    fontSize: 12,
                    color: EbtlColors.navy,
                    fontWeight: FontWeight.w900,
                  ),
                ),
              ),
            ],
          ),
          const SizedBox(height: 8),
          Text(
            'Review your cocktail kits before checkout.',
            style: GoogleFonts.manrope(
              fontSize: 15,
              height: 1.35,
              fontWeight: FontWeight.w600,
              color: EbtlColors.ink,
            ),
          ),
        ],
      ),
    );
  }
}

class CartFulfillmentToggle extends StatelessWidget {
  final String fulfillmentType;
  final ValueChanged<String> onChanged;

  const CartFulfillmentToggle({
    super.key,
    required this.fulfillmentType,
    required this.onChanged,
  });

  @override
  Widget build(BuildContext context) {
    final options = [
      (FulfillmentTypes.pickupAtCart, Icons.storefront_outlined),
      (FulfillmentTypes.deliveryToUnit, Icons.delivery_dining_outlined),
    ];

    return Padding(
      padding: const EdgeInsets.fromLTRB(22, 10, 22, 8),
      child: Container(
        padding: const EdgeInsets.all(6),
        decoration: BoxDecoration(
          color: EbtlColors.white.withValues(alpha: 0.78),
          borderRadius: BorderRadius.circular(22),
          border: Border.all(color: EbtlColors.border),
        ),
        child: Row(
          children: options.map((option) {
            final disabled = option.$1 == FulfillmentTypes.deliveryToUnit;
            final selected = !disabled && fulfillmentType == option.$1;
            final foregroundColor = disabled
                ? EbtlColors.muted
                : selected
                ? Colors.white
                : EbtlColors.navy;

            return Expanded(
              child: GestureDetector(
                onTap: disabled ? null : () => onChanged(option.$1),
                child: Opacity(
                  opacity: disabled ? 0.52 : 1,
                  child: AnimatedContainer(
                    duration: const Duration(milliseconds: 180),
                    padding: const EdgeInsets.symmetric(vertical: 12),
                    decoration: BoxDecoration(
                      color: selected ? EbtlColors.coral : Colors.transparent,
                      borderRadius: BorderRadius.circular(18),
                    ),
                    child: Column(
                      children: [
                        Icon(option.$2, color: foregroundColor),
                        const SizedBox(height: 5),
                        Text(
                          FulfillmentTypes.labelFor(option.$1),
                          textAlign: TextAlign.center,
                          style: GoogleFonts.manrope(
                            fontSize: 12,
                            fontWeight: FontWeight.w900,
                            color: foregroundColor,
                          ),
                        ),
                        if (disabled) ...[
                          const SizedBox(height: 5),
                          Container(
                            padding: const EdgeInsets.symmetric(
                              horizontal: 9,
                              vertical: 3,
                            ),
                            decoration: BoxDecoration(
                              color: EbtlColors.gold.withValues(alpha: 0.28),
                              borderRadius: BorderRadius.circular(999),
                            ),
                            child: Text(
                              'Coming soon',
                              textAlign: TextAlign.center,
                              style: GoogleFonts.manrope(
                                fontSize: 9.5,
                                fontWeight: FontWeight.w900,
                                letterSpacing: 0.3,
                                color: EbtlColors.ink,
                              ),
                            ),
                          ),
                        ],
                      ],
                    ),
                  ),
                ),
              ),
            );
          }).toList(),
        ),
      ),
    );
  }
}

class CartLocationCard extends StatelessWidget {
  final CartLocation? location;
  final String? fallbackLocationName;
  final bool hasSelectedLocation;
  final VoidCallback onChooseLocation;

  const CartLocationCard({
    super.key,
    required this.location,
    required this.fallbackLocationName,
    required this.hasSelectedLocation,
    required this.onChooseLocation,
  });

  @override
  Widget build(BuildContext context) {
    final selectedLocation = location;

    if (!hasSelectedLocation && selectedLocation == null) {
      return Padding(
        padding: const EdgeInsets.fromLTRB(22, 12, 22, 8),
        child: DetailCard(
          backgroundColor: EbtlColors.sand.withValues(alpha: 0.48),
          child: Row(
            children: [
              Container(
                width: 58,
                height: 58,
                decoration: BoxDecoration(
                  color: EbtlColors.white.withValues(alpha: 0.75),
                  borderRadius: BorderRadius.circular(18),
                ),
                child: const Icon(
                  Icons.beach_access_outlined,
                  color: EbtlColors.coral,
                  size: 31,
                ),
              ),
              const SizedBox(width: 14),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      'Choose your beach cart',
                      style: GoogleFonts.manrope(
                        fontSize: 16,
                        fontWeight: FontWeight.w900,
                        color: EbtlColors.navy,
                      ),
                    ),
                    const SizedBox(height: 5),
                    Text(
                      'Select a location so availability and delivery fees stay accurate.',
                      style: GoogleFonts.manrope(
                        fontSize: 13,
                        height: 1.3,
                        fontWeight: FontWeight.w600,
                        color: EbtlColors.ink,
                      ),
                    ),
                  ],
                ),
              ),
              IconButton(
                onPressed: onChooseLocation,
                icon: const Icon(Icons.chevron_right, color: EbtlColors.teal),
              ),
            ],
          ),
        ),
      );
    }

    final locationName =
        selectedLocation?.name ?? fallbackLocationName ?? 'Selected Beach Cart';

    final subtitle = selectedLocation?.subtitle.trim().isNotEmpty == true
        ? selectedLocation!.subtitle.trim()
        : 'Selected location';

    final statusLabel =
        selectedLocation?.currentStatus.label.trim().isNotEmpty == true
        ? selectedLocation!.currentStatus.label.trim()
        : 'Hours unavailable';

    return Padding(
      padding: const EdgeInsets.fromLTRB(22, 12, 22, 8),
      child: Material(
        color: Colors.transparent,
        child: InkWell(
          onTap: onChooseLocation,
          borderRadius: BorderRadius.circular(18),
          child: Ink(
            height: 92,
            decoration: BoxDecoration(
              color: EbtlColors.white.withValues(alpha: 0.94),
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
            child: ClipRRect(
              borderRadius: BorderRadius.circular(18),
              child: Row(
                children: [
                  Expanded(
                    child: Padding(
                      padding: const EdgeInsets.fromLTRB(14, 12, 12, 12),
                      child: Row(
                        children: [
                          const Icon(
                            Icons.location_on_outlined,
                            color: EbtlColors.navy,
                            size: 22,
                          ),
                          const SizedBox(width: 10),
                          Expanded(
                            child: Column(
                              crossAxisAlignment: CrossAxisAlignment.start,
                              mainAxisAlignment: MainAxisAlignment.center,
                              children: [
                                Text(
                                  locationName,
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
                                  subtitle,
                                  maxLines: 1,
                                  overflow: TextOverflow.ellipsis,
                                  style: GoogleFonts.manrope(
                                    fontSize: 11,
                                    fontWeight: FontWeight.w600,
                                    color: EbtlColors.muted,
                                  ),
                                ),
                                const SizedBox(height: 5),
                                Text(
                                  statusLabel,
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
                        ],
                      ),
                    ),
                  ),
                  SizedBox(
                    width: 136,
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
          ),
        ),
      ),
    );
  }
}

class CartItemCard extends StatelessWidget {
  final CartPageItem item;
  final bool isMutating;
  final VoidCallback onIncrement;
  final VoidCallback onDecrement;
  final VoidCallback onDelete;

  const CartItemCard({
    super.key,
    required this.item,
    required this.isMutating,
    required this.onIncrement,
    required this.onDecrement,
    required this.onDelete,
  });

  @override
  Widget build(BuildContext context) {
    const double thumbnailSize = 86;

    final shortDescription = item.product.shortDescription?.trim() ?? '';
    final hasShortDescription = shortDescription.isNotEmpty;

    final customizationSummary = item.customizationSummary;
    final hasCustomizationSummary = customizationSummary != null;

    final availabilityReason = item.availability.reason?.trim() ?? '';
    final hasAvailabilityReason =
        !item.availability.isOrderable && availabilityReason.isNotEmpty;

    return Container(
      decoration: BoxDecoration(
        color: EbtlColors.white.withValues(alpha: 0.92),
        borderRadius: BorderRadius.circular(18),
        border: Border.all(color: EbtlColors.border),
        boxShadow: [
          BoxShadow(
            color: Colors.black.withValues(alpha: 0.03),
            blurRadius: 12,
            offset: const Offset(0, 6),
          ),
        ],
      ),
      child: Padding(
        padding: const EdgeInsets.all(7),
        child: Row(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            ClipRRect(
              borderRadius: BorderRadius.circular(14),
              child: SizedBox(
                width: thumbnailSize,
                height: thumbnailSize,
                child: NetworkOrAssetImage(
                  imageUrl: item.product.imageUrl,
                  asset: item.product.imageAsset,
                  fit: BoxFit.cover,
                ),
              ),
            ),
            const SizedBox(width: 11),
            Expanded(
              child: SizedBox(
                height: thumbnailSize,
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Row(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Expanded(
                          child: Text(
                            item.product.name,
                            maxLines: 1,
                            overflow: TextOverflow.ellipsis,
                            style: GoogleFonts.manrope(
                              fontSize: 14,
                              height: 1.1,
                              fontWeight: FontWeight.w900,
                              color: EbtlColors.navy,
                            ),
                          ),
                        ),
                        SizedBox(
                          width: 26,
                          height: 26,
                          child: IconButton(
                            onPressed: isMutating ? null : onDelete,
                            icon: const Icon(Icons.delete_outline),
                            color: EbtlColors.coral,
                            tooltip: 'Remove',
                            padding: EdgeInsets.zero,
                            iconSize: 19,
                          ),
                        ),
                      ],
                    ),
                    if (hasShortDescription) ...[
                      const SizedBox(height: 2),
                      Text(
                        shortDescription,
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: GoogleFonts.manrope(
                          fontSize: 10.5,
                          height: 1.1,
                          fontWeight: FontWeight.w600,
                          color: EbtlColors.muted,
                        ),
                      ),
                    ],
                    if (hasCustomizationSummary) ...[
                      const SizedBox(height: 2),
                      Text(
                        customizationSummary,
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: GoogleFonts.manrope(
                          fontSize: 10.5,
                          height: 1.1,
                          fontWeight: FontWeight.w800,
                          color: EbtlColors.teal,
                        ),
                      ),
                    ],
                    if (hasAvailabilityReason) ...[
                      const SizedBox(height: 2),
                      Text(
                        availabilityReason,
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: GoogleFonts.manrope(
                          fontSize: 10,
                          height: 1.1,
                          fontWeight: FontWeight.w700,
                          color: EbtlColors.coral,
                        ),
                      ),
                    ],
                    const Spacer(),
                    Row(
                      crossAxisAlignment: CrossAxisAlignment.end,
                      children: [
                        CartQuantityControls(
                          quantity: item.quantity,
                          isMutating: isMutating,
                          onIncrement: onIncrement,
                          onDecrement: onDecrement,
                        ),
                        const Spacer(),
                        if (isMutating)
                          const SizedBox(
                            width: 16,
                            height: 16,
                            child: CircularProgressIndicator(
                              strokeWidth: 2,
                              color: EbtlColors.coral,
                            ),
                          )
                        else
                          Padding(
                            padding: const EdgeInsets.only(bottom: 3),
                            child: Column(
                              crossAxisAlignment: CrossAxisAlignment.end,
                              mainAxisSize: MainAxisSize.min,
                              children: [
                                Text(
                                  '${item.quantity} × ${item.unitPriceLabel}',
                                  maxLines: 1,
                                  overflow: TextOverflow.ellipsis,
                                  style: GoogleFonts.manrope(
                                    fontSize: 10,
                                    fontWeight: FontWeight.w700,
                                    color: EbtlColors.muted,
                                  ),
                                ),
                                const SizedBox(height: 2),
                                Text(
                                  item.lineTotalLabel,
                                  maxLines: 1,
                                  overflow: TextOverflow.ellipsis,
                                  style: GoogleFonts.manrope(
                                    fontSize: 13.5,
                                    fontWeight: FontWeight.w900,
                                    color: EbtlColors.coral,
                                  ),
                                ),
                              ],
                            ),
                          ),
                      ],
                    ),
                  ],
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class CartQuantityControls extends StatelessWidget {
  final int quantity;
  final bool isMutating;
  final VoidCallback onIncrement;
  final VoidCallback onDecrement;

  const CartQuantityControls({
    super.key,
    required this.quantity,
    required this.isMutating,
    required this.onIncrement,
    required this.onDecrement,
  });

  @override
  Widget build(BuildContext context) {
    return Container(
      height: 30,
      decoration: BoxDecoration(
        color: EbtlColors.cream,
        borderRadius: BorderRadius.circular(999),
        border: Border.all(color: EbtlColors.border),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          SizedBox(
            width: 32,
            child: IconButton(
              onPressed: isMutating ? null : onDecrement,
              icon: Icon(quantity <= 1 ? Icons.delete_outline : Icons.remove),
              color: EbtlColors.navy,
              iconSize: 16,
              padding: EdgeInsets.zero,
            ),
          ),
          Container(
            width: 34,
            alignment: Alignment.center,
            decoration: const BoxDecoration(
              border: Border.symmetric(
                vertical: BorderSide(color: EbtlColors.border),
              ),
            ),
            child: Text(
              quantity.toString(),
              style: GoogleFonts.manrope(
                fontSize: 13,
                fontWeight: FontWeight.w900,
                color: EbtlColors.navy,
              ),
            ),
          ),
          SizedBox(
            width: 32,
            child: IconButton(
              onPressed: isMutating || quantity >= 99 ? null : onIncrement,
              icon: const Icon(Icons.add),
              color: EbtlColors.navy,
              iconSize: 16,
              padding: EdgeInsets.zero,
            ),
          ),
        ],
      ),
    );
  }
}

class CartEmptyState extends StatelessWidget {
  final String? reason;
  final VoidCallback onOpenFinder;

  const CartEmptyState({
    super.key,
    required this.reason,
    required this.onOpenFinder,
  });

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.fromLTRB(22, 18, 22, 8),
      child: Container(
        width: double.infinity,
        padding: const EdgeInsets.all(22),
        decoration: BoxDecoration(
          color: EbtlColors.white.withValues(alpha: 0.88),
          borderRadius: BorderRadius.circular(24),
          border: Border.all(color: EbtlColors.border),
        ),
        child: Column(
          children: [
            Container(
              width: 72,
              height: 72,
              decoration: BoxDecoration(
                color: EbtlColors.blush.withValues(alpha: 0.54),
                shape: BoxShape.circle,
              ),
              child: const Icon(
                Icons.shopping_cart_outlined,
                color: EbtlColors.navy,
                size: 34,
              ),
            ),
            const SizedBox(height: 16),
            Text(
              'Your cart is empty',
              textAlign: TextAlign.center,
              style: GoogleFonts.playfairDisplay(
                fontSize: 30,
                fontWeight: FontWeight.w800,
                color: EbtlColors.navy,
              ),
            ),
            const SizedBox(height: 8),
            Text(
              reason?.trim().isNotEmpty == true
                  ? reason!.trim()
                  : 'Add a cocktail kit to start your beachside order.',
              textAlign: TextAlign.center,
              style: GoogleFonts.manrope(
                fontSize: 14,
                height: 1.4,
                fontWeight: FontWeight.w600,
                color: EbtlColors.ink,
              ),
            ),
            const SizedBox(height: 18),
            SizedBox(
              width: double.infinity,
              height: 54,
              child: ElevatedButton.icon(
                onPressed: onOpenFinder,
                icon: const Icon(Icons.local_bar_outlined),
                label: const Text('Find Cocktails'),
                style: ebtlCoralButtonStyle(
                  textStyle: GoogleFonts.manrope(
                    fontSize: 15,
                    fontWeight: FontWeight.w900,
                  ),
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class CartOrderSummaryCard extends StatelessWidget {
  final CartTotals totals;
  final CheckoutReadiness checkoutReadiness;
  final VoidCallback? onCheckout;

  const CartOrderSummaryCard({
    super.key,
    required this.totals,
    required this.checkoutReadiness,
    required this.onCheckout,
  });

  @override
  Widget build(BuildContext context) {
    final blockingReason = checkoutReadiness.firstBlockingReason;

    return Padding(
      padding: const EdgeInsets.fromLTRB(22, 18, 22, 8),
      child: Container(
        width: double.infinity,
        padding: const EdgeInsets.all(18),
        decoration: BoxDecoration(
          color: EbtlColors.navy,
          borderRadius: BorderRadius.circular(24),
          boxShadow: [
            BoxShadow(
              color: Colors.black.withValues(alpha: 0.10),
              blurRadius: 22,
              offset: const Offset(0, 10),
            ),
          ],
        ),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              'Order Summary',
              style: GoogleFonts.manrope(
                fontSize: 18,
                fontWeight: FontWeight.w900,
                color: Colors.white,
              ),
            ),
            const SizedBox(height: 16),
            CartSummaryRow(label: 'Subtotal', value: totals.subtotalLabel),
            const SizedBox(height: 10),
            CartSummaryRow(
              label: 'Delivery Fee',
              value: totals.deliveryFeeLabel,
            ),
            const SizedBox(height: 12),
            Divider(color: Colors.white.withValues(alpha: 0.20)),
            const SizedBox(height: 12),
            CartSummaryRow(
              label: 'Total (incl. VAT)',
              value: totals.totalLabel,
              isTotal: true,
            ),
            if (!checkoutReadiness.canCheckout &&
                blockingReason != null &&
                blockingReason.trim().isNotEmpty) ...[
              const SizedBox(height: 14),
              Container(
                width: double.infinity,
                padding: const EdgeInsets.all(12),
                decoration: BoxDecoration(
                  color: EbtlColors.sand.withValues(alpha: 0.14),
                  borderRadius: BorderRadius.circular(16),
                  border: Border.all(
                    color: Colors.white.withValues(alpha: 0.16),
                  ),
                ),
                child: Row(
                  children: [
                    const Icon(
                      Icons.info_outline,
                      color: EbtlColors.blush,
                      size: 18,
                    ),
                    const SizedBox(width: 8),
                    Expanded(
                      child: Text(
                        blockingReason,
                        style: GoogleFonts.manrope(
                          fontSize: 12,
                          height: 1.3,
                          fontWeight: FontWeight.w700,
                          color: Colors.white,
                        ),
                      ),
                    ),
                  ],
                ),
              ),
            ],
            const SizedBox(height: 18),
            SizedBox(
              width: double.infinity,
              height: 58,
              child: ElevatedButton.icon(
                onPressed: onCheckout,
                icon: const Icon(Icons.lock_outline),
                label: const Text('Proceed to Checkout'),
                style: ebtlCoralButtonStyle(
                  withDisabledColors: true,
                  textStyle: GoogleFonts.manrope(
                    fontSize: 16,
                    fontWeight: FontWeight.w900,
                  ),
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class CartSummaryRow extends StatelessWidget {
  final String label;
  final String value;
  final bool isTotal;

  const CartSummaryRow({
    super.key,
    required this.label,
    required this.value,
    this.isTotal = false,
  });

  @override
  Widget build(BuildContext context) {
    return Row(
      children: [
        Expanded(
          child: Text(
            label,
            style: GoogleFonts.manrope(
              fontSize: isTotal ? 16 : 14,
              fontWeight: isTotal ? FontWeight.w900 : FontWeight.w700,
              color: Colors.white.withValues(alpha: isTotal ? 1 : 0.75),
            ),
          ),
        ),
        Text(
          value,
          style: GoogleFonts.manrope(
            fontSize: isTotal ? 20 : 15,
            fontWeight: FontWeight.w900,
            color: isTotal ? EbtlColors.gold : Colors.white,
          ),
        ),
      ],
    );
  }
}
