import 'package:flutter/material.dart';

import '../../core/theme/ebtl_colors.dart';
import '../../models/profile_models.dart';
import '../../services/api_service.dart';
import '../../core/network/api_exception.dart';
import '../../shared/widgets/app_state_widgets.dart';
import 'order_detail_screen.dart';
import 'widgets/profile_widgets.dart';

class CustomerOrdersScreen extends StatefulWidget {
  const CustomerOrdersScreen({super.key});

  @override
  State<CustomerOrdersScreen> createState() => _CustomerOrdersScreenState();
}

class _CustomerOrdersScreenState extends State<CustomerOrdersScreen> {
  late Future<CustomerOrdersResponse> ordersFuture;

  @override
  void initState() {
    super.initState();
    ordersFuture = ApiService.fetchCustomerOrders();
  }

  void reload() {
    setState(() {
      ordersFuture = ApiService.fetchCustomerOrders();
    });
  }

  Future<void> _openOrderDetail(ProfileOrder order) async {
    await Navigator.of(context).push(
      MaterialPageRoute(
        builder: (_) => OrderDetailScreen(
          orderId: order.id,
          orderNumber: order.orderNumber,
        ),
      ),
    );

    // An order can be paid for or cancelled on that screen, so the list it
    // came from is re-read rather than left showing the status it had.
    if (!mounted) return;
    reload();
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: EbtlColors.cream,
      body: SafeArea(
        child: FutureBuilder<CustomerOrdersResponse>(
          future: ordersFuture,
          builder: (context, snapshot) {
            return CustomScrollView(
              slivers: [
                SliverToBoxAdapter(
                  child: ProfileSubScreenHeader(
                    title: 'My Orders',
                    onBack: () => Navigator.of(context).pop(),
                  ),
                ),
                if (snapshot.connectionState == ConnectionState.waiting)
                  const EbtlLoadingSliver(label: 'Loading your orders...')
                else if (snapshot.hasError)
                  SliverToBoxAdapter(
                    child: InlineErrorCard(
                      message: apiErrorMessage(snapshot.error!),
                      onRetry: reload,
                    ),
                  )
                else if (snapshot.data == null || snapshot.data!.orders.isEmpty)
                  const SliverToBoxAdapter(child: ProfileEmptyOrdersCard())
                else
                  SliverPadding(
                    padding: const EdgeInsets.fromLTRB(22, 8, 22, 22),
                    sliver: SliverList(
                      delegate: SliverChildBuilderDelegate((context, index) {
                        if (index.isOdd) return const SizedBox(height: 12);

                        final orderIndex = index ~/ 2;
                        final order = snapshot.data!.orders[orderIndex];

                        return ProfileOrderCard(
                          order: order,
                          onTap: () => _openOrderDetail(order),
                        );
                      }, childCount: (snapshot.data!.orders.length * 2) - 1),
                    ),
                  ),
              ],
            );
          },
        ),
      ),
    );
  }
}
