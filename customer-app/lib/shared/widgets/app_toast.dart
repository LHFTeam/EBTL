import 'dart:async';

import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';

import '../../core/theme/ebtl_colors.dart';

/// Notification kind — drives the icon and accent color of [AppToastCard].
enum AppToastType { success, info, order, warning, error }

class _TypePalette {
  final Color accent;
  final Color chip;
  const _TypePalette(this.accent, this.chip);
}

const _typePalettes = <AppToastType, _TypePalette>{
  AppToastType.success: _TypePalette(EbtlColors.teal, EbtlColors.seafoam),
  AppToastType.info: _TypePalette(EbtlColors.teal, EbtlColors.seafoam),
  AppToastType.order: _TypePalette(EbtlColors.coral, EbtlColors.blush),
  AppToastType.warning: _TypePalette(Color(0xFF8A6A17), Color(0x6BE7BD68)),
  AppToastType.error: _TypePalette(EbtlColors.coral, EbtlColors.blush),
};

IconData _typeIcon(AppToastType type) {
  switch (type) {
    case AppToastType.success:
      return Icons.check_rounded;
    case AppToastType.order:
      return Icons.shopping_bag_outlined;
    case AppToastType.warning:
      return Icons.warning_amber_rounded;
    case AppToastType.error:
      return Icons.cancel_outlined;
    case AppToastType.info:
      return Icons.info_outline;
  }
}

/// The app's rich in-app popup notification: a floating card with an icon
/// chip (or [thumbnail]), title, message and an optional action, colored by
/// [type]. Shown near the top of the screen via [showAppToast].
///
/// Pairs with the compact, bottom-anchored [AppSnackbarPill] shown via
/// [showAppSnackBar], which is used for lightweight one-line confirmations.
class AppToastCard extends StatelessWidget {
  final AppToastType type;
  final String? title;
  final String? message;
  final String? actionText;
  final VoidCallback? onAction;
  final VoidCallback? onDismiss;
  final String? thumbnail;

  const AppToastCard({
    super.key,
    this.type = AppToastType.success,
    this.title,
    this.message,
    this.actionText,
    this.onAction,
    this.onDismiss,
    this.thumbnail,
  });

  @override
  Widget build(BuildContext context) {
    final palette = _typePalettes[type]!;
    return Container(
      constraints: const BoxConstraints(maxWidth: 440),
      padding: const EdgeInsets.fromLTRB(15, 14, 14, 14),
      decoration: BoxDecoration(
        color: EbtlColors.white.withValues(alpha: 0.96),
        borderRadius: BorderRadius.circular(20),
        border: Border.all(color: EbtlColors.border),
        boxShadow: [
          BoxShadow(
            color: Colors.black.withValues(alpha: 0.10),
            blurRadius: 22,
            offset: const Offset(0, 10),
          ),
        ],
      ),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          if (thumbnail != null)
            ClipRRect(
              borderRadius: BorderRadius.circular(12),
              child: Image.network(
                thumbnail!,
                width: 44,
                height: 44,
                fit: BoxFit.cover,
              ),
            )
          else
            Container(
              width: 40,
              height: 40,
              alignment: Alignment.center,
              decoration: BoxDecoration(
                color: palette.chip,
                shape: BoxShape.circle,
              ),
              child: Icon(_typeIcon(type), color: palette.accent, size: 22),
            ),
          const SizedBox(width: 13),
          Expanded(
            child: Padding(
              padding: const EdgeInsets.only(top: 1),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                mainAxisSize: MainAxisSize.min,
                children: [
                  if (title != null && title!.isNotEmpty)
                    Text(
                      title!,
                      style: GoogleFonts.manrope(
                        fontSize: 15,
                        height: 1.25,
                        fontWeight: FontWeight.w800,
                        color: EbtlColors.navy,
                      ),
                    ),
                  if (message != null && message!.isNotEmpty)
                    Padding(
                      padding: EdgeInsets.only(
                        top: (title != null && title!.isNotEmpty) ? 3 : 0,
                      ),
                      child: Text(
                        message!,
                        style: GoogleFonts.manrope(
                          fontSize: 13,
                          height: 1.4,
                          fontWeight: FontWeight.w600,
                          color: EbtlColors.muted,
                        ),
                      ),
                    ),
                  if (actionText != null)
                    Padding(
                      padding: const EdgeInsets.only(top: 7),
                      child: SizedBox(
                        height: 32,
                        child: ElevatedButton(
                          onPressed: onAction,
                          style: ElevatedButton.styleFrom(
                            backgroundColor: palette.accent,
                            foregroundColor: Colors.white,
                            elevation: 0,
                            padding: const EdgeInsets.symmetric(
                              horizontal: 14,
                            ),
                            shape: RoundedRectangleBorder(
                              borderRadius: BorderRadius.circular(12),
                            ),
                          ),
                          child: Text(
                            actionText!,
                            style: GoogleFonts.manrope(
                              fontWeight: FontWeight.w800,
                              fontSize: 13,
                            ),
                          ),
                        ),
                      ),
                    ),
                ],
              ),
            ),
          ),
          if (onDismiss != null)
            SizedBox(
              width: 26,
              height: 26,
              child: IconButton(
                padding: EdgeInsets.zero,
                constraints: const BoxConstraints(),
                visualDensity: VisualDensity.compact,
                onPressed: onDismiss,
                icon: const Icon(Icons.close, size: 18),
                color: EbtlColors.muted,
              ),
            ),
        ],
      ),
    );
  }
}

/// The app's compact bottom feedback: a single-line navy pill with an
/// optional action, shown via [showAppSnackBar]. See also [AppToastCard].
class AppSnackbarPill extends StatelessWidget {
  final String message;
  final String? actionText;
  final VoidCallback? onAction;
  final VoidCallback? onDismiss;

  const AppSnackbarPill({
    super.key,
    required this.message,
    this.actionText,
    this.onAction,
    this.onDismiss,
  });

  @override
  Widget build(BuildContext context) {
    return Container(
      constraints: const BoxConstraints(maxWidth: 440),
      padding: const EdgeInsets.fromLTRB(18, 13, 8, 13),
      decoration: BoxDecoration(
        color: EbtlColors.navy,
        borderRadius: BorderRadius.circular(18),
        boxShadow: [
          BoxShadow(
            color: Colors.black.withValues(alpha: 0.10),
            blurRadius: 22,
            offset: const Offset(0, 10),
          ),
        ],
      ),
      child: Row(
        children: [
          Expanded(
            child: Text(
              message,
              style: GoogleFonts.manrope(
                fontSize: 14,
                height: 1.35,
                fontWeight: FontWeight.w600,
                color: Colors.white,
              ),
            ),
          ),
          if (actionText != null)
            TextButton(
              onPressed: onAction,
              style: TextButton.styleFrom(
                foregroundColor: EbtlColors.gold,
                padding: const EdgeInsets.symmetric(
                  horizontal: 14,
                  vertical: 8,
                ),
                shape: RoundedRectangleBorder(
                  borderRadius: BorderRadius.circular(12),
                ),
              ),
              child: Text(
                actionText!.toUpperCase(),
                style: GoogleFonts.manrope(
                  fontWeight: FontWeight.w900,
                  fontSize: 13,
                  letterSpacing: 0.3,
                ),
              ),
            ),
          if (onDismiss != null)
            SizedBox(
              width: 30,
              height: 30,
              child: IconButton(
                padding: EdgeInsets.zero,
                constraints: const BoxConstraints(),
                visualDensity: VisualDensity.compact,
                onPressed: onDismiss,
                icon: const Icon(Icons.close, size: 19),
                color: Colors.white.withValues(alpha: 0.62),
              ),
            ),
        ],
      ),
    );
  }
}

/// Shows the app's standard compact feedback pill at the bottom of the
/// screen. This is the drop-in replacement for every plain-text
/// confirmation/error message in the app (cart updates, validation errors,
/// API failures, etc.) — same call signature as before, restyled.
void showAppSnackBar(
  BuildContext context,
  String message, {
  String? actionText,
  VoidCallback? onAction,
}) {
  final messenger = ScaffoldMessenger.of(context);
  messenger.hideCurrentSnackBar();
  messenger.showSnackBar(
    SnackBar(
      content: AppSnackbarPill(
        message: message,
        actionText: actionText,
        onAction: onAction == null
            ? null
            : () {
                messenger.hideCurrentSnackBar();
                onAction();
              },
        onDismiss: messenger.hideCurrentSnackBar,
      ),
      backgroundColor: Colors.transparent,
      elevation: 0,
      behavior: SnackBarBehavior.floating,
      padding: EdgeInsets.zero,
      margin: const EdgeInsets.fromLTRB(16, 0, 16, 16),
    ),
  );
}

class _ToastHandle {
  final OverlayEntry entry;
  final GlobalKey<_AnimatedToastState> key;
  Timer? autoDismissTimer;
  bool _removed = false;

  _ToastHandle(this.entry, this.key);

  void remove() {
    if (_removed) return;
    _removed = true;
    autoDismissTimer?.cancel();
    if (identical(_activeToastHandle, this)) {
      _activeToastHandle = null;
    }
    final state = key.currentState;
    if (state != null) {
      state.dismiss(entry.remove);
    } else {
      entry.remove();
    }
  }
}

_ToastHandle? _activeToastHandle;

/// Shows the app's rich in-app popup notification near the top of the
/// screen — icon chip, title, message and an optional action, colored by
/// [type]. Used for events that deserve more attention than the compact
/// [showAppSnackBar] pill (e.g. an order being ready, an incoming
/// notification). Only one toast is shown at a time.
void showAppToast(
  BuildContext context, {
  AppToastType type = AppToastType.info,
  String? title,
  String? message,
  String? actionText,
  VoidCallback? onAction,
  String? thumbnail,
  Duration duration = const Duration(seconds: 5),
}) {
  hideAppToast();

  final overlayState = Overlay.of(context, rootOverlay: true);
  final key = GlobalKey<_AnimatedToastState>();
  late final _ToastHandle handle;

  final entry = OverlayEntry(
    builder: (_) => _AnimatedToast(
      key: key,
      // The overlay sits outside the app's Material tree, so without this the
      // card's Text widgets inherit MaterialApp's error placeholder style and
      // render with a yellow double underline.
      child: Material(
        type: MaterialType.transparency,
        child: AppToastCard(
          type: type,
          title: title,
          message: message,
          actionText: actionText,
          thumbnail: thumbnail,
          onAction: onAction == null
              ? null
              : () {
                  onAction();
                  handle.remove();
                },
          onDismiss: () => handle.remove(),
        ),
      ),
    ),
  );

  handle = _ToastHandle(entry, key);
  _activeToastHandle = handle;
  overlayState.insert(entry);
  handle.autoDismissTimer = Timer(duration, handle.remove);
}

/// Dismisses the currently showing [showAppToast] popup, if any.
void hideAppToast() {
  _activeToastHandle?.remove();
}

class _AnimatedToast extends StatefulWidget {
  final Widget child;

  const _AnimatedToast({super.key, required this.child});

  @override
  State<_AnimatedToast> createState() => _AnimatedToastState();
}

class _AnimatedToastState extends State<_AnimatedToast>
    with SingleTickerProviderStateMixin {
  late final AnimationController _controller = AnimationController(
    vsync: this,
    duration: const Duration(milliseconds: 220),
  )..forward();

  Future<void> dismiss(VoidCallback onDismissed) async {
    if (!mounted) {
      onDismissed();
      return;
    }
    await _controller.reverse();
    onDismissed();
  }

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final curved = CurvedAnimation(parent: _controller, curve: Curves.easeOut);
    return Positioned(
      top: 12,
      left: 14,
      right: 14,
      child: SafeArea(
        bottom: false,
        child: FadeTransition(
          opacity: curved,
          child: SlideTransition(
            position: Tween<Offset>(
              begin: const Offset(0, -0.15),
              end: Offset.zero,
            ).animate(curved),
            child: widget.child,
          ),
        ),
      ),
    );
  }
}
