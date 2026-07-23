import 'package:flutter/material.dart';

import '../../core/theme/ebtl_colors.dart';
import '../../models/profile_models.dart';
import '../../services/api_service.dart';
import '../../shared/widgets/app_state_widgets.dart';
import 'customer_addresses_screen.dart';
import 'customer_orders_screen.dart';
import 'favorite_cocktails_screen.dart';
import 'profile_edit_sheet.dart';
import 'widgets/profile_widgets.dart';

class ProfileScreen extends StatefulWidget {
  final String? selectedLocationId;
  final VoidCallback onLoggedOut;
  final int unreadNotificationCount;
  final VoidCallback onOpenNotifications;

  const ProfileScreen({
    super.key,
    required this.selectedLocationId,
    required this.onLoggedOut,
    required this.unreadNotificationCount,
    required this.onOpenNotifications,
  });

  @override
  State<ProfileScreen> createState() => _ProfileScreenState();
}

class _ProfileScreenState extends State<ProfileScreen> {
  late Future<CustomerProfileResponse> profileFuture;
  bool isLoggingOut = false;

  @override
  void initState() {
    super.initState();
    profileFuture = ApiService.fetchCustomerProfile();
  }

  void reloadProfile() {
    setState(() {
      profileFuture = ApiService.fetchCustomerProfile();
    });
  }

  Future<void> refreshProfile() async {
    final future = ApiService.fetchCustomerProfile();
    setState(() => profileFuture = future);
    await future;
  }

  void showComingSoon(String title) {
    showAppSnackBar(context, '$title coming soon.');
  }

  Future<void> openEditProfile(CustomerProfile profile) async {
    final updated = await showModalBottomSheet<bool>(
      context: context,
      isScrollControlled: true,
      backgroundColor: Colors.transparent,
      builder: (context) => ProfileEditSheet(profile: profile),
    );

    if (updated == true && mounted) {
      reloadProfile();
    }
  }

  void openQuickLink(ProfileQuickLink link) {
    switch (link.key) {
      case 'favorite_cocktails':
        Navigator.of(context).push(
          MaterialPageRoute(
            builder: (_) =>
                FavoriteCocktailsScreen(locationId: widget.selectedLocationId),
          ),
        );
        return;
      case 'addresses':
        Navigator.of(context).push(
          MaterialPageRoute(
            builder: (_) => const CustomerAddressesScreen(),
          ),
        );
        return;
      case 'notifications':
        widget.onOpenNotifications();
        return;
      case 'payment_methods':
      case 'promo_codes':
      default:
        showComingSoon(link.title);
        return;
    }
  }

  Future<void> logout() async {
    if (isLoggingOut) return;

    setState(() => isLoggingOut = true);

    try {
      await ApiService.clearCustomerSession();
      if (!mounted) return;
      widget.onLoggedOut();
    } catch (error) {
      if (!mounted) return;
      setState(() => isLoggingOut = false);
      showAppSnackBar(context, 'Could not log out: $error');
    }
  }

  @override
  Widget build(BuildContext context) {
    return SafeArea(
      child: FutureBuilder<CustomerProfileResponse>(
        future: profileFuture,
        builder: (context, snapshot) {
          if (snapshot.connectionState == ConnectionState.waiting) {
            return const ProfileLoadingState();
          }

          if (snapshot.hasError) {
            return CustomScrollView(
              slivers: [
                const SliverToBoxAdapter(child: ProfileHeaderSkeleton()),
                SliverToBoxAdapter(
                  child: InlineErrorCard(
                    message: snapshot.error.toString(),
                    onRetry: reloadProfile,
                  ),
                ),
              ],
            );
          }

          final profile = snapshot.data;
          if (profile == null) {
            return CustomScrollView(
              slivers: [
                const SliverToBoxAdapter(child: ProfileHeaderSkeleton()),
                SliverToBoxAdapter(
                  child: InlineErrorCard(
                    message: 'The backend returned no profile data.',
                    onRetry: reloadProfile,
                  ),
                ),
              ],
            );
          }

          return RefreshIndicator(
            color: EbtlColors.coral,
            onRefresh: refreshProfile,
            child: CustomScrollView(
              physics: const AlwaysScrollableScrollPhysics(),
              slivers: [
                SliverToBoxAdapter(
                  child: ProfileHeader(
                    onNotifications: widget.onOpenNotifications,
                    onSettings: () => openEditProfile(profile.customer),
                    unreadCount: widget.unreadNotificationCount,
                  ),
                ),
                SliverToBoxAdapter(
                  child: ProfileIdentityCard(
                    profile: profile.customer,
                    onTap: () => openEditProfile(profile.customer),
                  ),
                ),
                SliverToBoxAdapter(
                  child: ProfileOrdersSection(
                    recentOrders: profile.recentOrders,
                    onViewAll:
                        profile.recentOrders.hasMore ||
                            profile.recentOrders.items.isNotEmpty
                        ? () {
                            Navigator.of(context).push(
                              MaterialPageRoute(
                                builder: (_) => const CustomerOrdersScreen(),
                              ),
                            );
                          }
                        : null,
                  ),
                ),
                SliverToBoxAdapter(
                  child: ProfileQuickLinksSection(
                    links: profile.quickLinks,
                    onTapLink: openQuickLink,
                  ),
                ),
                SliverToBoxAdapter(
                  child: ProfileBrandMessageCard(
                    brandMessage: profile.brandMessage,
                  ),
                ),
                SliverToBoxAdapter(
                  child: ProfileLogoutButton(
                    isLoading: isLoggingOut,
                    onTap: logout,
                  ),
                ),
                const SliverToBoxAdapter(child: SizedBox(height: 22)),
              ],
            ),
          );
        },
      ),
    );
  }
}
