import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';

import '../../core/theme/ebtl_colors.dart';
import '../../models/profile_models.dart';
import '../../services/api_service.dart';
import '../../shared/widgets/app_state_widgets.dart';
import 'customer_orders_screen.dart';
import 'order_detail_screen.dart';
import 'widgets/profile_widgets.dart';

/// Lists the customer's active orders — orders that are paid but not yet
/// completed. Reached from the active-orders shortcut in the top bar, which
/// only appears while at least one order is active. Tapping an order opens its
/// detail screen; a "View all orders" link leads to the full order history.
class ActiveOrdersScreen extends StatefulWidget {
  const ActiveOrdersScreen({super.key});

  @override
  State<ActiveOrdersScreen> createState() => _ActiveOrdersScreenState();
}

class _ActiveOrdersScreenState extends State<ActiveOrdersScreen> {
  late Future<CustomerOrdersResponse> ordersFuture;

  @override
  void initState() {
    super.initState();
    ordersFuture = ApiService.fetchCustomerOrders(limit: 100);
  }

  void reload() {
    setState(() {
      ordersFuture = ApiService.fetchCustomerOrders(limit: 100);
    });
  }

  void _openOrderDetail(ProfileOrder order) {
    Navigator.of(context)
        .push(
          MaterialPageRoute(
            builder: (_) => OrderDetailScreen(
              orderId: order.id,
              orderNumber: order.orderNumber,
            ),
          ),
        )
        // An order may have moved out of the active set (e.g. completed) while
        // its detail screen was open, so refresh the list on return.
        .then((_) => reload());
  }

  void _openAllOrders() {
    Navigator.of(context).push(
      MaterialPageRoute(builder: (_) => const CustomerOrdersScreen()),
    );
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: EbtlColors.cream,
      body: SafeArea(
        child: FutureBuilder<CustomerOrdersResponse>(
          future: ordersFuture,
          builder: (context, snapshot) {
            final activeOrders =
                snapshot.data?.orders
                    .where((order) => order.isActive)
                    .toList() ??
                const <ProfileOrder>[];

            final isLoading =
                snapshot.connectionState == ConnectionState.waiting;
            final hasError = snapshot.hasError;

            return CustomScrollView(
              slivers: [
                SliverToBoxAdapter(
                  child: ProfileSubScreenHeader(
                    title: 'Active Orders',
                    onBack: () => Navigator.of(context).pop(),
                  ),
                ),
                if (isLoading)
                  const EbtlLoadingSliver(
                    label: 'Loading your active orders...',
                  )
                else if (hasError)
                  SliverToBoxAdapter(
                    child: InlineErrorCard(
                      message: snapshot.error.toString(),
                      onRetry: reload,
                    ),
                  )
                else if (activeOrders.isEmpty)
                  const SliverToBoxAdapter(child: _NoActiveOrdersCard())
                else ...[
                  for (final order in activeOrders.where(
                    (order) => order.isWaitingForCollection,
                  ))
                    SliverToBoxAdapter(
                      child: _ReadyForCollectionBanner(
                        order: order,
                        onTap: () => _openOrderDetail(order),
                      ),
                    ),
                  SliverPadding(
                    padding: const EdgeInsets.fromLTRB(22, 8, 22, 4),
                    sliver: SliverList(
                      delegate: SliverChildBuilderDelegate((context, index) {
                        if (index.isOdd) return const SizedBox(height: 12);

                        final order = activeOrders[index ~/ 2];

                        return ProfileOrderCard(
                          order: order,
                          onTap: () => _openOrderDetail(order),
                        );
                      }, childCount: (activeOrders.length * 2) - 1),
                    ),
                  ),
                ],
                if (!isLoading && !hasError)
                  SliverToBoxAdapter(
                    child: _ViewAllOrdersLink(onTap: _openAllOrders),
                  ),
              ],
            );
          },
        ),
      ),
    );
  }
}

/// An order bagged and waiting at the cart. Tapping through goes straight to
/// the pickup code, which is the only thing left to do with it.
class _ReadyForCollectionBanner extends StatelessWidget {
  final ProfileOrder order;
  final VoidCallback onTap;

  const _ReadyForCollectionBanner({required this.order, required this.onTap});

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.fromLTRB(22, 8, 22, 0),
      child: Material(
        color: EbtlColors.seafoam,
        borderRadius: BorderRadius.circular(18),
        child: InkWell(
          onTap: onTap,
          borderRadius: BorderRadius.circular(18),
          child: Padding(
            padding: const EdgeInsets.all(16),
            child: Row(
              children: [
                const Icon(
                  Icons.qr_code_scanner_rounded,
                  size: 22,
                  color: EbtlColors.teal,
                ),
                const SizedBox(width: 12),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        'Order ${order.displayOrderNumber} is ready',
                        style: GoogleFonts.manrope(
                          fontSize: 15,
                          fontWeight: FontWeight.w900,
                          color: EbtlColors.navy,
                        ),
                      ),
                      const SizedBox(height: 2),
                      Text(
                        'Show your pickup code at ${order.displayLocation}',
                        style: GoogleFonts.manrope(
                          fontSize: 12.5,
                          height: 1.3,
                          fontWeight: FontWeight.w600,
                          color: EbtlColors.ink,
                        ),
                      ),
                    ],
                  ),
                ),
                const Icon(
                  Icons.chevron_right_rounded,
                  color: EbtlColors.teal,
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}

class _NoActiveOrdersCard extends StatelessWidget {
  const _NoActiveOrdersCard();

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.fromLTRB(22, 8, 22, 8),
      child: Container(
        width: double.infinity,
        padding: const EdgeInsets.all(20),
        decoration: BoxDecoration(
          color: EbtlColors.white.withValues(alpha: 0.90),
          borderRadius: BorderRadius.circular(18),
          border: Border.all(color: EbtlColors.border),
        ),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Container(
              width: 52,
              height: 52,
              decoration: BoxDecoration(
                color: EbtlColors.seafoam.withValues(alpha: 0.65),
                borderRadius: BorderRadius.circular(16),
              ),
              child: const Icon(
                Icons.local_bar_outlined,
                color: EbtlColors.navy,
              ),
            ),
            const SizedBox(height: 16),
            Text(
              'No active orders right now.',
              style: GoogleFonts.manrope(
                fontSize: 16,
                fontWeight: FontWeight.w900,
                color: EbtlColors.navy,
              ),
            ),
            const SizedBox(height: 6),
            Text(
              "Orders you've paid for will show up here until they're "
              'completed.',
              style: GoogleFonts.manrope(
                fontSize: 13,
                height: 1.35,
                fontWeight: FontWeight.w600,
                color: EbtlColors.muted,
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _ViewAllOrdersLink extends StatelessWidget {
  final VoidCallback onTap;

  const _ViewAllOrdersLink({required this.onTap});

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.fromLTRB(22, 4, 22, 24),
      child: Align(
        alignment: Alignment.centerLeft,
        child: TextButton.icon(
          onPressed: onTap,
          style: TextButton.styleFrom(
            foregroundColor: EbtlColors.coral,
            padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 8),
          ),
          icon: const Icon(Icons.receipt_long_outlined, size: 18),
          label: Text(
            'View all orders',
            style: GoogleFonts.manrope(
              fontSize: 14,
              fontWeight: FontWeight.w800,
              color: EbtlColors.coral,
            ),
          ),
        ),
      ),
    );
  }
}
