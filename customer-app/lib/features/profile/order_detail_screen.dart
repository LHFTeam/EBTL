import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';

import '../../core/theme/ebtl_colors.dart';
import '../../models/order_detail_models.dart';
import '../../services/api_service.dart';
import '../../shared/widgets/app_state_widgets.dart';
import '../../shared/widgets/detail_card.dart';
import '../../shared/widgets/network_or_asset_image.dart';
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
                      message: snapshot.error.toString(),
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
            fontSize: 22,
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
