import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';
import 'widgets/shop_simple_header.dart';

import '../../core/theme/ebtl_colors.dart';
import '../../models/shop_models.dart';

class ShopCategoryPickerScreen extends StatelessWidget {
  final String title;
  final List<ShopCategory> categories;
  final ValueChanged<ShopCategory> onCategoryTap;

  const ShopCategoryPickerScreen({
    super.key,
    required this.title,
    required this.categories,
    required this.onCategoryTap,
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
                subtitle: 'Choose a category to keep shopping.',
                onBack: () => Navigator.of(context).pop(),
              ),
            ),
            SliverPadding(
              padding: const EdgeInsets.fromLTRB(22, 10, 22, 24),
              sliver: SliverList(
                delegate: SliverChildBuilderDelegate(
                  (context, index) {
                    if (index.isOdd) return const SizedBox(height: 12);

                    final categoryIndex = index ~/ 2;
                    final category = categories[categoryIndex];

                    return InkWell(
                      onTap: () {
                        Navigator.of(context).pop();
                        onCategoryTap(category);
                      },
                      borderRadius: BorderRadius.circular(16),
                      child: Container(
                        padding: const EdgeInsets.all(16),
                        decoration: BoxDecoration(
                          color: EbtlColors.white.withValues(alpha: 0.92),
                          borderRadius: BorderRadius.circular(16),
                          border: Border.all(color: EbtlColors.border),
                        ),
                        child: Row(
                          children: [
                            Container(
                              width: 58,
                              height: 58,
                              decoration: BoxDecoration(
                                color: EbtlColors.blush.withValues(alpha: 0.45),
                                borderRadius: BorderRadius.circular(18),
                              ),
                              child: const Icon(
                                Icons.shopping_bag_outlined,
                                color: EbtlColors.coral,
                                size: 28,
                              ),
                            ),
                            const SizedBox(width: 14),
                            Expanded(
                              child: Text(
                                category.name,
                                style: GoogleFonts.manrope(
                                  fontSize: 16,
                                  fontWeight: FontWeight.w900,
                                  color: EbtlColors.navy,
                                ),
                              ),
                            ),
                            const Icon(
                              Icons.chevron_right,
                              color: EbtlColors.teal,
                            ),
                          ],
                        ),
                      ),
                    );
                  },
                  childCount: categories.isEmpty
                      ? 0
                      : (categories.length * 2) - 1,
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }
}
