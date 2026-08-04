import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';

import '../../core/network/api_exception.dart';
import '../../core/theme/ebtl_colors.dart';
import '../../models/spirit_models.dart';
import '../../services/api_service.dart';
import '../../shared/widgets/app_state_widgets.dart';
import 'widgets/profile_widgets.dart';
import 'widgets/spirit_widgets.dart';

/// "My Spirits" — the customer's own spirit list, plus the most-ordered list
/// the backend keeps for them.
///
/// Every mutation answers with the whole spirits payload, so there is no local
/// patching: the response replaces what is on screen. Pops `true` when anything
/// changed, which the profile uses to reload its own copy.
class FavoriteSpiritsScreen extends StatefulWidget {
  const FavoriteSpiritsScreen({super.key});

  @override
  State<FavoriteSpiritsScreen> createState() => _FavoriteSpiritsScreenState();
}

class _FavoriteSpiritsScreenState extends State<FavoriteSpiritsScreen> {
  late Future<ProfileSpirits> spiritsFuture;
  final Set<String> mutatingIds = <String>{};
  ProfileSpirits? spirits;
  bool changed = false;

  @override
  void initState() {
    super.initState();
    spiritsFuture = loadSpirits();
  }

  Future<ProfileSpirits> loadSpirits() async {
    final response = await ApiService.fetchCustomerSpirits();
    spirits = response;
    return response;
  }

  void reload() {
    setState(() {
      spiritsFuture = loadSpirits();
    });
  }

  Future<void> mutate(
    ProfileSpirit spirit,
    Future<ProfileSpirits> Function() request,
    String failureMessage,
  ) async {
    if (mutatingIds.contains(spirit.id)) return;

    setState(() => mutatingIds.add(spirit.id));

    try {
      final updated = await request();

      if (!mounted) return;

      setState(() {
        mutatingIds.remove(spirit.id);
        spirits = updated;
        changed = true;
      });
    } catch (error) {
      if (!mounted) return;

      setState(() => mutatingIds.remove(spirit.id));
      showAppSnackBar(context, failureMessage);
    }
  }

  Future<void> addSpirit(ProfileSpirit spirit) {
    return mutate(
      spirit,
      () => ApiService.addFavoriteSpirit(liquorTypeId: spirit.id),
      'Could not save ${spirit.name}.',
    );
  }

  Future<void> removeSpirit(ProfileSpirit spirit) {
    return mutate(
      spirit,
      () => ApiService.removeFavoriteSpirit(liquorTypeId: spirit.id),
      'Could not remove ${spirit.name}.',
    );
  }

  @override
  Widget build(BuildContext context) {
    return PopScope(
      canPop: false,
      onPopInvokedWithResult: (didPop, _) {
        if (!didPop) Navigator.of(context).pop(changed);
      },
      child: Scaffold(
        backgroundColor: EbtlColors.cream,
        body: SafeArea(
          child: FutureBuilder<ProfileSpirits>(
            future: spiritsFuture,
            builder: (context, snapshot) {
              final data = spirits ?? snapshot.data;

              return CustomScrollView(
                slivers: [
                  SliverToBoxAdapter(
                    child: ProfileSubScreenHeader(
                      title: 'My Spirits',
                      onBack: () => Navigator.of(context).pop(changed),
                    ),
                  ),
                  if (snapshot.connectionState == ConnectionState.waiting &&
                      data == null)
                    const EbtlLoadingSliver(label: 'Loading your spirits...')
                  else if (data == null)
                    SliverToBoxAdapter(
                      child: InlineErrorCard(
                        message: snapshot.hasError
                            ? apiErrorMessage(snapshot.error!)
                            : 'The backend returned no spirits.',
                        onRetry: reload,
                      ),
                    )
                  else
                    SliverPadding(
                      padding: const EdgeInsets.fromLTRB(22, 0, 22, 28),
                      sliver: SliverList(
                        delegate: SliverChildListDelegate([
                          _SpiritsCard(
                            title: data.favoriteSpirits.title,
                            subtitle: data.favoriteSpirits.subtitle,
                            emptyMessage:
                                'Nothing saved yet. Pick your bottles below.',
                            children: data.favoriteSpirits.items
                                .map(
                                  (spirit) => SpiritPill(
                                    spirit: spirit,
                                    actionIcon: Icons.close,
                                    isBusy: mutatingIds.contains(spirit.id),
                                    onAction: () => removeSpirit(spirit),
                                  ),
                                )
                                .toList(),
                          ),
                          if (data.topSpirits.items.isNotEmpty)
                            _SpiritsCard(
                              title: data.topSpirits.title,
                              subtitle: data.topSpirits.subtitle,
                              emptyMessage: '',
                              children: data.topSpirits.items
                                  .map(
                                    (spirit) => SpiritPill(
                                      spirit: spirit,
                                      trailingLabel: spirit.orderCountLabel,
                                      highlighted: true,
                                    ),
                                  )
                                  .toList(),
                            ),
                          _SpiritsCard(
                            title: 'Add a Spirit',
                            subtitle: 'Tap a bottle to save it to your list',
                            emptyMessage:
                                'You have saved every spirit we pour with.',
                            children: data.addableSpirits
                                .map(
                                  (spirit) => SpiritPill(
                                    spirit: spirit,
                                    actionIcon: Icons.add,
                                    isBusy: mutatingIds.contains(spirit.id),
                                    onAction: () => addSpirit(spirit),
                                  ),
                                )
                                .toList(),
                          ),
                        ]),
                      ),
                    ),
                ],
              );
            },
          ),
        ),
      ),
    );
  }
}

class _SpiritsCard extends StatelessWidget {
  final String title;
  final String subtitle;
  final String emptyMessage;
  final List<Widget> children;

  const _SpiritsCard({
    required this.title,
    required this.subtitle,
    required this.emptyMessage,
    required this.children,
  });

  @override
  Widget build(BuildContext context) {
    return Container(
      width: double.infinity,
      margin: const EdgeInsets.only(bottom: 16),
      padding: const EdgeInsets.all(16),
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
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          SpiritsGroupLabel(label: title, hint: subtitle),
          const SizedBox(height: 12),
          if (children.isEmpty)
            Text(
              emptyMessage,
              style: GoogleFonts.manrope(
                fontSize: 13,
                height: 1.35,
                fontWeight: FontWeight.w600,
                color: EbtlColors.muted,
              ),
            )
          else
            Wrap(spacing: 8, runSpacing: 8, children: children),
        ],
      ),
    );
  }
}
