import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';

import '../../core/theme/ebtl_colors.dart';

class EbtlBottomNav extends StatelessWidget {
  final int selectedIndex;
  final ValueChanged<int> onTap;
  final bool showProfileDot;

  const EbtlBottomNav({
    super.key,
    required this.selectedIndex,
    required this.onTap,
    this.showProfileDot = false,
  });

  @override
  Widget build(BuildContext context) {
    final items = [
      (Icons.home_outlined, Icons.home, 'Home'),
      (Icons.search, Icons.search, 'Cocktail Finder'),
      (Icons.shopping_bag_outlined, Icons.shopping_bag, 'Shop'),
      (Icons.shopping_cart_outlined, Icons.shopping_cart, 'Cart'),
      (Icons.person_outline, Icons.person, 'Profile'),
    ];

    return Container(
      height: 88,
      decoration: BoxDecoration(
        color: Colors.white.withValues(alpha: 0.97),
        border: const Border(top: BorderSide(color: EbtlColors.border)),
      ),
      child: Row(
        children: List.generate(items.length, (index) {
          final item = items[index];
          final active = index == selectedIndex;

          return Expanded(
            child: InkWell(
              onTap: () => onTap(index),
              child: Column(
                mainAxisAlignment: MainAxisAlignment.center,
                children: [
                  Stack(
                    clipBehavior: Clip.none,
                    children: [
                      Icon(
                        active ? item.$2 : item.$1,
                        color: active ? EbtlColors.coral : Colors.black87,
                        size: 27,
                      ),
                      if (index == 4 && showProfileDot)
                        Positioned(
                          top: -1,
                          right: -5,
                          child: Container(
                            width: 8,
                            height: 8,
                            decoration: BoxDecoration(
                              color: EbtlColors.coral,
                              shape: BoxShape.circle,
                              border: Border.all(
                                color: EbtlColors.white,
                                width: 1,
                              ),
                            ),
                          ),
                        ),
                    ],
                  ),
                  const SizedBox(height: 4),
                  Text(
                    item.$3,
                    maxLines: 2,
                    textAlign: TextAlign.center,
                    overflow: TextOverflow.ellipsis,
                    style: GoogleFonts.manrope(
                      fontSize: 9.5,
                      height: 1.08,
                      fontWeight: active ? FontWeight.w900 : FontWeight.w600,
                      color: active ? EbtlColors.coral : Colors.black87,
                    ),
                  ),
                  const SizedBox(height: 5),
                  AnimatedContainer(
                    duration: const Duration(milliseconds: 180),
                    width: active ? 28 : 0,
                    height: 3,
                    decoration: BoxDecoration(
                      color: EbtlColors.coral,
                      borderRadius: BorderRadius.circular(999),
                    ),
                  ),
                ],
              ),
            ),
          );
        }),
      ),
    );
  }
}
