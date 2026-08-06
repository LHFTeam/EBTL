import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';

import '../../core/theme/ebtl_colors.dart';
import '../../models/shop_models.dart';
import '../../shared/widgets/app_state_widgets.dart';
import 'widgets/shop_product_widgets.dart';
import 'widgets/shop_simple_header.dart';

class ShopSearchScreen extends StatefulWidget {
  final ShopResponse shop;
  final String? locationId;
  final ValueChanged<ShopCategory> onCategoryTap;
  final ValueChanged<ShopProduct> onProductTap;
  final ValueChanged<ShopProduct> onQuickAdd;

  const ShopSearchScreen({
    super.key,
    required this.shop,
    required this.locationId,
    required this.onCategoryTap,
    required this.onProductTap,
    required this.onQuickAdd,
  });

  @override
  State<ShopSearchScreen> createState() => _ShopSearchScreenState();
}

class _ShopSearchScreenState extends State<ShopSearchScreen> {
  final TextEditingController searchController = TextEditingController();

  @override
  void dispose() {
    searchController.dispose();
    super.dispose();
  }

  void openCategory(ShopCategory category) {
    Navigator.of(context).pop();
    widget.onCategoryTap(category);
  }

  void openProduct(ShopProduct product) {
    Navigator.of(context).pop();
    widget.onProductTap(product);
  }

  @override
  Widget build(BuildContext context) {
    final query = searchController.text.trim();

    final categoryMatches = widget.shop.categories
        .where((category) => category.matchesQuery(query))
        .toList();

    final productMatches = widget.shop.allFeaturedProducts
        .where((product) => product.matchesQuery(query))
        .toList();

    return Scaffold(
      backgroundColor: EbtlColors.cream,
      body: SafeArea(
        child: CustomScrollView(
          slivers: [
            SliverToBoxAdapter(
              child: ShopSimpleHeader(
                title: 'Search Shop',
                subtitle: 'Find cocktails, snacks and essentials.',
                onBack: () => Navigator.of(context).pop(),
              ),
            ),
            SliverToBoxAdapter(
              child: Padding(
                padding: const EdgeInsets.fromLTRB(22, 4, 22, 14),
                child: TextField(
                  controller: searchController,
                  autofocus: true,
                  onChanged: (_) => setState(() {}),
                  decoration: InputDecoration(
                    hintText: 'Search the shop',
                    prefixIcon: const Icon(Icons.search),
                    filled: true,
                    fillColor: EbtlColors.white,
                    contentPadding: const EdgeInsets.symmetric(
                      horizontal: 16,
                      vertical: 16,
                    ),
                    enabledBorder: OutlineInputBorder(
                      borderRadius: BorderRadius.circular(18),
                      borderSide: const BorderSide(color: EbtlColors.border),
                    ),
                    focusedBorder: OutlineInputBorder(
                      borderRadius: BorderRadius.circular(18),
                      borderSide: const BorderSide(color: EbtlColors.coral),
                    ),
                  ),
                ),
              ),
            ),
            if (categoryMatches.isNotEmpty)
              SliverToBoxAdapter(
                child: ShopSearchCategoryMatches(
                  categories: categoryMatches,
                  onCategoryTap: openCategory,
                ),
              ),
            if (productMatches.isEmpty && query.isNotEmpty)
              const SliverToBoxAdapter(
                child: EmptyStateCard(
                  message: 'No matching featured shop items found.',
                ),
              )
            else
              SliverPadding(
                padding: const EdgeInsets.fromLTRB(22, 14, 22, 24),
                sliver: SliverGrid(
                  delegate: SliverChildBuilderDelegate((context, index) {
                    final product = productMatches[index];

                    return ShopProductCardTile(
                      product: product,
                      compact: false,
                      isAdding: false,
                      onTap: () => openProduct(product),
                      onAdd: product.isCocktail
                          ? () => widget.onQuickAdd(product)
                          : null,
                    );
                  }, childCount: productMatches.length),
                  gridDelegate: SliverGridDelegateWithFixedCrossAxisCount(
                    crossAxisCount: 2,
                    mainAxisExtent: ShopProductCardTile.heightFor(
                      compact: false,
                    ),
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

class ShopSearchCategoryMatches extends StatelessWidget {
  final List<ShopCategory> categories;
  final ValueChanged<ShopCategory> onCategoryTap;

  const ShopSearchCategoryMatches({
    super.key,
    required this.categories,
    required this.onCategoryTap,
  });

  @override
  Widget build(BuildContext context) {
    return SizedBox(
      height: 92,
      child: ListView.separated(
        padding: const EdgeInsets.symmetric(horizontal: 22),
        scrollDirection: Axis.horizontal,
        itemCount: categories.length,
        separatorBuilder: (_, _) => const SizedBox(width: 10),
        itemBuilder: (context, index) {
          final category = categories[index];

          return SizedBox(
            width: 150,
            child: InkWell(
              onTap: () => onCategoryTap(category),
              borderRadius: BorderRadius.circular(18),
              child: Container(
                padding: const EdgeInsets.all(12),
                decoration: BoxDecoration(
                  color: EbtlColors.white.withValues(alpha: 0.92),
                  borderRadius: BorderRadius.circular(18),
                  border: Border.all(color: EbtlColors.border),
                ),
                child: Row(
                  children: [
                    const Icon(
                      Icons.category_outlined,
                      color: EbtlColors.coral,
                    ),
                    const SizedBox(width: 8),
                    Expanded(
                      child: Text(
                        category.name,
                        maxLines: 2,
                        overflow: TextOverflow.ellipsis,
                        style: GoogleFonts.manrope(
                          fontSize: 13,
                          fontWeight: FontWeight.w900,
                          color: EbtlColors.navy,
                        ),
                      ),
                    ),
                  ],
                ),
              ),
            ),
          );
        },
      ),
    );
  }
}
