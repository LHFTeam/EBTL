import 'package:flutter/material.dart';

/// A modal page route that slides its [page] up from the bottom of the screen
/// and presents it as a rounded-top sheet over a dimmed copy of whatever is
/// behind it — the way an iOS bottom sheet does.
///
/// Cocktail and product detail pages use this instead of the default
/// right-to-left [MaterialPageRoute] push, so opening one feels like a sheet
/// sliding up rather than a full page swap. The status-bar strip is left
/// uncovered so the screen behind peeks through at the very top.
Route<T> slideUpModalRoute<T>(Widget page) {
  return PageRouteBuilder<T>(
    // Keep the route below painted so it shows through the peek gap at the top.
    opaque: false,
    barrierColor: Colors.black.withValues(alpha: 0.32),
    transitionDuration: const Duration(milliseconds: 360),
    reverseTransitionDuration: const Duration(milliseconds: 280),
    pageBuilder: (context, animation, secondaryAnimation) {
      // Leave the status-bar inset uncovered so the screen behind peeks through
      // at the top. The sheet content then starts below it, so its own top
      // padding is removed to avoid double-counting that inset.
      final topGap = MediaQuery.of(context).padding.top;
      return Padding(
        padding: EdgeInsets.only(top: topGap),
        child: ClipRRect(
          borderRadius: const BorderRadius.vertical(top: Radius.circular(24)),
          child: MediaQuery.removePadding(
            context: context,
            removeTop: true,
            child: page,
          ),
        ),
      );
    },
    transitionsBuilder: (context, animation, secondaryAnimation, child) {
      final curved = CurvedAnimation(
        parent: animation,
        curve: Curves.easeOutCubic,
        reverseCurve: Curves.easeInCubic,
      );
      return SlideTransition(
        position: Tween<Offset>(
          begin: const Offset(0, 1),
          end: Offset.zero,
        ).animate(curved),
        child: child,
      );
    },
  );
}
