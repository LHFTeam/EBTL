import 'package:flutter/material.dart';
// OverflowBoxFit is defined in the rendering layer and is not re-exported
// through material.dart, so import just that symbol.
import 'package:flutter/rendering.dart' show OverflowBoxFit;
import 'package:google_fonts/google_fonts.dart';

import '../../core/constants/fulfillment_types.dart';
import '../../core/constants/order_confirmation_assets.dart';
import '../../core/theme/ebtl_colors.dart';
import '../../core/utils/formatters.dart';
import '../../models/checkout_models.dart';
import '../../models/referral_models.dart';
import '../../services/api_service.dart';
import '../../shared/widgets/brand_widgets.dart';
import '../../shared/widgets/network_or_asset_image.dart';
import '../auth/social_sign_in_card.dart';
import '../profile/order_detail_screen.dart';

/*
  The screen the customer lands on the moment their money has gone through.

  It carries three jobs, in this order:

  1. Reassure — the order exists, it is paid, and here is where and when it
     lands. Everything on this screen came back with place-order, so none of it
     costs a request.
  2. Receipt — what they bought, at the prices they paid. These are the stored
     snapshots off `order_items`, not today's menu.
  3. Keep the account — the one moment the app asks a customer to sign in. It
     asks here rather than before checkout deliberately: an account wall in
     front of an order is the single most-cited fixable cause of checkout
     abandonment, and by this point every field the account needs is already
     known.

  Nothing here may gate the order. A customer who ignores the sign-in card has
  lost nothing, and the screen must read as complete without it.
*/

class OrderConfirmedScreen extends StatefulWidget {
  final CheckoutOrder order;

  /// The lines this order was placed with. Empty is a legitimate state — an
  /// order recovered by the idempotent replay of place-order has no items on
  /// its response — and the receipt simply omits the itemisation then.
  final List<PlacedOrderItem> items;

  /// The beach cart the checkout screen was drawn with, used only when the
  /// order payload did not carry its own.
  final CheckoutLocation? location;

  /// Set when the checkout screen knew the fulfilment type but the order
  /// payload came back without one.
  final String? fulfillmentTypeOverride;
  final double? paidAmount;
  final String? paidAmountCurrency;
  final String? paymentStatusOverride;
  final VoidCallback onDone;

  const OrderConfirmedScreen({
    super.key,
    required this.order,
    required this.onDone,
    this.items = const [],
    this.location,
    this.fulfillmentTypeOverride,
    this.paidAmount,
    this.paidAmountCurrency,
    this.paymentStatusOverride,
  });

  @override
  State<OrderConfirmedScreen> createState() => _OrderConfirmedScreenState();
}

class _OrderConfirmedScreenState extends State<OrderConfirmedScreen> {
  final ScrollController _scrollController = ScrollController();

  /// The referral strip is the one piece of this screen that needs the network.
  /// It is loaded quietly and stays hidden if the call fails — a customer who
  /// just paid should not be shown an error about a bonus.
  ReferralHub? referral;

  @override
  void initState() {
    super.initState();
    _loadReferral();
  }

  @override
  void dispose() {
    _scrollController.dispose();
    super.dispose();
  }

  Future<void> _loadReferral() async {
    try {
      final hub = await ApiService.fetchReferralHub();
      if (!mounted) return;
      if (!hub.programActive || (hub.code ?? '').trim().isEmpty) return;
      setState(() => referral = hub);
    } catch (_) {
      // Best-effort: the confirmation is complete without it.
    }
  }

  String get paymentStatus {
    final status = widget.paymentStatusOverride?.trim();
    if (status != null && status.isNotEmpty) return status;
    return widget.order.paymentStatus.trim().isEmpty
        ? 'paid'
        : widget.order.paymentStatus;
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

  bool get isPaid => paymentStatus.toLowerCase() == 'paid';

  /// Prefer the order's own location: it is what the order recorded, where the
  /// screen's copy is only what the customer had selected when they paid.
  CheckoutLocation? get location => widget.order.location ?? widget.location;

  bool get isDelivery {
    final type = widget.order.fulfillmentType.trim().isEmpty
        ? (widget.fulfillmentTypeOverride ?? '')
        : widget.order.fulfillmentType;

    return type == FulfillmentTypes.deliveryToUnit;
  }

  String get destinationName {
    if (isDelivery) {
      final address = widget.order.address?.trim();
      if (address != null && address.isNotEmpty) return address;
      return 'your unit';
    }

    final locationName = location?.name.trim();
    if (locationName != null && locationName.isNotEmpty) return locationName;

    return 'your selected EBTL cart';
  }

  String get headlineMessage {
    if (!isPaid) {
      return 'We’ll confirm your payment and start on your order as soon as it '
          'clears.';
    }

    return isDelivery
        ? 'We’ll notify you when it’s on the way to $destinationName.'
        : 'We’ll notify you when it’s ready at $destinationName.';
  }

  bool get hasTotalPaid {
    if (widget.order.hasTotals) return true;
    return widget.paidAmount != null;
  }

  String get currency {
    if (widget.order.hasTotals) return widget.order.totals.currency;
    return widget.paidAmountCurrency ?? 'EGP';
  }

  String get totalPaidLabel {
    if (widget.order.hasTotals) return widget.order.totals.totalLabel;
    return formatMoney(widget.paidAmount ?? 0, currency);
  }

  void openOrderDetail() {
    Navigator.of(context).push(
      MaterialPageRoute(
        builder: (_) => OrderDetailScreen(
          orderId: widget.order.id,
          orderNumber: widget.order.orderNumber,
        ),
      ),
    );
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
                  controller: _scrollController,
                  primary: false,
                  keyboardDismissBehavior:
                      ScrollViewKeyboardDismissBehavior.onDrag,
                  padding: EdgeInsets.fromLTRB(
                    28,
                    compactHeight ? 18 : 26,
                    28,
                    22,
                  ),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.stretch,
                    children: [
                      const _OrderConfirmationLogo(),
                      SizedBox(height: compactHeight ? 18 : 34),
                      OverflowBox(
                        maxWidth: constraints.maxWidth,
                        // The scroll view leaves height unbounded, so the
                        // default OverflowBoxFit.max would try to size this
                        // box to infinity and throw during layout. Defer to
                        // the child so it takes the image's finite height
                        // while still bleeding to full screen width.
                        fit: OverflowBoxFit.deferToChild,
                        child: Image.asset(
                          OrderConfirmationAssets.headerGraphic,
                          width: constraints.maxWidth,
                          fit: BoxFit.fitWidth,
                          filterQuality: FilterQuality.high,
                        ),
                      ),
                      SizedBox(height: compactHeight ? 8 : 18),
                      Text(
                        isPaid ? 'Order Confirmed' : 'Order Placed',
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
                        isPaid
                            ? 'Your payment went through successfully.'
                            : 'Your order is in — we’re waiting on the bank.',
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
                        headlineMessage,
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
                        orderNumber: widget.order.orderNumber,
                        totalPaidLabel: hasTotalPaid ? totalPaidLabel : null,
                        paymentStatusLabel: paymentStatusLabel,
                        isPaid: isPaid,
                      ),
                      const SizedBox(height: 18),
                      _FulfillmentCard(
                        isDelivery: isDelivery,
                        location: location,
                        address: widget.order.address,
                        requestedFulfillmentAt:
                            widget.order.requestedFulfillmentAt,
                      ),
                      if (widget.items.isNotEmpty) ...[
                        const SizedBox(height: 18),
                        _OrderReceiptCard(
                          items: widget.items,
                          totals: widget.order.hasTotals
                              ? widget.order.totals
                              : null,
                          currency: currency,
                          promotionCode: widget.order.promotion?.code,
                        ),
                      ],
                      const SizedBox(height: 18),
                      SocialSignInCard(orderNumber: widget.order.orderNumber),
                      if (referral != null) ...[
                        const SizedBox(height: 18),
                        _ReferralStrip(hub: referral!),
                      ],
                      SizedBox(height: compactHeight ? 22 : 30),
                      Semantics(
                        label: isDelivery
                            ? 'Preparing your order for delivery to $destinationName.'
                            : 'Preparing your order. Pick up from $destinationName. '
                                  'You’ll receive a notification when it’s ready.',
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
                      const SizedBox(height: 26),
                      SizedBox(
                        height: 58,
                        child: ElevatedButton(
                          onPressed: openOrderDetail,
                          style: ebtlCoralButtonStyle(
                            radius: 30,
                            shadowColor: Colors.transparent,
                          ),
                          child: Text(
                            'Track my order',
                            style: GoogleFonts.manrope(
                              fontSize: 20,
                              fontWeight: FontWeight.w800,
                            ),
                          ),
                        ),
                      ),
                      const SizedBox(height: 10),
                      TextButton(
                        onPressed: widget.onDone,
                        style: TextButton.styleFrom(
                          foregroundColor: EbtlColors.navy,
                          minimumSize: const Size.fromHeight(52),
                        ),
                        child: Text(
                          'Back to home',
                          style: GoogleFonts.manrope(
                            fontSize: 16,
                            fontWeight: FontWeight.w800,
                          ),
                        ),
                      ),
                    ],
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
        gradient: RadialGradient(colors: [color, color.withValues(alpha: 0)]),
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

/// The card shape the whole screen is built from: a near-white pane floating on
/// the cream ground, warmed by a gold underglow.
class OrderConfirmationPane extends StatelessWidget {
  final Widget child;
  final EdgeInsetsGeometry padding;

  const OrderConfirmationPane({
    super.key,
    required this.child,
    this.padding = const EdgeInsets.symmetric(horizontal: 20, vertical: 16),
  });

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: padding,
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
      child: child,
    );
  }
}

class _OrderConfirmationSummaryCard extends StatelessWidget {
  final String orderNumber;
  final String? totalPaidLabel;
  final String paymentStatusLabel;
  final bool isPaid;

  const _OrderConfirmationSummaryCard({
    required this.orderNumber,
    required this.totalPaidLabel,
    required this.paymentStatusLabel,
    required this.isPaid,
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
        const OrderConfirmationDivider(),
        _OrderConfirmationInfoRow(
          icon: Icons.account_balance_wallet_outlined,
          iconColor: EbtlColors.coral,
          iconBackground: EbtlColors.blush.withValues(alpha: 0.22),
          label: 'Total Paid',
          trailing: _TotalPaidValue(value: totalPaidLabel!),
        ),
      ],
      const OrderConfirmationDivider(),
      _OrderConfirmationInfoRow(
        icon: Icons.verified_user_outlined,
        iconColor: isPaid ? EbtlColors.teal : EbtlColors.gold,
        iconBackground: isPaid
            ? EbtlColors.seafoam.withValues(alpha: 0.42)
            : EbtlColors.gold.withValues(alpha: 0.18),
        label: 'Payment Status',
        trailing: _PaidStatusPill(label: paymentStatusLabel, isPaid: isPaid),
      ),
    ];

    return OrderConfirmationPane(child: Column(children: rows));
  }
}

/// Where the order lands and when.
///
/// Pickup and delivery are genuinely different answers, not one answer with a
/// word swapped: a pickup customer needs the cart's name and beach, a delivery
/// customer needs the address they typed read back to them.
class _FulfillmentCard extends StatelessWidget {
  final bool isDelivery;
  final CheckoutLocation? location;
  final String? address;
  final String? requestedFulfillmentAt;

  const _FulfillmentCard({
    required this.isDelivery,
    required this.location,
    required this.address,
    required this.requestedFulfillmentAt,
  });

  @override
  Widget build(BuildContext context) {
    final cart = location;
    final trimmedAddress = address?.trim() ?? '';
    final scheduled = requestedFulfillmentAt?.trim() ?? '';

    final rows = <Widget>[];

    if (isDelivery) {
      rows.add(
        _OrderConfirmationInfoRow(
          icon: Icons.delivery_dining_outlined,
          iconColor: EbtlColors.teal,
          iconBackground: EbtlColors.seafoam.withValues(alpha: 0.42),
          label: 'Delivering to',
          stackedValue: trimmedAddress.isEmpty ? 'Your unit' : trimmedAddress,
          stackedSubtitle: cart?.name,
        ),
      );
    } else {
      rows.add(
        _OrderConfirmationInfoRow(
          icon: Icons.storefront_outlined,
          iconColor: EbtlColors.teal,
          iconBackground: EbtlColors.seafoam.withValues(alpha: 0.42),
          label: 'Pick up from',
          stackedValue: cart?.name ?? 'Your selected beach cart',
          stackedSubtitle: cart?.subtitle,
          trailing: cart == null
              ? null
              : ClipRRect(
                  borderRadius: BorderRadius.circular(14),
                  child: SizedBox(
                    width: 64,
                    height: 54,
                    child: NetworkOrAssetImage(
                      imageUrl: cart.bannerImageUrl,
                      asset: 'assets/images/location_banner_placeholder.jpg',
                      fit: BoxFit.cover,
                    ),
                  ),
                ),
        ),
      );
    }

    rows
      ..add(const OrderConfirmationDivider())
      ..add(
        _OrderConfirmationInfoRow(
          icon: Icons.schedule_outlined,
          iconColor: EbtlColors.gold,
          iconBackground: EbtlColors.gold.withValues(alpha: 0.16),
          label: scheduled.isEmpty ? 'Ready' : 'Ready by',
          value: scheduled.isEmpty
              ? 'As soon as possible'
              : formatProfileDateTime(scheduled),
          valueStyle: GoogleFonts.manrope(
            fontSize: 15,
            fontWeight: FontWeight.w800,
            color: EbtlColors.navy,
          ),
        ),
      );

    return OrderConfirmationPane(child: Column(children: rows));
  }
}

/// What they bought, at the prices they paid.
class _OrderReceiptCard extends StatelessWidget {
  final List<PlacedOrderItem> items;
  final CheckoutSummary? totals;
  final String currency;
  final String? promotionCode;

  const _OrderReceiptCard({
    required this.items,
    required this.totals,
    required this.currency,
    required this.promotionCode,
  });

  @override
  Widget build(BuildContext context) {
    final summary = totals;
    final code = promotionCode?.trim() ?? '';

    return OrderConfirmationPane(
      padding: const EdgeInsets.fromLTRB(20, 18, 20, 18),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Row(
            children: [
              Expanded(
                child: Text(
                  'Your order',
                  style: GoogleFonts.manrope(
                    fontSize: 16,
                    fontWeight: FontWeight.w900,
                    color: EbtlColors.navy,
                  ),
                ),
              ),
              Text(
                items.length == 1 ? '1 item' : '${items.length} items',
                style: GoogleFonts.manrope(
                  fontSize: 13,
                  fontWeight: FontWeight.w700,
                  color: EbtlColors.muted,
                ),
              ),
            ],
          ),
          const SizedBox(height: 6),
          for (final item in items)
            _ReceiptItemRow(item: item, currency: currency),
          if (summary != null) ...[
            const OrderConfirmationDivider(),
            _ReceiptTotalRow(
              label: 'Subtotal',
              value: summary.subtotalLabel,
            ),
            if (summary.discountAmount > 0)
              _ReceiptTotalRow(
                label: code.isEmpty ? 'Discount' : 'Promo · $code',
                value: summary.discountLabel,
                valueColor: EbtlColors.teal,
              ),
            if (summary.hasReferralDiscount)
              _ReceiptTotalRow(
                label: 'Referral discount',
                value: summary.referralDiscountLabel,
                valueColor: EbtlColors.teal,
              ),
            if (summary.hasCreditApplied)
              _ReceiptTotalRow(
                label: 'Store credit',
                value: summary.creditAppliedLabel,
                valueColor: EbtlColors.teal,
              ),
            if (summary.deliveryFee > 0)
              _ReceiptTotalRow(
                label: 'Delivery',
                value: summary.deliveryFeeLabel,
              ),
            const OrderConfirmationDivider(),
            _ReceiptTotalRow(
              label: 'Total',
              value: summary.totalLabel,
              isTotal: true,
            ),
            if (summary.vatIncluded)
              Padding(
                padding: const EdgeInsets.only(top: 6),
                child: Text(
                  'VAT included',
                  style: GoogleFonts.manrope(
                    fontSize: 12,
                    fontWeight: FontWeight.w600,
                    color: EbtlColors.muted,
                  ),
                ),
              ),
          ],
        ],
      ),
    );
  }
}

class _ReceiptItemRow extends StatelessWidget {
  final PlacedOrderItem item;
  final String currency;

  const _ReceiptItemRow({required this.item, required this.currency});

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 10),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Container(
            width: 34,
            height: 34,
            alignment: Alignment.center,
            decoration: BoxDecoration(
              color: EbtlColors.sand.withValues(alpha: 0.55),
              borderRadius: BorderRadius.circular(12),
            ),
            child: Text(
              '${item.quantity}×',
              style: GoogleFonts.manrope(
                fontSize: 13,
                fontWeight: FontWeight.w900,
                color: EbtlColors.navy,
              ),
            ),
          ),
          const SizedBox(width: 12),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  item.productName,
                  style: GoogleFonts.manrope(
                    fontSize: 15,
                    height: 1.25,
                    fontWeight: FontWeight.w800,
                    color: EbtlColors.navy,
                  ),
                ),
                if (item.hasVariant)
                  Text(
                    item.variantName!,
                    style: GoogleFonts.manrope(
                      fontSize: 12.5,
                      fontWeight: FontWeight.w600,
                      color: EbtlColors.muted,
                    ),
                  ),
                if (item.hasCustomization)
                  Padding(
                    padding: const EdgeInsets.only(top: 3),
                    child: Text(
                      item.customizationSummary!,
                      style: GoogleFonts.manrope(
                        fontSize: 12.5,
                        height: 1.3,
                        fontWeight: FontWeight.w600,
                        color: EbtlColors.coral,
                      ),
                    ),
                  ),
              ],
            ),
          ),
          const SizedBox(width: 10),
          Text(
            item.lineTotalLabel(currency),
            style: GoogleFonts.manrope(
              fontSize: 14.5,
              fontWeight: FontWeight.w800,
              color: EbtlColors.navy,
            ),
          ),
        ],
      ),
    );
  }
}

class _ReceiptTotalRow extends StatelessWidget {
  final String label;
  final String value;
  final Color? valueColor;
  final bool isTotal;

  const _ReceiptTotalRow({
    required this.label,
    required this.value,
    this.valueColor,
    this.isTotal = false,
  });

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 4),
      child: Row(
        children: [
          Expanded(
            child: Text(
              label,
              style: GoogleFonts.manrope(
                fontSize: isTotal ? 16 : 14,
                fontWeight: isTotal ? FontWeight.w900 : FontWeight.w600,
                color: isTotal ? EbtlColors.navy : EbtlColors.ink,
              ),
            ),
          ),
          const SizedBox(width: 12),
          Text(
            value,
            style: GoogleFonts.manrope(
              fontSize: isTotal ? 18 : 14,
              fontWeight: isTotal ? FontWeight.w900 : FontWeight.w700,
              color: valueColor ?? (isTotal ? EbtlColors.coral : EbtlColors.navy),
            ),
          ),
        ],
      ),
    );
  }
}

/// The referral bonus, sold at the moment the customer is most likely to pass
/// the app on: they have just had a good experience with it.
class _ReferralStrip extends StatelessWidget {
  final ReferralHub hub;

  const _ReferralStrip({required this.hub});

  @override
  Widget build(BuildContext context) {
    final code = hub.code ?? '';

    return OrderConfirmationPane(
      padding: const EdgeInsets.fromLTRB(20, 18, 20, 18),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Container(
            width: 46,
            height: 46,
            decoration: BoxDecoration(
              color: EbtlColors.gold.withValues(alpha: 0.18),
              shape: BoxShape.circle,
            ),
            child: const Icon(
              Icons.card_giftcard_outlined,
              color: EbtlColors.gold,
              size: 24,
            ),
          ),
          const SizedBox(width: 14),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  'Share EBTL, earn ${hub.rewards.referrerRewardLabel}',
                  style: GoogleFonts.manrope(
                    fontSize: 15,
                    height: 1.25,
                    fontWeight: FontWeight.w900,
                    color: EbtlColors.navy,
                  ),
                ),
                const SizedBox(height: 4),
                Text(
                  'They get ${hub.rewards.refereeRewardLabel} on their first '
                  'order. Your code is $code.',
                  style: GoogleFonts.manrope(
                    fontSize: 13,
                    height: 1.35,
                    fontWeight: FontWeight.w600,
                    color: EbtlColors.ink.withValues(alpha: 0.8),
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

class _OrderConfirmationInfoRow extends StatelessWidget {
  final IconData icon;
  final Color iconColor;
  final Color iconBackground;
  final String label;
  final String? value;
  final TextStyle? valueStyle;
  final Widget? trailing;

  /// When set, the row reads as a label above a value rather than a label with
  /// the value pushed to the right — the shape a beach cart name or a street
  /// address needs, since neither fits on one line beside its label.
  final String? stackedValue;
  final String? stackedSubtitle;

  const _OrderConfirmationInfoRow({
    required this.icon,
    required this.iconColor,
    required this.iconBackground,
    required this.label,
    this.value,
    this.valueStyle,
    this.trailing,
    this.stackedValue,
    this.stackedSubtitle,
  });

  @override
  Widget build(BuildContext context) {
    final stacked = stackedValue;
    final subtitle = stackedSubtitle?.trim() ?? '';

    return ConstrainedBox(
      constraints: const BoxConstraints(minHeight: 64),
      child: Center(
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
            if (stacked != null)
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Text(
                      label,
                      style: GoogleFonts.manrope(
                        fontSize: 12.5,
                        height: 1.2,
                        fontWeight: FontWeight.w700,
                        color: EbtlColors.muted,
                      ),
                    ),
                    const SizedBox(height: 3),
                    Text(
                      stacked,
                      style: GoogleFonts.manrope(
                        fontSize: 16,
                        height: 1.2,
                        fontWeight: FontWeight.w800,
                        color: EbtlColors.navy,
                      ),
                    ),
                    if (subtitle.isNotEmpty)
                      Padding(
                        padding: const EdgeInsets.only(top: 2),
                        child: Text(
                          subtitle,
                          style: GoogleFonts.manrope(
                            fontSize: 12.5,
                            height: 1.25,
                            fontWeight: FontWeight.w600,
                            color: EbtlColors.muted,
                          ),
                        ),
                      ),
                  ],
                ),
              )
            else
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
            else if (stacked == null)
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
      ),
    );
  }
}

class _TotalPaidValue extends StatelessWidget {
  final String value;

  const _TotalPaidValue({required this.value});

  @override
  Widget build(BuildContext context) {
    final style = GoogleFonts.manrope(
      fontSize: 17,
      height: 1.15,
      fontWeight: FontWeight.w800,
      color: EbtlColors.coral,
    );
    final separatorIndex = value.indexOf(' ');

    return Flexible(
      child: LayoutBuilder(
        builder: (context, constraints) {
          final textPainter = TextPainter(
            text: TextSpan(text: value, style: style),
            maxLines: 1,
            textDirection: TextDirection.ltr,
          )..layout(maxWidth: constraints.maxWidth);

          if (!textPainter.didExceedMaxLines) {
            return Text(
              value,
              maxLines: 1,
              textAlign: TextAlign.right,
              style: style,
            );
          }

          if (separatorIndex < 0) {
            return FittedBox(
              fit: BoxFit.scaleDown,
              alignment: Alignment.centerRight,
              child: Text(value, maxLines: 1, style: style),
            );
          }

          final currency = value.substring(0, separatorIndex);
          final amount = value.substring(separatorIndex + 1).trimLeft();
          return Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(currency, maxLines: 1, style: style),
              FittedBox(
                fit: BoxFit.scaleDown,
                alignment: Alignment.centerLeft,
                child: Text(amount, maxLines: 1, style: style),
              ),
            ],
          );
        },
      ),
    );
  }
}

class OrderConfirmationDivider extends StatelessWidget {
  const OrderConfirmationDivider({super.key});

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
  final bool isPaid;

  const _PaidStatusPill({required this.label, required this.isPaid});

  @override
  Widget build(BuildContext context) {
    final accent = isPaid ? EbtlColors.teal : EbtlColors.gold;

    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 13, vertical: 8),
      decoration: BoxDecoration(
        color: isPaid
            ? EbtlColors.seafoam.withValues(alpha: 0.42)
            : EbtlColors.gold.withValues(alpha: 0.16),
        borderRadius: BorderRadius.circular(999),
        border: Border.all(color: accent.withValues(alpha: 0.15)),
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
              border: Border.all(color: accent.withValues(alpha: 0.7)),
            ),
            child: Icon(
              isPaid ? Icons.check_rounded : Icons.schedule_rounded,
              size: 14,
              color: accent,
            ),
          ),
          const SizedBox(width: 8),
          Text(
            label,
            style: GoogleFonts.manrope(
              fontSize: 16,
              height: 1,
              fontWeight: FontWeight.w800,
              color: accent,
            ),
          ),
        ],
      ),
    );
  }
}
