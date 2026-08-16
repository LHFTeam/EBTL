import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';

import '../../core/theme/ebtl_colors.dart';
import '../../models/order_detail_models.dart';
import '../../services/api_service.dart';
import '../../services/payment_sheet_service.dart';
import '../../core/network/api_exception.dart';
import '../../shared/widgets/app_state_widgets.dart';
import '../../shared/widgets/brand_widgets.dart';
import '../../shared/widgets/detail_card.dart';
import '../../shared/widgets/network_or_asset_image.dart';
import 'widgets/pickup_code_card.dart';
import 'widgets/profile_widgets.dart';

class OrderDetailScreen extends StatefulWidget {
  final String orderId;
  final String? orderNumber;

  const OrderDetailScreen({
    super.key,
    required this.orderId,
    this.orderNumber,
  });

  @override
  State<OrderDetailScreen> createState() => _OrderDetailScreenState();
}

class _OrderDetailScreenState extends State<OrderDetailScreen> {
  late Future<OrderDetailResponse> orderFuture;

  /// True while the payment sheet for this order is being opened, or while the
  /// payment it submitted is being confirmed.
  bool isPaying = false;
  bool isCancelling = false;

  @override
  void initState() {
    super.initState();
    orderFuture = ApiService.fetchCustomerOrderDetail(orderId: widget.orderId);
  }

  void reload() {
    setState(() {
      orderFuture = ApiService.fetchCustomerOrderDetail(
        orderId: widget.orderId,
      );
    });
  }

  /// Picks the payment of an order left unpaid back up.
  ///
  /// The payment session created when the order was placed is still live until
  /// the backend closes it (thirty minutes, then the order expires), so this
  /// re-reads that session and presents the same sheet checkout would have.
  /// Nothing here decides that the money arrived — the backend's webhook does,
  /// which is what the poll afterwards is waiting for.
  Future<void> continuePayment(OrderDetail order) async {
    if (isPaying || isCancelling) return;

    setState(() => isPaying = true);

    try {
      final status = await ApiService.fetchOrderPaymentStatus(
        orderId: order.id,
      );

      if (!mounted) return;

      if (status.isPaid) {
        setState(() => isPaying = false);
        showAppSnackBar(context, 'This order is already paid for.');
        reload();
        return;
      }

      final result = await presentStripePaymentSheet(status.payment.stripe);

      if (!mounted) return;

      if (!result.isSubmitted) {
        setState(() => isPaying = false);

        final message = result.message;
        if (message != null) showAppSnackBar(context, message);
        return;
      }

      final settled = await pollPaymentStatus(order.id);

      if (!mounted) return;
      setState(() => isPaying = false);

      showAppSnackBar(
        context,
        settled.isPaid
            ? 'Payment confirmed. Your order is on its way.'
            : settled.isFailed
            ? 'Your payment did not go through, so you have not been charged.'
            : "We're still waiting for your bank to confirm this payment. It will update here shortly.",
      );

      reload();
    } catch (error) {
      if (!mounted) return;

      setState(() => isPaying = false);
      showAppSnackBar(
        context,
        apiErrorMessage(error, fallback: 'Could not start this payment.'),
      );
    }
  }

  Future<void> cancelOrder(OrderDetail order) async {
    if (isPaying || isCancelling) return;

    final confirmed = await showConfirmCancelOrderDialog(context);
    if (!confirmed || !mounted) return;

    setState(() => isCancelling = true);

    try {
      await ApiService.cancelCustomerOrder(orderId: order.id);

      if (!mounted) return;
      setState(() => isCancelling = false);
      showAppSnackBar(context, 'Order cancelled. You have not been charged.');
      reload();
    } catch (error) {
      if (!mounted) return;

      setState(() => isCancelling = false);
      showAppSnackBar(
        context,
        apiErrorMessage(error, fallback: 'Could not cancel this order.'),
      );
      // Whatever the backend refused for, the order is not where this screen
      // thought it was — show where it actually stands.
      reload();
    }
  }

  @override
  Widget build(BuildContext context) {
    final headerNumber = widget.orderNumber?.trim();
    final headerTitle = headerNumber != null && headerNumber.isNotEmpty
        ? 'Order $headerNumber'
        : 'Order Details';

    return Scaffold(
      backgroundColor: EbtlColors.cream,
      body: SafeArea(
        child: FutureBuilder<OrderDetailResponse>(
          future: orderFuture,
          builder: (context, snapshot) {
            return CustomScrollView(
              slivers: [
                SliverToBoxAdapter(
                  child: ProfileSubScreenHeader(
                    title: headerTitle,
                    onBack: () => Navigator.of(context).pop(),
                  ),
                ),
                if (snapshot.connectionState == ConnectionState.waiting)
                  const EbtlLoadingSliver(label: 'Loading order...')
                else if (snapshot.hasError)
                  SliverToBoxAdapter(
                    child: InlineErrorCard(
                      message: apiErrorMessage(snapshot.error!),
                      onRetry: reload,
                    ),
                  )
                else if (snapshot.data == null)
                  SliverToBoxAdapter(
                    child: InlineErrorCard(
                      message: 'The backend returned no order data.',
                      onRetry: reload,
                    ),
                  )
                else
                  ..._buildContent(snapshot.data!),
                const SliverToBoxAdapter(child: SizedBox(height: 24)),
              ],
            );
          },
        ),
      ),
    );
  }

  List<Widget> _buildContent(OrderDetailResponse data) {
    final order = data.order;
    final currency = order.totals.currency;

    return [
      SliverToBoxAdapter(child: _OrderStatusCard(order: order)),
      // Sits directly under the status, above everything else: once the order
      // is ready this is the only thing on the screen the customer needs.
      if (order.showsPickupCode)
        SliverToBoxAdapter(
          child: PickupCodeCard(
            // Keyed by order so switching between two orders rebuilds the card
            // rather than reusing one order's code under another's number.
            key: ValueKey('pickup-${order.id}'),
            orderId: order.id,
            orderStatus: order.status,
            onOrderMoved: reload,
          ),
        ),
      if (order.awaitsPayment)
        SliverToBoxAdapter(
          child: _PendingPaymentCard(
            order: order,
            isPaying: isPaying,
            isCancelling: isCancelling,
            onContinuePayment: () => continuePayment(order),
            onCancelOrder: () => cancelOrder(order),
          ),
        ),
      if (order.location != null)
        SliverToBoxAdapter(child: _OrderLocationCard(location: order.location!)),
      SliverToBoxAdapter(
        child: Padding(
          padding: const EdgeInsets.fromLTRB(22, 6, 22, 4),
          child: _SectionLabel(
            label: order.isDelivery ? 'Delivery' : 'Pickup',
            title: 'Your Items',
          ),
        ),
      ),
      SliverPadding(
        padding: const EdgeInsets.fromLTRB(22, 0, 22, 4),
        sliver: SliverList.separated(
          itemCount: data.items.length,
          separatorBuilder: (_, _) => const SizedBox(height: 10),
          itemBuilder: (context, index) {
            return _OrderItemCard(item: data.items[index], currency: currency);
          },
        ),
      ),
      SliverToBoxAdapter(child: _OrderSummaryCard(totals: order.totals)),
    ];
  }
}

/// Asks before an order is dropped: cancelling closes the payment window with
/// the gateway, so it cannot be undone from here.
Future<bool> showConfirmCancelOrderDialog(BuildContext context) async {
  final confirmed = await showDialog<bool>(
    context: context,
    builder: (dialogContext) {
      return AlertDialog(
        backgroundColor: EbtlColors.white,
        title: Text(
          'Cancel this order?',
          style: GoogleFonts.manrope(
            fontSize: 18,
            fontWeight: FontWeight.w900,
            color: EbtlColors.navy,
          ),
        ),
        content: Text(
          'You have not been charged, and nothing has been prepared. You will '
          'need to place a new order if you change your mind.',
          style: GoogleFonts.manrope(
            fontSize: 14,
            height: 1.35,
            fontWeight: FontWeight.w600,
            color: EbtlColors.ink,
          ),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(dialogContext).pop(false),
            child: Text(
              'Keep it',
              style: GoogleFonts.manrope(
                fontWeight: FontWeight.w900,
                color: EbtlColors.teal,
              ),
            ),
          ),
          TextButton(
            onPressed: () => Navigator.of(dialogContext).pop(true),
            child: Text(
              'Cancel order',
              style: GoogleFonts.manrope(
                fontWeight: FontWeight.w900,
                color: EbtlColors.coral,
              ),
            ),
          ),
        ],
      );
    },
  );

  return confirmed ?? false;
}

/// The two ways out of an order that was placed but never paid for.
class _PendingPaymentCard extends StatelessWidget {
  final OrderDetail order;
  final bool isPaying;
  final bool isCancelling;
  final VoidCallback onContinuePayment;
  final VoidCallback onCancelOrder;

  const _PendingPaymentCard({
    required this.order,
    required this.isPaying,
    required this.isCancelling,
    required this.onContinuePayment,
    required this.onCancelOrder,
  });

  @override
  Widget build(BuildContext context) {
    final isBusy = isPaying || isCancelling;

    return Padding(
      padding: const EdgeInsets.fromLTRB(22, 0, 22, 8),
      child: DetailCard(
        backgroundColor: EbtlColors.sand.withValues(alpha: 0.48),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                const Icon(
                  Icons.hourglass_bottom,
                  size: 20,
                  color: EbtlColors.coral,
                ),
                const SizedBox(width: 8),
                Expanded(
                  child: Text(
                    'Payment pending',
                    style: GoogleFonts.manrope(
                      fontSize: 16,
                      fontWeight: FontWeight.w900,
                      color: EbtlColors.navy,
                    ),
                  ),
                ),
              ],
            ),
            const SizedBox(height: 6),
            Text(
              'This order is being held until it is paid for. Finish the '
              'payment to confirm it, or cancel it — nothing has been charged '
              'either way.',
              style: GoogleFonts.manrope(
                fontSize: 13,
                height: 1.35,
                fontWeight: FontWeight.w600,
                color: EbtlColors.ink,
              ),
            ),
            const SizedBox(height: 14),
            SizedBox(
              width: double.infinity,
              height: 52,
              child: ElevatedButton(
                onPressed: isBusy ? null : onContinuePayment,
                style: ebtlCoralButtonStyle(withDisabledColors: true),
                child: isPaying
                    ? const SizedBox(
                        width: 18,
                        height: 18,
                        child: CircularProgressIndicator(
                          strokeWidth: 2,
                          color: Colors.white,
                        ),
                      )
                    : Text(
                        'Continue Payment',
                        style: GoogleFonts.manrope(
                          fontSize: 15,
                          fontWeight: FontWeight.w900,
                        ),
                      ),
              ),
            ),
            const SizedBox(height: 4),
            Center(
              child: TextButton(
                onPressed: isBusy ? null : onCancelOrder,
                child: Text(
                  isCancelling ? 'Cancelling...' : 'Cancel Order',
                  style: GoogleFonts.manrope(
                    fontWeight: FontWeight.w900,
                    color: EbtlColors.coral,
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

class _SectionLabel extends StatelessWidget {
  final String label;
  final String title;

  const _SectionLabel({required this.label, required this.title});

  @override
  Widget build(BuildContext context) {
    return Row(
      crossAxisAlignment: CrossAxisAlignment.center,
      children: [
        Text(
          title,
          style: GoogleFonts.playfairDisplay(
            fontSize: 20,
            height: 1,
            fontWeight: FontWeight.w800,
            color: EbtlColors.navy,
          ),
        ),
        const SizedBox(width: 10),
        Container(
          padding: const EdgeInsets.symmetric(horizontal: 9, vertical: 4),
          decoration: BoxDecoration(
            color: EbtlColors.seafoam.withValues(alpha: 0.6),
            borderRadius: BorderRadius.circular(999),
          ),
          child: Text(
            label,
            style: GoogleFonts.manrope(
              fontSize: 10.5,
              fontWeight: FontWeight.w900,
              color: EbtlColors.teal,
            ),
          ),
        ),
      ],
    );
  }
}

class _OrderStatusCard extends StatelessWidget {
  final OrderDetail order;

  const _OrderStatusCard({required this.order});

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.fromLTRB(22, 6, 22, 8),
      child: DetailCard(
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                Expanded(
                  child: Text(
                    'Order ${order.displayOrderNumber}',
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: GoogleFonts.manrope(
                      fontSize: 17,
                      fontWeight: FontWeight.w900,
                      color: EbtlColors.navy,
                    ),
                  ),
                ),
                _OrderStatusBadge(status: order.status),
              ],
            ),
            const SizedBox(height: 10),
            _OrderInfoRow(
              icon: Icons.schedule,
              label: order.displayTime,
            ),
            const SizedBox(height: 8),
            _OrderInfoRow(
              icon: Icons.payments_outlined,
              label: 'Payment: ${_paymentLabel(order.paymentStatus)}',
            ),
            if ((order.customerPhone ?? '').trim().isNotEmpty) ...[
              const SizedBox(height: 8),
              _OrderInfoRow(
                icon: Icons.phone_outlined,
                label: order.customerPhone!.trim(),
              ),
            ],
            if (order.isDelivery &&
                (order.addressText ?? '').trim().isNotEmpty) ...[
              const SizedBox(height: 8),
              _OrderInfoRow(
                icon: Icons.home_outlined,
                label: order.addressText!.trim(),
              ),
            ],
            if ((order.customerNotes ?? '').trim().isNotEmpty) ...[
              const SizedBox(height: 8),
              _OrderInfoRow(
                icon: Icons.sticky_note_2_outlined,
                label: order.customerNotes!.trim(),
              ),
            ],
          ],
        ),
      ),
    );
  }

  String _paymentLabel(String status) {
    final normalized = status.trim().toLowerCase().replaceAll('_', ' ');
    if (normalized.isEmpty) return 'Unknown';
    return normalized[0].toUpperCase() + normalized.substring(1);
  }
}

class _OrderInfoRow extends StatelessWidget {
  final IconData icon;
  final String label;

  const _OrderInfoRow({required this.icon, required this.label});

  @override
  Widget build(BuildContext context) {
    return Row(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Icon(icon, size: 18, color: EbtlColors.teal),
        const SizedBox(width: 10),
        Expanded(
          child: Text(
            label,
            style: GoogleFonts.manrope(
              fontSize: 13,
              height: 1.3,
              fontWeight: FontWeight.w700,
              color: EbtlColors.ink,
            ),
          ),
        ),
      ],
    );
  }
}

class _OrderStatusBadge extends StatelessWidget {
  final String status;

  const _OrderStatusBadge({required this.status});

  @override
  Widget build(BuildContext context) {
    final normalized = status.toLowerCase();
    final backgroundColor = normalized == 'ready' || normalized == 'completed'
        ? EbtlColors.seafoam.withValues(alpha: 0.68)
        : normalized == 'cancelled' || normalized == 'refunded'
        ? EbtlColors.blush.withValues(alpha: 0.68)
        : EbtlColors.sand.withValues(alpha: 0.72);
    final textColor = normalized == 'cancelled' || normalized == 'refunded'
        ? EbtlColors.coral
        : EbtlColors.teal;

    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
      decoration: BoxDecoration(
        color: backgroundColor,
        borderRadius: BorderRadius.circular(999),
      ),
      child: Text(
        _label(normalized),
        style: GoogleFonts.manrope(
          fontSize: 11,
          fontWeight: FontWeight.w900,
          color: textColor,
        ),
      ),
    );
  }

  String _label(String status) {
    switch (status) {
      case 'ready':
        return 'Ready for pickup';
      case 'pending_payment':
        return 'Pending payment';
      case 'confirmed':
        return 'Confirmed';
      case 'preparing':
        return 'Preparing';
      case 'out_for_delivery':
        return 'Out for delivery';
      case 'completed':
        return 'Completed';
      case 'cancelled':
        return 'Cancelled';
      case 'refunded':
        return 'Refunded';
      default:
        if (status.isEmpty) return 'Order';
        return status[0].toUpperCase() +
            status.substring(1).replaceAll('_', ' ');
    }
  }
}

class _OrderLocationCard extends StatelessWidget {
  final OrderDetailLocation location;

  const _OrderLocationCard({required this.location});

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.fromLTRB(22, 4, 22, 8),
      child: Container(
        height: 88,
        decoration: BoxDecoration(
          color: EbtlColors.white.withValues(alpha: 0.92),
          borderRadius: BorderRadius.circular(18),
          border: Border.all(color: EbtlColors.border),
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
                  mainAxisAlignment: MainAxisAlignment.center,
                  children: [
                    Text(
                      location.name,
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
                      location.subtitle,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: GoogleFonts.manrope(
                        fontSize: 11,
                        fontWeight: FontWeight.w600,
                        color: EbtlColors.muted,
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
                imageUrl: location.bannerImageUrl,
                asset: 'assets/images/location_banner_placeholder.jpg',
                fit: BoxFit.cover,
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _OrderItemCard extends StatelessWidget {
  final OrderDetailItem item;
  final String currency;

  const _OrderItemCard({required this.item, required this.currency});

  @override
  Widget build(BuildContext context) {
    final variantName = item.variantName?.trim() ?? '';
    final customization = item.customizationSummary?.trim() ?? '';

    return Container(
      decoration: BoxDecoration(
        color: EbtlColors.white.withValues(alpha: 0.92),
        borderRadius: BorderRadius.circular(18),
        border: Border.all(color: EbtlColors.border),
      ),
      padding: const EdgeInsets.all(10),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          ClipRRect(
            borderRadius: BorderRadius.circular(14),
            child: SizedBox(
              width: 62,
              height: 62,
              child: NetworkOrAssetImage(
                imageUrl: null,
                asset: item.imageAsset,
                fit: BoxFit.cover,
              ),
            ),
          ),
          const SizedBox(width: 12),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  item.displayName,
                  maxLines: 2,
                  overflow: TextOverflow.ellipsis,
                  style: GoogleFonts.manrope(
                    fontSize: 14,
                    height: 1.15,
                    fontWeight: FontWeight.w900,
                    color: EbtlColors.navy,
                  ),
                ),
                if (variantName.isNotEmpty) ...[
                  const SizedBox(height: 3),
                  Text(
                    variantName,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: GoogleFonts.manrope(
                      fontSize: 11.5,
                      fontWeight: FontWeight.w700,
                      color: EbtlColors.muted,
                    ),
                  ),
                ],
                if (customization.isNotEmpty) ...[
                  const SizedBox(height: 3),
                  Text(
                    customization,
                    maxLines: 2,
                    overflow: TextOverflow.ellipsis,
                    style: GoogleFonts.manrope(
                      fontSize: 11.5,
                      fontWeight: FontWeight.w800,
                      color: EbtlColors.teal,
                    ),
                  ),
                ],
                const SizedBox(height: 6),
                Row(
                  children: [
                    Text(
                      '${item.quantity} × ${item.unitPriceLabel(currency)}',
                      style: GoogleFonts.manrope(
                        fontSize: 11,
                        fontWeight: FontWeight.w700,
                        color: EbtlColors.muted,
                      ),
                    ),
                    const Spacer(),
                    Text(
                      item.lineTotalLabel(currency),
                      style: GoogleFonts.manrope(
                        fontSize: 14,
                        fontWeight: FontWeight.w900,
                        color: EbtlColors.coral,
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

class _OrderSummaryCard extends StatelessWidget {
  final OrderDetailTotals totals;

  const _OrderSummaryCard({required this.totals});

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.fromLTRB(22, 12, 22, 8),
      child: Container(
        width: double.infinity,
        padding: const EdgeInsets.all(18),
        decoration: BoxDecoration(
          color: EbtlColors.navy,
          borderRadius: BorderRadius.circular(24),
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
            _SummaryRow(label: 'Subtotal', value: totals.subtotalLabel),
            if (totals.discountAmount > 0) ...[
              const SizedBox(height: 10),
              _SummaryRow(
                label: 'Discount',
                value: totals.discountLabel,
                valueColor: EbtlColors.seafoam,
              ),
            ],
            if (totals.deliveryFee > 0) ...[
              const SizedBox(height: 10),
              _SummaryRow(
                label: 'Delivery Fee',
                value: totals.deliveryFeeLabel,
              ),
            ],
            const SizedBox(height: 12),
            Divider(color: Colors.white.withValues(alpha: 0.20)),
            const SizedBox(height: 12),
            _SummaryRow(
              label: 'Total (incl. VAT)',
              value: totals.totalLabel,
              isTotal: true,
            ),
          ],
        ),
      ),
    );
  }
}

class _SummaryRow extends StatelessWidget {
  final String label;
  final String value;
  final bool isTotal;
  final Color? valueColor;

  const _SummaryRow({
    required this.label,
    required this.value,
    this.isTotal = false,
    this.valueColor,
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
            color: isTotal ? EbtlColors.gold : (valueColor ?? Colors.white),
          ),
        ),
      ],
    );
  }
}
