import 'package:flutter/material.dart';

import '../../core/theme/ebtl_colors.dart';
import '../../models/shop_models.dart';
import '../../shared/widgets/app_state_widgets.dart';
import '../shop/widgets/shop_product_widgets.dart';
import '../shop/widgets/shop_simple_header.dart';

/// A category or tag reached from Explore search results.
class SearchCollectionScreen extends StatelessWidget {
  final String title;
  final List<ShopProduct> products;
  final Future<void> Function(ShopProduct product) onOpenProduct;

  const SearchCollectionScreen({
    super.key,
    required this.title,
    required this.products,
    required this.onOpenProduct,
  });

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: EbtlColors.cream,
      body: SafeArea(
        child: CustomScrollView(
          slivers: [
            SliverToBoxAdapter(
              child: ShopSimpleHeader(
                title: title,
                subtitle: 'Browse products tagged $title.',
                onBack: () => Navigator.of(context).pop(),
              ),
            ),
            if (products.isEmpty)
              const SliverToBoxAdapter(
                child: EmptyStateCard(
                  message: 'No matching products are available yet.',
                ),
              )
            else
              SliverPadding(
                padding: const EdgeInsets.fromLTRB(22, 14, 22, 24),
                sliver: SliverGrid(
                  delegate: SliverChildBuilderDelegate((context, index) {
                    final product = products[index];
                    return ShopProductCardTile(
                      product: product,
                      compact: false,
                      isAdding: false,
                      onTap: () => onOpenProduct(product),
                      onAdd: null,
                    );
                  }, childCount: products.length),
                  gridDelegate: SliverGridDelegateWithFixedCrossAxisCount(
                    crossAxisCount: 2,
                    mainAxisExtent: ShopProductCardTile.heightFor(compact: false),
                    mainAxisSpacing: 14,
                    crossAxisSpacing: 14,
                  ),
                ),
              ),
          ],
        ),
      ),
    );
  }
}
