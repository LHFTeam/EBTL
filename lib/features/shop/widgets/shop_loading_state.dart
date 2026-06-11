import 'package:flutter/material.dart';

import 'shop_skeleton_box.dart';
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
              cartQuantity: 0,
              onSearch: null,
              onOpenCart: () {},
            ),
          ),
          const SliverToBoxAdapter(
            child: Padding(
              padding: EdgeInsets.fromLTRB(22, 8, 22, 18),
              child: ShopSkeletonBox(
                width: double.infinity,
                height: 142,
                radius: 20,
              ),
            ),
          ),
          SliverToBoxAdapter(
            child: SizedBox(
              height: 102,
              child: ListView.separated(
                padding: const EdgeInsets.fromLTRB(22, 8, 22, 8),
                scrollDirection: Axis.horizontal,
                itemCount: 6,
                separatorBuilder: (_, _) => const SizedBox(width: 10),
                itemBuilder: (_, _) =>
                    const ShopSkeletonBox(width: 76, height: 80, radius: 22),
              ),
            ),
          ),
          SliverToBoxAdapter(
            child: Padding(
              padding: const EdgeInsets.symmetric(horizontal: 22),
              child: GridView.builder(
                shrinkWrap: true,
                primary: false,
                physics: const NeverScrollableScrollPhysics(),
                itemCount: 6,
                gridDelegate: const SliverGridDelegateWithFixedCrossAxisCount(
                  crossAxisCount: 3,
                  mainAxisExtent: 198,
                  mainAxisSpacing: 12,
                  crossAxisSpacing: 10,
                ),
                itemBuilder: (_, _) => const ShopSkeletonBox(
                  width: double.infinity,
                  height: 198,
                  radius: 18,
                ),
              ),
            ),
          ),
        ],
      ),
    );
  }
}
