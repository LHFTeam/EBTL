import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_svg/flutter_svg.dart';
import 'package:google_fonts/google_fonts.dart';

import '../../../core/theme/ebtl_colors.dart';
import '../../../models/order_detail_models.dart';
import '../../../services/api_service.dart';
import '../../../shared/widgets/detail_card.dart';

/// The code the customer shows at the cart to collect a pickup order.
///
/// Nothing leaves the cart until an attendant scans this, so the card holds
/// both forms of it: the QR to be scanned, and the six digits under it to read
/// out when a camera or a sunlit screen will not cooperate.
///
/// The code rotates, so this refreshes itself on the interval the backend asks
/// for. It also keeps watch on the order's status while it is open — the card
/// appears on its own when the cart marks the order ready, which is the moment
/// the customer is walking over.
class PickupCodeCard extends StatefulWidget {
  final String orderId;

  /// The order status the rest of the screen was drawn from. When the poll
  /// below sees a different one, the whole screen is stale and reloads.
  final String orderStatus;
  final VoidCallback onOrderMoved;

  const PickupCodeCard({
    super.key,
    required this.orderId,
    required this.orderStatus,
    required this.onOrderMoved,
  });

  @override
  State<PickupCodeCard> createState() => _PickupCodeCardState();
}

class _PickupCodeCardState extends State<PickupCodeCard>
    with WidgetsBindingObserver {
  /// Floor on the refresh interval, so a bad value from the backend cannot turn
  /// the card into a request loop.
  static const _minimumRefresh = Duration(seconds: 15);

  PickupCode? code;
  bool hasFailed = false;
  Timer? timer;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
    _load();
  }

  @override
  void dispose() {
    timer?.cancel();
    WidgetsBinding.instance.removeObserver(this);
    super.dispose();
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    // A backgrounded app has no screen to show a code on, so the timer stops
    // rather than refreshing a code nobody is looking at. Coming back re-reads
    // immediately, because whatever was on screen has almost certainly expired.
    if (state == AppLifecycleState.resumed) {
      _load();
    } else {
      timer?.cancel();
    }
  }

  Future<void> _load() async {
    try {
      final result = await ApiService.fetchOrderPickupCode(
        orderId: widget.orderId,
      );

      if (!mounted) return;

      setState(() {
        code = result;
        hasFailed = false;
      });

      // Keep polling either way. Telling the screen to reload replaces the
      // widget around this card but not the card itself, so dropping the timer
      // here would leave a mounted card that never refreshes its code again.
      _scheduleNext(result);

      if (result.status.isNotEmpty && result.status != widget.orderStatus) {
        widget.onOrderMoved();
      }
    } catch (_) {
      if (!mounted) return;

      // A missed refresh is not worth an error state of its own: the code on
      // screen is good for a little longer, and the next tick may well work. It
      // only becomes worth saying once there is nothing to show at all.
      setState(() => hasFailed = true);
      _scheduleNext(code);
    }
  }

  void _scheduleNext(PickupCode? current) {
    timer?.cancel();

    final requested = Duration(milliseconds: current?.refreshAfterMs ?? 30000);
    final interval = requested < _minimumRefresh ? _minimumRefresh : requested;

    timer = Timer(interval, _load);
  }

  @override
  Widget build(BuildContext context) {
    final current = code;

    if (current == null) {
      return hasFailed
          ? _PickupMessageCard(
              icon: Icons.wifi_off_rounded,
              message:
                  'We could not load your pickup code. Check your connection '
                  'and pull down to refresh.',
              onRetry: _load,
            )
          : const SizedBox.shrink();
    }

    if (current.isShowable) {
      return _PickupCodeReady(code: current, isStale: hasFailed);
    }

    if (current.isPending) {
      return _PickupMessageCard(
        icon: Icons.qr_code_2_rounded,
        message:
            current.message ??
            'Your pickup code appears here the moment your order is ready.',
      );
    }

    return const SizedBox.shrink();
  }
}

class _PickupCodeReady extends StatelessWidget {
  final PickupCode code;

  /// True when the last refresh failed. The code on screen may be a few seconds
  /// from expiring, so the customer is told rather than left wondering why an
  /// attendant's scan bounced.
  final bool isStale;

  const _PickupCodeReady({required this.code, required this.isStale});

  @override
  Widget build(BuildContext context) {
    final greeting = code.customerFirstName?.trim();

    return Padding(
      padding: const EdgeInsets.fromLTRB(22, 6, 22, 8),
      child: DetailCard(
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                const Icon(
                  Icons.qr_code_scanner_rounded,
                  size: 20,
                  color: EbtlColors.teal,
                ),
                const SizedBox(width: 8),
                Expanded(
                  child: Text(
                    greeting == null || greeting.isEmpty
                        ? 'Your pickup code'
                        : '$greeting, your order is ready',
                    maxLines: 2,
                    style: GoogleFonts.manrope(
                      fontSize: 17,
                      fontWeight: FontWeight.w900,
                      color: EbtlColors.navy,
                    ),
                  ),
                ),
              ],
            ),
            const SizedBox(height: 4),
            Text(
              code.instructions ?? 'Show this to the attendant at your cart.',
              style: GoogleFonts.manrope(
                fontSize: 13,
                height: 1.35,
                fontWeight: FontWeight.w600,
                color: EbtlColors.muted,
              ),
            ),
            const SizedBox(height: 14),

            // White plate under the QR whatever the card does: a scanner needs
            // the quiet zone around the code to stay light.
            Center(
              child: Container(
                padding: const EdgeInsets.all(12),
                decoration: BoxDecoration(
                  color: EbtlColors.white,
                  borderRadius: BorderRadius.circular(18),
                  border: Border.all(color: EbtlColors.border),
                ),
                child: SvgPicture.string(
                  code.qrSvg!,
                  width: 220,
                  height: 220,
                ),
              ),
            ),

            const SizedBox(height: 16),
            Center(
              child: Text(
                'OR READ OUT THIS CODE',
                style: GoogleFonts.manrope(
                  fontSize: 11,
                  fontWeight: FontWeight.w800,
                  letterSpacing: 0.14,
                  color: EbtlColors.muted,
                ),
              ),
            ),
            const SizedBox(height: 6),
            Center(
              child: Text(
                code.shortCode!,
                style: GoogleFonts.manrope(
                  fontSize: 32,
                  fontWeight: FontWeight.w900,
                  letterSpacing: 0.22,
                  color: EbtlColors.navy,
                ),
              ),
            ),

            if (isStale) ...[
              const SizedBox(height: 12),
              Text(
                'This code may be out of date — we could not reach EBTL to '
                'refresh it. Pull down to try again.',
                textAlign: TextAlign.center,
                style: GoogleFonts.manrope(
                  fontSize: 12,
                  height: 1.35,
                  fontWeight: FontWeight.w700,
                  color: EbtlColors.coral,
                ),
              ),
            ],
          ],
        ),
      ),
    );
  }
}

class _PickupMessageCard extends StatelessWidget {
  final IconData icon;
  final String message;
  final VoidCallback? onRetry;

  const _PickupMessageCard({
    required this.icon,
    required this.message,
    this.onRetry,
  });

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.fromLTRB(22, 6, 22, 8),
      child: DetailCard(
        child: Row(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Icon(icon, size: 20, color: EbtlColors.teal),
            const SizedBox(width: 10),
            Expanded(
              child: Text(
                message,
                style: GoogleFonts.manrope(
                  fontSize: 13,
                  height: 1.4,
                  fontWeight: FontWeight.w600,
                  color: EbtlColors.ink,
                ),
              ),
            ),
            if (onRetry != null)
              TextButton(
                onPressed: onRetry,
                child: Text(
                  'Retry',
                  style: GoogleFonts.manrope(
                    fontWeight: FontWeight.w900,
                    color: EbtlColors.teal,
                  ),
                ),
              ),
          ],
        ),
      ),
    );
  }
}
