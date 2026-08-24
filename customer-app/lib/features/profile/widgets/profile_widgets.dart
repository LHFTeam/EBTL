import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';

import '../../../core/theme/ebtl_colors.dart';
import '../../../models/profile_models.dart';
import '../../../shared/widgets/brand_widgets.dart';
import '../../../shared/widgets/detail_card.dart';
import '../../../shared/widgets/ebtl_loading_graphic.dart';
import '../../../shared/widgets/network_or_asset_image.dart';

class ProfileLoadingState extends StatelessWidget {
  const ProfileLoadingState({super.key});

  @override
  Widget build(BuildContext context) {
    return CustomScrollView(
      slivers: const [
        SliverToBoxAdapter(child: ProfileHeaderSkeleton()),
        SliverToBoxAdapter(
          child: Padding(
            padding: EdgeInsets.all(28),
            child: EbtlLoadingGraphic(label: 'Loading your profile...'),
          ),
        ),
      ],
    );
  }
}

class ProfileHeaderSkeleton extends StatelessWidget {
  const ProfileHeaderSkeleton({super.key});

  @override
  Widget build(BuildContext context) {
    return ProfileHeader(onNotifications: () {}, onSettings: () {});
  }
}

class ProfileHeader extends StatelessWidget {
  final VoidCallback onNotifications;
  final VoidCallback onSettings;
  final int unreadCount;

  const ProfileHeader({
    super.key,
    required this.onNotifications,
    required this.onSettings,
    this.unreadCount = 0,
  });

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.fromLTRB(22, 14, 22, 8),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.center,
        children: [
          Expanded(
            child: Text(
              'Profile',
              style: GoogleFonts.playfairDisplay(
                fontSize: 41,
                height: 1,
                fontWeight: FontWeight.w800,
                color: EbtlColors.navy,
              ),
            ),
          ),
          Stack(
            clipBehavior: Clip.none,
            children: [
              ProfileCircleIconButton(
                icon: Icons.notifications_none,
                onTap: onNotifications,
              ),
              if (unreadCount > 0)
                Positioned(
                  top: -2,
                  right: -2,
                  child: IgnorePointer(
                    child: Container(
                      constraints: const BoxConstraints(minWidth: 18),
                      height: 18,
                      padding: const EdgeInsets.symmetric(horizontal: 4),
                      alignment: Alignment.center,
                      decoration: BoxDecoration(
                        color: EbtlColors.coral,
                        borderRadius: BorderRadius.circular(999),
                        border: Border.all(
                          color: EbtlColors.white,
                          width: 1.5,
                        ),
                      ),
                      child: Text(
                        unreadCount > 9 ? '9+' : '$unreadCount',
                        style: GoogleFonts.manrope(
                          fontSize: 10,
                          height: 1,
                          fontWeight: FontWeight.w900,
                          color: EbtlColors.white,
                        ),
                      ),
                    ),
                  ),
                ),
            ],
          ),
          const SizedBox(width: 12),
          ProfileCircleIconButton(
            icon: Icons.settings_outlined,
            onTap: onSettings,
          ),
        ],
      ),
    );
  }
}

class ProfileCircleIconButton extends StatelessWidget {
  final IconData icon;
  final VoidCallback onTap;

  const ProfileCircleIconButton({
    super.key,
    required this.icon,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    return Material(
      color: EbtlColors.white.withValues(alpha: 0.78),
      shape: const CircleBorder(),
      child: InkWell(
        onTap: onTap,
        customBorder: const CircleBorder(),
        child: SizedBox(
          width: 50,
          height: 50,
          child: Icon(icon, color: EbtlColors.navy, size: 25),
        ),
      ),
    );
  }
}

class ProfileIdentityCard extends StatelessWidget {
  final CustomerProfile profile;
  final VoidCallback onTap;

  const ProfileIdentityCard({
    super.key,
    required this.profile,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.fromLTRB(22, 16, 22, 18),
      child: Material(
        color: Colors.transparent,
        child: InkWell(
          onTap: onTap,
          borderRadius: BorderRadius.circular(20),
          child: Ink(
            padding: const EdgeInsets.fromLTRB(17, 16, 18, 16),
            decoration: BoxDecoration(
              color: EbtlColors.white.withValues(alpha: 0.90),
              borderRadius: BorderRadius.circular(20),
              border: Border.all(color: EbtlColors.border),
              boxShadow: [
                BoxShadow(
                  color: Colors.black.withValues(alpha: 0.035),
                  blurRadius: 18,
                  offset: const Offset(0, 8),
                ),
              ],
            ),
            child: Row(
              children: [
                ProfileAvatar(profile: profile, size: 82),
                const SizedBox(width: 18),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        profile.displayName,
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: GoogleFonts.manrope(
                          fontSize: 19,
                          height: 1.15,
                          fontWeight: FontWeight.w900,
                          color: EbtlColors.navy,
                        ),
                      ),
                      const SizedBox(height: 10),
                      Text(
                        profile.displayEmail,
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: GoogleFonts.manrope(
                          fontSize: 14,
                          fontWeight: FontWeight.w600,
                          color: EbtlColors.ink,
                        ),
                      ),
                      const SizedBox(height: 8),
                      Text(
                        profile.displayPhone,
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: GoogleFonts.manrope(
                          fontSize: 14,
                          fontWeight: FontWeight.w800,
                          color: EbtlColors.teal,
                        ),
                      ),
                    ],
                  ),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}

String profileAvatarAssetForGender(String? gender) {
  switch (CustomerProfile.normalizeGender(gender)) {
    case 'male':
      return 'assets/profile/male-profile.webp';
    case 'female':
      return 'assets/profile/female-profile.webp';
    default:
      return 'assets/profile/default-profile.webp';
  }
}

class ProfileAvatar extends StatelessWidget {
  final CustomerProfile profile;
  final double size;

  const ProfileAvatar({super.key, required this.profile, required this.size});

  @override
  Widget build(BuildContext context) {
    final fallback = Container(
      color: EbtlColors.seafoam,
      child: const Icon(Icons.person, color: EbtlColors.navy, size: 38),
    );

    return ClipOval(
      child: SizedBox(
        width: size,
        height: size,
        child: Image.asset(
          profileAvatarAssetForGender(profile.gender),
          fit: BoxFit.cover,
          errorBuilder: (_, _, _) => fallback,
        ),
      ),
    );
  }
}

class ProfileOrdersSection extends StatelessWidget {
  final ProfileRecentOrders recentOrders;
  final VoidCallback? onViewAll;
  final ValueChanged<ProfileOrder>? onOpenOrder;

  const ProfileOrdersSection({
    super.key,
    required this.recentOrders,
    required this.onViewAll,
    this.onOpenOrder,
  });

  @override
  Widget build(BuildContext context) {
    final firstOrder = recentOrders.items.isEmpty
        ? null
        : recentOrders.items.first;

    return Padding(
      padding: const EdgeInsets.fromLTRB(22, 0, 22, 18),
      child: Column(
        children: [
          ProfileSectionHeader(
            title: recentOrders.title,
            actionText: 'View all',
            onAction: onViewAll,
          ),
          if (firstOrder == null)
            const ProfileEmptyOrdersCard()
          else
            ProfileOrderCard(
              order: firstOrder,
              onTap: onOpenOrder == null
                  ? null
                  : () => onOpenOrder!(firstOrder),
            ),
        ],
      ),
    );
  }
}

class ProfileSectionHeader extends StatelessWidget {
  final String title;
  final String? actionText;
  final VoidCallback? onAction;

  const ProfileSectionHeader({
    super.key,
    required this.title,
    this.actionText,
    this.onAction,
  });

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 10),
      child: Row(
        children: [
          Expanded(
            child: Text(
              title,
              style: GoogleFonts.playfairDisplay(
                fontSize: 22,
                height: 1,
                fontWeight: FontWeight.w800,
                color: EbtlColors.navy,
              ),
            ),
          ),
          if (actionText != null)
            TextButton(
              onPressed: onAction,
              style: TextButton.styleFrom(
                foregroundColor: onAction == null
                    ? EbtlColors.muted
                    : EbtlColors.teal,
                padding: EdgeInsets.zero,
                textStyle: GoogleFonts.manrope(
                  fontSize: 13,
                  fontWeight: FontWeight.w800,
                ),
              ),
              child: Row(
                mainAxisSize: MainAxisSize.min,
                children: [
                  Text(actionText!),
                  const SizedBox(width: 2),
                  const Icon(Icons.chevron_right, size: 21),
                ],
              ),
            ),
        ],
      ),
    );
  }
}

class ProfileOrderCard extends StatelessWidget {
  final ProfileOrder order;
  final VoidCallback? onTap;

  const ProfileOrderCard({super.key, required this.order, this.onTap});

  @override
  Widget build(BuildContext context) {
    final card = Container(
      height: 103,
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: EbtlColors.white.withValues(alpha: 0.92),
        borderRadius: BorderRadius.circular(18),
        border: Border.all(color: EbtlColors.border),
        boxShadow: [
          BoxShadow(
            color: Colors.black.withValues(alpha: 0.035),
            blurRadius: 18,
            offset: const Offset(0, 8),
          ),
        ],
      ),
      child: Row(
        children: [
          ClipRRect(
            borderRadius: BorderRadius.circular(12),
            child: SizedBox(
              width: 78,
              height: 78,
              child: NetworkOrAssetImage(
                imageUrl: order.orderImageUrl,
                asset: 'assets/images/cocktail_placeholder.jpg',
                fit: BoxFit.cover,
              ),
            ),
          ),
          const SizedBox(width: 14),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              mainAxisAlignment: MainAxisAlignment.center,
              children: [
                Text(
                  'Order #${order.displayOrderNumber}',
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: GoogleFonts.manrope(
                    fontSize: 14,
                    fontWeight: FontWeight.w900,
                    color: EbtlColors.navy,
                  ),
                ),
                const SizedBox(height: 9),
                Text(
                  order.displayLocation,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: GoogleFonts.manrope(
                    fontSize: 13,
                    fontWeight: FontWeight.w600,
                    color: EbtlColors.ink,
                  ),
                ),
                const SizedBox(height: 6),
                Text(
                  order.displayTime,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: GoogleFonts.manrope(
                    fontSize: 13,
                    fontWeight: FontWeight.w700,
                    color: EbtlColors.muted,
                  ),
                ),
              ],
            ),
          ),
          const SizedBox(width: 10),
          Column(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            crossAxisAlignment: CrossAxisAlignment.end,
            children: [
              ProfileStatusBadge(order: order),
              const Icon(Icons.chevron_right, color: EbtlColors.navy, size: 25),
            ],
          ),
        ],
      ),
    );

    if (onTap == null) return card;

    return Material(
      color: Colors.transparent,
      child: InkWell(
        onTap: onTap,
        borderRadius: BorderRadius.circular(18),
        child: card,
      ),
    );
  }
}

class ProfileStatusBadge extends StatelessWidget {
  final ProfileOrder order;

  const ProfileStatusBadge({super.key, required this.order});

  @override
  Widget build(BuildContext context) {
    final status = order.status.toLowerCase();
    final label = profileStatusLabel(order);
    final backgroundColor = status == 'ready' || status == 'completed'
        ? EbtlColors.seafoam.withValues(alpha: 0.68)
        : status == 'cancelled' || status == 'refunded'
        ? EbtlColors.blush.withValues(alpha: 0.68)
        : EbtlColors.sand.withValues(alpha: 0.72);
    final textColor = status == 'cancelled' || status == 'refunded'
        ? EbtlColors.coral
        : EbtlColors.teal;

    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 5),
      decoration: BoxDecoration(
        color: backgroundColor,
        borderRadius: BorderRadius.circular(999),
      ),
      child: Text(
        label,
        maxLines: 1,
        overflow: TextOverflow.ellipsis,
        style: GoogleFonts.manrope(
          fontSize: 10,
          fontWeight: FontWeight.w900,
          color: textColor,
        ),
      ),
    );
  }
}

class ProfileEmptyOrdersCard extends StatelessWidget {
  const ProfileEmptyOrdersCard({super.key});

  @override
  Widget build(BuildContext context) {
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.all(18),
      decoration: BoxDecoration(
        color: EbtlColors.white.withValues(alpha: 0.90),
        borderRadius: BorderRadius.circular(18),
        border: Border.all(color: EbtlColors.border),
      ),
      child: Row(
        children: [
          Container(
            width: 52,
            height: 52,
            decoration: BoxDecoration(
              color: EbtlColors.seafoam.withValues(alpha: 0.65),
              borderRadius: BorderRadius.circular(16),
            ),
            child: const Icon(
              Icons.receipt_long_outlined,
              color: EbtlColors.navy,
            ),
          ),
          const SizedBox(width: 14),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  'No orders yet.',
                  style: GoogleFonts.manrope(
                    fontSize: 15,
                    fontWeight: FontWeight.w900,
                    color: EbtlColors.navy,
                  ),
                ),
                const SizedBox(height: 4),
                Text(
                  'Your beach-day essentials will appear here.',
                  style: GoogleFonts.manrope(
                    fontSize: 12,
                    height: 1.3,
                    fontWeight: FontWeight.w600,
                    color: EbtlColors.muted,
                  ),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}

class ProfileQuickLinksSection extends StatelessWidget {
  final List<ProfileQuickLink> links;
  final ValueChanged<ProfileQuickLink> onTapLink;

  /// The shell's live unread count. The profile payload carries its own
  /// `notifications` count, but it is only as fresh as the last profile fetch —
  /// reading the notifications marks them read while this screen stays mounted,
  /// which would leave a stale badge on the tile until a pull-to-refresh. The
  /// live count is what the header badge already uses, so the two agree.
  final int unreadNotificationCount;

  const ProfileQuickLinksSection({
    super.key,
    required this.links,
    required this.onTapLink,
    this.unreadNotificationCount = 0,
  });

  /// Server copy for the notifications tile when nothing is unread.
  static const String _notificationsSubtitle =
      'Order updates and pickup alerts';

  /// The "3 unread" subtitle the backend sends alongside the count. Matching it
  /// means the fallback copy only replaces a stale unread line, never a
  /// subtitle the backend meant to show.
  static final RegExp _unreadSubtitlePattern = RegExp(r'^\d+ unread$');

  /// Links that are built but not launched yet. Addresses only exist to manage
  /// delivery addresses, and delivery is still behind "Coming soon" in the
  /// cart, so the tile stays hidden. Filtering here — rather than dropping the
  /// entry from [defaultProfileQuickLinks] — also hides the tile when the
  /// backend payload sends it, and re-enabling it is a one-line change.
  static const Set<String> _hiddenLinkKeys = {'addresses'};

  ProfileQuickLink _withLiveUnreadCount(ProfileQuickLink link) {
    if (link.key != 'notifications') return link;

    final stale = (link.subtitle ?? '').trim();
    final subtitle = unreadNotificationCount > 0
        ? '$unreadNotificationCount unread'
        : (_unreadSubtitlePattern.hasMatch(stale)
              ? _notificationsSubtitle
              : link.subtitle);

    return ProfileQuickLink(
      key: link.key,
      title: link.title,
      subtitle: subtitle,
      endpoint: link.endpoint,
      enabled: link.enabled,
      placeholder: link.placeholder,
      count: unreadNotificationCount,
    );
  }

  @override
  Widget build(BuildContext context) {
    final effectiveLinks = (links.isEmpty ? defaultProfileQuickLinks : links)
        .where((link) => !_hiddenLinkKeys.contains(link.key))
        .map(_withLiveUnreadCount)
        .toList();

    // Nothing left to link to once the hidden keys are filtered out — an empty
    // bordered card under a "Quick Links" header would just read as a bug.
    if (effectiveLinks.isEmpty) return const SizedBox.shrink();

    return Padding(
      padding: const EdgeInsets.fromLTRB(22, 0, 22, 18),
      child: Column(
        children: [
          const ProfileSectionHeader(title: 'Quick Links'),
          Container(
            decoration: BoxDecoration(
              color: EbtlColors.white.withValues(alpha: 0.92),
              borderRadius: BorderRadius.circular(18),
              border: Border.all(color: EbtlColors.border),
              boxShadow: [
                BoxShadow(
                  color: Colors.black.withValues(alpha: 0.035),
                  blurRadius: 18,
                  offset: const Offset(0, 8),
                ),
              ],
            ),
            child: Column(
              children: List.generate(effectiveLinks.length, (index) {
                final link = effectiveLinks[index];
                return ProfileQuickLinkTile(
                  link: link,
                  isLast: index == effectiveLinks.length - 1,
                  onTap: () => onTapLink(link),
                );
              }),
            ),
          ),
        ],
      ),
    );
  }
}

class ProfileQuickLinkTile extends StatelessWidget {
  final ProfileQuickLink link;
  final bool isLast;
  final VoidCallback onTap;

  const ProfileQuickLinkTile({
    super.key,
    required this.link,
    required this.isLast,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    final icon = profileQuickLinkIcon(link.key);
    final iconColor = link.key == 'favorite_cocktails'
        ? EbtlColors.coral
        : EbtlColors.navy;

    return Material(
      color: Colors.transparent,
      child: InkWell(
        onTap: onTap,
        child: Column(
          children: [
            Padding(
              padding: const EdgeInsets.fromLTRB(16, 13, 13, 13),
              child: Row(
                children: [
                  Icon(icon, color: iconColor, size: 26),
                  const SizedBox(width: 18),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Row(
                          children: [
                            Flexible(
                              child: Text(
                                link.title,
                                maxLines: 1,
                                overflow: TextOverflow.ellipsis,
                                style: GoogleFonts.manrope(
                                  fontSize: 15,
                                  fontWeight: FontWeight.w900,
                                  color: EbtlColors.navy,
                                ),
                              ),
                            ),
                            if (link.count != null && link.count! > 0) ...[
                              const SizedBox(width: 7),
                              Container(
                                padding: const EdgeInsets.symmetric(
                                  horizontal: 7,
                                  vertical: 3,
                                ),
                                decoration: BoxDecoration(
                                  color: EbtlColors.seafoam.withValues(
                                    alpha: 0.72,
                                  ),
                                  borderRadius: BorderRadius.circular(999),
                                ),
                                child: Text(
                                  link.count.toString(),
                                  style: GoogleFonts.manrope(
                                    fontSize: 10,
                                    fontWeight: FontWeight.w900,
                                    color: EbtlColors.navy,
                                  ),
                                ),
                              ),
                            ],
                          ],
                        ),
                        if ((link.subtitle ?? '').trim().isNotEmpty) ...[
                          const SizedBox(height: 3),
                          Text(
                            link.subtitle!.trim(),
                            maxLines: 1,
                            overflow: TextOverflow.ellipsis,
                            style: GoogleFonts.manrope(
                              fontSize: 12,
                              fontWeight: FontWeight.w600,
                              color: EbtlColors.muted,
                            ),
                          ),
                        ],
                      ],
                    ),
                  ),
                  const SizedBox(width: 12),
                  const Icon(
                    Icons.chevron_right,
                    color: EbtlColors.navy,
                    size: 25,
                  ),
                ],
              ),
            ),
            if (!isLast)
              Padding(
                padding: const EdgeInsets.only(left: 63, right: 16),
                child: Divider(
                  height: 1,
                  color: EbtlColors.border.withValues(alpha: 0.95),
                ),
              ),
          ],
        ),
      ),
    );
  }
}

class ProfileBrandMessageCard extends StatelessWidget {
  final ProfileBrandMessage brandMessage;

  const ProfileBrandMessageCard({super.key, required this.brandMessage});

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.fromLTRB(22, 0, 22, 18),
      child: Container(
        height: 79,
        padding: const EdgeInsets.symmetric(horizontal: 18, vertical: 14),
        decoration: BoxDecoration(
          color: EbtlColors.sand.withValues(alpha: 0.42),
          borderRadius: BorderRadius.circular(18),
          border: Border.all(color: EbtlColors.border),
        ),
        child: Row(
          children: [
            Text('🍹', style: GoogleFonts.manrope(fontSize: 28)),
            const SizedBox(width: 16),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                mainAxisAlignment: MainAxisAlignment.center,
                children: [
                  Text(
                    brandMessage.title,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: GoogleFonts.manrope(
                      fontSize: 15,
                      fontWeight: FontWeight.w700,
                      color: EbtlColors.navy,
                    ),
                  ),
                  const SizedBox(height: 2),
                  Text(
                    brandMessage.accent,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: GoogleFonts.playfairDisplay(
                      fontSize: 18,
                      height: 1,
                      fontWeight: FontWeight.w800,
                      fontStyle: FontStyle.italic,
                      color: EbtlColors.coral,
                    ),
                  ),
                ],
              ),
            ),
            const SizedBox(width: 10),
            CustomPaint(
              size: const Size(78, 43),
              painter: ProfileBeachLinePainter(),
            ),
          ],
        ),
      ),
    );
  }
}

class ProfileBeachLinePainter extends CustomPainter {
  @override
  void paint(Canvas canvas, Size size) {
    final paint = Paint()
      ..color = EbtlColors.coral.withValues(alpha: 0.42)
      ..strokeWidth = 1.1
      ..style = PaintingStyle.stroke
      ..strokeCap = StrokeCap.round;

    final baseY = size.height - 7;
    canvas.drawLine(Offset(2, baseY), Offset(size.width - 2, baseY), paint);

    final trunk = Path()
      ..moveTo(size.width * 0.42, baseY)
      ..quadraticBezierTo(
        size.width * 0.43,
        size.height * 0.55,
        size.width * 0.52,
        size.height * 0.34,
      );
    canvas.drawPath(trunk, paint);

    final leaf1 = Path()
      ..moveTo(size.width * 0.52, size.height * 0.34)
      ..quadraticBezierTo(
        size.width * 0.35,
        size.height * 0.28,
        size.width * 0.24,
        size.height * 0.45,
      );
    final leaf2 = Path()
      ..moveTo(size.width * 0.52, size.height * 0.34)
      ..quadraticBezierTo(
        size.width * 0.62,
        size.height * 0.20,
        size.width * 0.78,
        size.height * 0.26,
      );
    final leaf3 = Path()
      ..moveTo(size.width * 0.52, size.height * 0.34)
      ..quadraticBezierTo(
        size.width * 0.55,
        size.height * 0.20,
        size.width * 0.49,
        size.height * 0.08,
      );
    canvas.drawPath(leaf1, paint);
    canvas.drawPath(leaf2, paint);
    canvas.drawPath(leaf3, paint);

    final sunPaint = Paint()
      ..color = EbtlColors.coral.withValues(alpha: 0.36)
      ..strokeWidth = 1.1
      ..style = PaintingStyle.stroke
      ..strokeCap = StrokeCap.round;
    canvas.drawArc(
      Rect.fromCircle(
        center: Offset(size.width * 0.86, size.height * 0.32),
        radius: 7,
      ),
      3.6,
      2.0,
      false,
      sunPaint,
    );
  }

  @override
  bool shouldRepaint(covariant CustomPainter oldDelegate) => false;
}

class ProfileLogoutButton extends StatelessWidget {
  final bool isLoading;
  final VoidCallback onTap;

  const ProfileLogoutButton({
    super.key,
    required this.isLoading,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.fromLTRB(22, 0, 22, 0),
      child: Material(
        color: Colors.transparent,
        child: InkWell(
          onTap: isLoading ? null : onTap,
          borderRadius: BorderRadius.circular(18),
          child: Ink(
            height: 61,
            padding: const EdgeInsets.symmetric(horizontal: 18),
            decoration: BoxDecoration(
              color: EbtlColors.white.withValues(alpha: 0.92),
              borderRadius: BorderRadius.circular(18),
              border: Border.all(color: EbtlColors.border),
              boxShadow: [
                BoxShadow(
                  color: Colors.black.withValues(alpha: 0.035),
                  blurRadius: 18,
                  offset: const Offset(0, 8),
                ),
              ],
            ),
            child: Row(
              children: [
                if (isLoading)
                  const SizedBox(
                    width: 23,
                    height: 23,
                    child: CircularProgressIndicator(
                      color: EbtlColors.coral,
                      strokeWidth: 2,
                    ),
                  )
                else
                  const Icon(Icons.logout, color: EbtlColors.coral, size: 26),
                const SizedBox(width: 18),
                Expanded(
                  child: Text(
                    isLoading ? 'Logging out...' : 'Log Out',
                    style: GoogleFonts.manrope(
                      fontSize: 16,
                      fontWeight: FontWeight.w900,
                      color: EbtlColors.coral,
                    ),
                  ),
                ),
                const Icon(
                  Icons.chevron_right,
                  color: EbtlColors.coral,
                  size: 25,
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}

class ProfileGenderSelector extends StatelessWidget {
  final String? selectedGender;
  final ValueChanged<String?> onChanged;

  const ProfileGenderSelector({
    super.key,
    required this.selectedGender,
    required this.onChanged,
  });

  @override
  Widget build(BuildContext context) {
    final normalizedGender = CustomerProfile.normalizeGender(selectedGender);

    return Container(
      width: double.infinity,
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(
        color: EbtlColors.cream.withValues(alpha: 0.62),
        borderRadius: BorderRadius.circular(18),
        border: Border.all(color: EbtlColors.border),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              const Icon(Icons.person_outline, color: EbtlColors.teal),
              const SizedBox(width: 10),
              Text(
                'Gender',
                style: GoogleFonts.manrope(
                  fontSize: 13,
                  fontWeight: FontWeight.w800,
                  color: EbtlColors.muted,
                ),
              ),
              const Spacer(),
              Text(
                'Optional',
                style: GoogleFonts.manrope(
                  fontSize: 12,
                  fontWeight: FontWeight.w700,
                  color: EbtlColors.muted,
                ),
              ),
            ],
          ),
          const SizedBox(height: 12),
          Row(
            children: [
              Expanded(
                child: _ProfileGenderOptionPill(
                  label: 'Male',
                  icon: Icons.male,
                  selected: normalizedGender == 'male',
                  onTap: () {
                    onChanged(normalizedGender == 'male' ? null : 'male');
                  },
                ),
              ),
              const SizedBox(width: 10),
              Expanded(
                child: _ProfileGenderOptionPill(
                  label: 'Female',
                  icon: Icons.female,
                  selected: normalizedGender == 'female',
                  onTap: () {
                    onChanged(normalizedGender == 'female' ? null : 'female');
                  },
                ),
              ),
            ],
          ),
        ],
      ),
    );
  }
}

class _ProfileGenderOptionPill extends StatelessWidget {
  final String label;
  final IconData icon;
  final bool selected;
  final VoidCallback onTap;

  const _ProfileGenderOptionPill({
    required this.label,
    required this.icon,
    required this.selected,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    return Semantics(
      button: true,
      selected: selected,
      label: label,
      child: Material(
        color: selected ? EbtlColors.coral : EbtlColors.white,
        borderRadius: BorderRadius.circular(999),
        child: InkWell(
          onTap: onTap,
          borderRadius: BorderRadius.circular(999),
          child: Container(
            height: 46,
            padding: const EdgeInsets.symmetric(horizontal: 12),
            decoration: BoxDecoration(
              borderRadius: BorderRadius.circular(999),
              border: Border.all(
                color: selected ? EbtlColors.coral : EbtlColors.border,
                width: selected ? 1.4 : 1,
              ),
            ),
            child: Row(
              mainAxisAlignment: MainAxisAlignment.center,
              children: [
                Icon(
                  icon,
                  size: 19,
                  color: selected ? Colors.white : EbtlColors.navy,
                ),
                const SizedBox(width: 7),
                Text(
                  label,
                  style: GoogleFonts.manrope(
                    fontSize: 13,
                    fontWeight: FontWeight.w900,
                    color: selected ? Colors.white : EbtlColors.navy,
                  ),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}

class ProfileSubScreenHeader extends StatelessWidget {
  final String title;
  final VoidCallback onBack;

  const ProfileSubScreenHeader({
    super.key,
    required this.title,
    required this.onBack,
  });

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.fromLTRB(22, 12, 22, 18),
      child: Row(
        children: [
          CircleIconButton(icon: Icons.arrow_back, onTap: onBack),
          const SizedBox(width: 16),
          Expanded(
            child: Text(
              title,
              style: GoogleFonts.playfairDisplay(
                fontSize: 36,
                height: 1,
                fontWeight: FontWeight.w800,
                color: EbtlColors.navy,
              ),
            ),
          ),
        ],
      ),
    );
  }
}

class FeaturePlaceholderScreen extends StatelessWidget {
  final String title;
  final String message;

  const FeaturePlaceholderScreen({
    super.key,
    required this.title,
    required this.message,
  });

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: EbtlColors.cream,
      body: SafeArea(
        child: CustomScrollView(
          slivers: [
            SliverToBoxAdapter(
              child: ProfileSubScreenHeader(
                title: title,
                onBack: () => Navigator.of(context).pop(),
              ),
            ),
            SliverToBoxAdapter(
              child: Padding(
                padding: const EdgeInsets.all(22),
                child: DetailCard(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        'Coming soon.',
                        style: GoogleFonts.playfairDisplay(
                          fontSize: 30,
                          fontWeight: FontWeight.w800,
                          color: EbtlColors.navy,
                        ),
                      ),
                      const SizedBox(height: 10),
                      Text(
                        message,
                        style: GoogleFonts.manrope(
                          fontSize: 14,
                          height: 1.4,
                          fontWeight: FontWeight.w600,
                          color: EbtlColors.ink,
                        ),
                      ),
                    ],
                  ),
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }
}

final List<ProfileQuickLink> defaultProfileQuickLinks = const [
  ProfileQuickLink(
    key: 'addresses',
    title: 'Addresses',
    subtitle: 'Manage your delivery addresses',
    endpoint: '/api/customer/addresses',
    enabled: true,
    placeholder: false,
    count: null,
  ),
  ProfileQuickLink(
    key: 'payment_methods',
    title: 'Payment Methods',
    subtitle: 'Saved cards coming soon',
    endpoint: null,
    enabled: false,
    placeholder: true,
    count: null,
  ),
  ProfileQuickLink(
    key: 'favorite_cocktails',
    title: 'Favorite Cocktails',
    subtitle: 'Your saved cocktail picks',
    endpoint: '/api/customer/favorites',
    enabled: true,
    placeholder: false,
    count: null,
  ),
  ProfileQuickLink(
    key: 'favorite_spirits',
    title: 'My Spirits',
    subtitle: 'The bottles you keep at hand',
    endpoint: '/api/customer/spirits',
    enabled: true,
    placeholder: false,
    count: null,
  ),
  ProfileQuickLink(
    key: 'promo_codes',
    title: 'Promo Codes',
    subtitle: 'View available offers',
    endpoint: null,
    enabled: false,
    placeholder: true,
    count: null,
  ),
  ProfileQuickLink(
    key: 'notifications',
    title: 'Notifications',
    subtitle: 'Manage your preferences',
    endpoint: null,
    enabled: false,
    placeholder: true,
    count: null,
  ),
];

IconData profileQuickLinkIcon(String key) {
  switch (key) {
    case 'addresses':
      return Icons.location_on_outlined;
    case 'payment_methods':
      return Icons.credit_card_outlined;
    case 'favorite_cocktails':
      return Icons.favorite_border;
    case 'favorite_spirits':
      return Icons.liquor_outlined;
    case 'promo_codes':
      return Icons.local_offer_outlined;
    case 'notifications':
      return Icons.notifications_none;
    default:
      return Icons.chevron_right;
  }
}

String profileStatusLabel(ProfileOrder order) {
  final clean = order.statusLabel.trim();
  if (clean.isNotEmpty) {
    if (order.status == 'ready' && !clean.toLowerCase().contains('pickup')) {
      return 'Ready for pickup';
    }
    return clean;
  }

  switch (order.status) {
    case 'ready':
      return 'Ready for pickup';
    case 'pending_payment':
      return 'Pending payment';
    case 'confirmed':
      return 'Confirmed';
    case 'preparing':
      return 'Preparing';
    case 'completed':
      return 'Completed';
    case 'cancelled':
      return 'Cancelled';
    case 'refunded':
      return 'Refunded';
    default:
      return 'Order';
  }
}
