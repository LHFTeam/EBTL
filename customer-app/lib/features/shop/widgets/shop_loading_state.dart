import 'package:flutter/material.dart';

import '../../../shared/widgets/ebtl_loading_graphic.dart';
import 'shop_top_widgets.dart';

class ShopLoadingState extends StatelessWidget {
  const ShopLoadingState({super.key});

  @override
  Widget build(BuildContext context) {
    return SafeArea(
      child: CustomScrollView(
        slivers: [
          SliverToBoxAdapter(
            child: ShopHeader(
              unreadNotificationCount: 0,
              onOpenNotifications: () {},
              activeOrdersCount: 0,
              onOpenActiveOrders: () {},
            ),
          ),
          const SliverFillRemaining(
            hasScrollBody: false,
            child: EbtlLoadingGraphic(label: 'Stocking the shop...'),
          ),
        ],
      ),
    );
  }
}
