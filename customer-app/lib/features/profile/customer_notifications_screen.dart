import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';

import '../../core/theme/ebtl_colors.dart';
import '../../models/notification_models.dart';
import '../../services/api_service.dart';
import '../../shared/widgets/app_state_widgets.dart';
import '../../shared/widgets/detail_card.dart';
import 'widgets/profile_widgets.dart';

class CustomerNotificationsScreen extends StatefulWidget {
  /// Reports the backend's authoritative `unread_count` after every load,
  /// so the shell can refresh its badge without an extra request.
  final ValueChanged<int>? onUnreadCountChanged;

  const CustomerNotificationsScreen({super.key, this.onUnreadCountChanged});

  @override
  State<CustomerNotificationsScreen> createState() =>
      _CustomerNotificationsScreenState();
}

class _CustomerNotificationsScreenState
    extends State<CustomerNotificationsScreen> {
  late Future<CustomerNotificationsResponse> notificationsFuture;

  @override
  void initState() {
    super.initState();
    notificationsFuture = _load();
  }

  Future<CustomerNotificationsResponse> _load() {
    final future = ApiService.fetchCustomerNotifications();

    // Side channel only: the FutureBuilder still owns error rendering.
    future.then((response) {
      if (!mounted) return;
      widget.onUnreadCountChanged?.call(response.unreadCount);
    }).catchError((_) {});

    return future;
  }

  void reload() {
    setState(() {
      notificationsFuture = _load();
    });
  }

  Future<void> refresh() async {
    final future = _load();
    setState(() => notificationsFuture = future);
    await future;
  }

  Future<void> markRead(CustomerNotification notification) async {
    if (!notification.isUnread) return;

    try {
      await ApiService.markCustomerNotificationRead(
        notificationId: notification.id,
      );
    } catch (error) {
      if (!mounted) return;
      showAppSnackBar(context, 'Could not mark as read: $error');
      return;
    }

    if (mounted) reload();
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: EbtlColors.cream,
      body: SafeArea(
        child: FutureBuilder<CustomerNotificationsResponse>(
          future: notificationsFuture,
          builder: (context, snapshot) {
            final notifications =
                snapshot.data?.notifications ?? const <CustomerNotification>[];

            return RefreshIndicator(
              color: EbtlColors.coral,
              onRefresh: refresh,
              child: CustomScrollView(
                physics: const AlwaysScrollableScrollPhysics(),
                slivers: [
                  SliverToBoxAdapter(
                    child: ProfileSubScreenHeader(
                      title: 'Notifications',
                      onBack: () => Navigator.of(context).pop(),
                    ),
                  ),
                  if (snapshot.connectionState == ConnectionState.waiting)
                    const EbtlLoadingSliver(label: 'Loading notifications...')
                  else if (snapshot.hasError)
                    SliverToBoxAdapter(
                      child: InlineErrorCard(
                        message: snapshot.error.toString(),
                        onRetry: reload,
                      ),
                    )
                  else if (notifications.isEmpty)
                    const SliverFillRemaining(
                      hasScrollBody: false,
                      child: _EmptyNotificationsCard(),
                    )
                  else
                    SliverPadding(
                      padding: const EdgeInsets.fromLTRB(22, 4, 22, 24),
                      sliver: SliverList.separated(
                        itemCount: notifications.length,
                        separatorBuilder: (_, _) => const SizedBox(height: 10),
                        itemBuilder: (context, index) {
                          final notification = notifications[index];

                          return _NotificationCard(
                            notification: notification,
                            onTap: () => markRead(notification),
                          );
                        },
                      ),
                    ),
                ],
              ),
            );
          },
        ),
      ),
    );
  }
}

class _EmptyNotificationsCard extends StatelessWidget {
  const _EmptyNotificationsCard();

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.all(22),
      child: Center(
        child: DetailCard(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              const Icon(
                Icons.notifications_none,
                color: EbtlColors.teal,
                size: 42,
              ),
              const SizedBox(height: 12),
              Text(
                'No notifications yet',
                style: GoogleFonts.playfairDisplay(
                  fontSize: 27,
                  fontWeight: FontWeight.w800,
                  color: EbtlColors.navy,
                ),
              ),
              const SizedBox(height: 8),
              Text(
                'Order updates and pickup alerts will appear here.',
                textAlign: TextAlign.center,
                style: GoogleFonts.manrope(
                  fontSize: 14,
                  height: 1.35,
                  fontWeight: FontWeight.w600,
                  color: EbtlColors.muted,
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

class _NotificationCard extends StatelessWidget {
  final CustomerNotification notification;
  final VoidCallback onTap;

  const _NotificationCard({required this.notification, required this.onTap});

  @override
  Widget build(BuildContext context) {
    return InkWell(
      borderRadius: BorderRadius.circular(20),
      onTap: onTap,
      child: DetailCard(
        child: Row(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Container(
              width: 42,
              height: 42,
              decoration: BoxDecoration(
                color: notification.isUnread
                    ? EbtlColors.coral.withValues(alpha: 0.12)
                    : EbtlColors.seafoam.withValues(alpha: 0.55),
                shape: BoxShape.circle,
              ),
              child: Icon(
                notification.isUnread
                    ? Icons.notifications_active_outlined
                    : Icons.notifications_none,
                color: notification.isUnread
                    ? EbtlColors.coral
                    : EbtlColors.teal,
                size: 21,
              ),
            ),
            const SizedBox(width: 12),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Row(
                    children: [
                      Expanded(
                        child: Text(
                          notification.title,
                          style: GoogleFonts.manrope(
                            fontSize: 15,
                            fontWeight: FontWeight.w900,
                            color: EbtlColors.navy,
                          ),
                        ),
                      ),
                      if (notification.isUnread)
                        Container(
                          width: 8,
                          height: 8,
                          decoration: const BoxDecoration(
                            color: EbtlColors.coral,
                            shape: BoxShape.circle,
                          ),
                        ),
                    ],
                  ),
                  const SizedBox(height: 5),
                  Text(
                    notification.body,
                    style: GoogleFonts.manrope(
                      fontSize: 13,
                      height: 1.35,
                      fontWeight: FontWeight.w600,
                      color: EbtlColors.ink,
                    ),
                  ),
                  if (notification.orderNumber?.isNotEmpty == true) ...[
                    const SizedBox(height: 8),
                    Text(
                      notification.orderNumber!,
                      style: GoogleFonts.manrope(
                        fontSize: 12,
                        fontWeight: FontWeight.w900,
                        color: EbtlColors.teal,
                      ),
                    ),
                  ],
                  const SizedBox(height: 6),
                  Text(
                    notification.createdAtLabel,
                    style: GoogleFonts.manrope(
                      fontSize: 12,
                      fontWeight: FontWeight.w600,
                      color: EbtlColors.muted,
                    ),
                  ),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }
}
