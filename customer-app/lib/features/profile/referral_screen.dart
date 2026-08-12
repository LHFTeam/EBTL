import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:google_fonts/google_fonts.dart';

import '../../core/network/api_exception.dart';
import '../../core/theme/ebtl_colors.dart';
import '../../core/utils/keyboard.dart';
import '../../models/referral_models.dart';
import '../../services/api_service.dart';
import '../../shared/widgets/app_state_widgets.dart';
import '../../shared/widgets/detail_card.dart';
import 'widgets/profile_widgets.dart';

class ReferralScreen extends StatefulWidget {
  const ReferralScreen({super.key});

  @override
  State<ReferralScreen> createState() => _ReferralScreenState();
}

class _ReferralScreenState extends State<ReferralScreen> {
  late Future<ReferralHub> hubFuture;
  final TextEditingController codeController = TextEditingController();

  ReferralHub? hub;
  bool isApplying = false;

  @override
  void initState() {
    super.initState();
    hubFuture = loadHub();
  }

  @override
  void dispose() {
    codeController.dispose();
    super.dispose();
  }

  Future<ReferralHub> loadHub() async {
    final result = await ApiService.fetchReferralHub();
    hub = result;
    return result;
  }

  void reload() {
    setState(() {
      hubFuture = loadHub();
    });
  }

  Future<void> copyToClipboard(String text, String confirmation) async {
    await Clipboard.setData(ClipboardData(text: text));
    if (!mounted) return;
    showAppSnackBar(context, confirmation);
  }

  Future<void> applyCode() async {
    if (isApplying) return;

    final code = codeController.text.trim();
    if (code.isEmpty) {
      showAppSnackBar(context, 'Enter a referral code.');
      return;
    }

    setState(() => isApplying = true);

    try {
      final updated = await ApiService.applyReferralCode(code);

      if (!mounted) return;

      setState(() {
        hub = updated;
        isApplying = false;
        codeController.clear();
      });

      showAppSnackBar(context, 'Referral code applied! Your discount is ready at checkout.');
    } catch (error) {
      if (!mounted) return;

      setState(() => isApplying = false);

      showAppSnackBar(
        context,
        error is ApiException ? error.message : 'Could not apply this referral code.',
      );
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: EbtlColors.cream,
      body: SafeArea(
        child: FutureBuilder<ReferralHub>(
          future: hubFuture,
          builder: (context, snapshot) {
            final data = hub ?? snapshot.data;

            if (snapshot.connectionState == ConnectionState.waiting && data == null) {
              return const ProfileLoadingState();
            }

            if (data == null) {
              return ListView(
                padding: EdgeInsets.zero,
                children: [
                  ProfileSubScreenHeader(
                    title: 'Refer & Earn',
                    onBack: () => Navigator.of(context).pop(),
                  ),
                  InlineErrorCard(
                    message: 'Could not load your referral rewards.',
                    onRetry: reload,
                  ),
                ],
              );
            }

            return ListView(
              padding: EdgeInsets.zero,
              children: [
                ProfileSubScreenHeader(
                  title: 'Refer & Earn',
                  onBack: () => Navigator.of(context).pop(),
                ),
                Padding(
                  padding: const EdgeInsets.fromLTRB(22, 0, 22, 32),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.stretch,
                    children: _buildSections(data),
                  ),
                ),
              ],
            );
          },
        ),
      ),
    );
  }

  List<Widget> _buildSections(ReferralHub data) {
    final sections = <Widget>[
      _creditCard(data),
      const SizedBox(height: 16),
    ];

    if (data.code != null) {
      sections
        ..add(_codeCard(data))
        ..add(const SizedBox(height: 16))
        ..add(_statsCard(data))
        ..add(const SizedBox(height: 16));
    }

    sections
      ..add(_howItWorksCard(data))
      ..add(const SizedBox(height: 16))
      ..add(_applyCard());

    if (data.terms != null) {
      sections
        ..add(const SizedBox(height: 16))
        ..add(
          Text(
            data.terms!,
            style: GoogleFonts.manrope(
              fontSize: 12,
              height: 1.5,
              color: EbtlColors.muted,
            ),
          ),
        );
    }

    return sections;
  }

  Widget _creditCard(ReferralHub data) {
    return DetailCard(
      backgroundColor: EbtlColors.teal,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            'Store credit balance',
            style: GoogleFonts.manrope(
              fontSize: 13,
              fontWeight: FontWeight.w700,
              color: EbtlColors.white.withValues(alpha: 0.85),
            ),
          ),
          const SizedBox(height: 6),
          Text(
            data.creditBalanceLabel,
            style: GoogleFonts.playfairDisplay(
              fontSize: 34,
              fontWeight: FontWeight.w900,
              color: EbtlColors.white,
            ),
          ),
          const SizedBox(height: 6),
          Text(
            data.hasCredit
                ? 'Applied automatically at your next checkout.'
                : 'Invite friends to start earning credit.',
            style: GoogleFonts.manrope(
              fontSize: 13,
              color: EbtlColors.white.withValues(alpha: 0.85),
            ),
          ),
        ],
      ),
    );
  }

  Widget _codeCard(ReferralHub data) {
    final code = data.code!;
    return DetailCard(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            'Your referral code',
            style: GoogleFonts.manrope(
              fontSize: 13,
              fontWeight: FontWeight.w700,
              color: EbtlColors.muted,
            ),
          ),
          const SizedBox(height: 10),
          Container(
            width: double.infinity,
            padding: const EdgeInsets.symmetric(vertical: 14),
            decoration: BoxDecoration(
              color: EbtlColors.cream,
              borderRadius: BorderRadius.circular(14),
              border: Border.all(color: EbtlColors.border),
            ),
            child: Text(
              code,
              textAlign: TextAlign.center,
              style: GoogleFonts.playfairDisplay(
                fontSize: 26,
                fontWeight: FontWeight.w900,
                letterSpacing: 2,
                color: EbtlColors.navy,
              ),
            ),
          ),
          const SizedBox(height: 14),
          Row(
            children: [
              Expanded(
                child: OutlinedButton.icon(
                  onPressed: () => copyToClipboard(code, 'Code copied to clipboard.'),
                  icon: const Icon(Icons.copy, size: 18),
                  label: const Text('Copy code'),
                  style: OutlinedButton.styleFrom(
                    foregroundColor: EbtlColors.navy,
                    side: const BorderSide(color: EbtlColors.border),
                    padding: const EdgeInsets.symmetric(vertical: 14),
                    shape: RoundedRectangleBorder(
                      borderRadius: BorderRadius.circular(14),
                    ),
                  ),
                ),
              ),
              const SizedBox(width: 12),
              Expanded(
                child: ElevatedButton.icon(
                  onPressed: data.shareMessage == null
                      ? null
                      : () => copyToClipboard(
                            data.shareMessage!,
                            'Invite message copied — paste it to a friend!',
                          ),
                  icon: const Icon(Icons.ios_share, size: 18),
                  label: const Text('Share'),
                  style: ElevatedButton.styleFrom(
                    backgroundColor: EbtlColors.coral,
                    foregroundColor: EbtlColors.white,
                    padding: const EdgeInsets.symmetric(vertical: 14),
                    elevation: 0,
                    shape: RoundedRectangleBorder(
                      borderRadius: BorderRadius.circular(14),
                    ),
                  ),
                ),
              ),
            ],
          ),
        ],
      ),
    );
  }

  Widget _statsCard(ReferralHub data) {
    return DetailCard(
      child: Row(
        children: [
          _statItem(data.stats.invited.toString(), 'Invited'),
          _statDivider(),
          _statItem(data.stats.pending.toString(), 'Pending'),
          _statDivider(),
          _statItem(data.stats.rewarded.toString(), 'Rewarded'),
        ],
      ),
    );
  }

  Widget _statItem(String value, String label) {
    return Expanded(
      child: Column(
        children: [
          Text(
            value,
            style: GoogleFonts.playfairDisplay(
              fontSize: 24,
              fontWeight: FontWeight.w900,
              color: EbtlColors.navy,
            ),
          ),
          const SizedBox(height: 4),
          Text(
            label,
            style: GoogleFonts.manrope(
              fontSize: 12,
              fontWeight: FontWeight.w600,
              color: EbtlColors.muted,
            ),
          ),
        ],
      ),
    );
  }

  Widget _statDivider() {
    return Container(
      width: 1,
      height: 34,
      color: EbtlColors.border,
    );
  }

  Widget _howItWorksCard(ReferralHub data) {
    final steps = data.howItWorks;
    return DetailCard(
      backgroundColor: EbtlColors.seafoam.withValues(alpha: 0.4),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            'How it works',
            style: GoogleFonts.playfairDisplay(
              fontSize: 20,
              fontWeight: FontWeight.w800,
              color: EbtlColors.navy,
            ),
          ),
          const SizedBox(height: 12),
          for (var i = 0; i < steps.length; i++) ...[
            if (i > 0) const SizedBox(height: 10),
            Row(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Container(
                  width: 24,
                  height: 24,
                  alignment: Alignment.center,
                  decoration: const BoxDecoration(
                    color: EbtlColors.teal,
                    shape: BoxShape.circle,
                  ),
                  child: Text(
                    '${i + 1}',
                    style: GoogleFonts.manrope(
                      fontSize: 12,
                      fontWeight: FontWeight.w800,
                      color: EbtlColors.white,
                    ),
                  ),
                ),
                const SizedBox(width: 12),
                Expanded(
                  child: Padding(
                    padding: const EdgeInsets.only(top: 2),
                    child: Text(
                      steps[i],
                      style: GoogleFonts.manrope(
                        fontSize: 14,
                        height: 1.4,
                        color: EbtlColors.ink,
                      ),
                    ),
                  ),
                ),
              ],
            ),
          ],
        ],
      ),
    );
  }

  Widget _applyCard() {
    return DetailCard(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            'Have a friend\'s code?',
            style: GoogleFonts.playfairDisplay(
              fontSize: 20,
              fontWeight: FontWeight.w800,
              color: EbtlColors.navy,
            ),
          ),
          const SizedBox(height: 4),
          Text(
            'Enter it before your first order to unlock your welcome discount.',
            style: GoogleFonts.manrope(
              fontSize: 13,
              height: 1.4,
              color: EbtlColors.muted,
            ),
          ),
          const SizedBox(height: 12),
          TextField(
            controller: codeController,
            textCapitalization: TextCapitalization.characters,
            onTapOutside: dismissKeyboard,
            decoration: InputDecoration(
              hintText: 'EBTL-XXXXX',
              filled: true,
              fillColor: EbtlColors.cream,
              contentPadding: const EdgeInsets.symmetric(horizontal: 16, vertical: 14),
              border: OutlineInputBorder(
                borderRadius: BorderRadius.circular(14),
                borderSide: const BorderSide(color: EbtlColors.border),
              ),
              enabledBorder: OutlineInputBorder(
                borderRadius: BorderRadius.circular(14),
                borderSide: const BorderSide(color: EbtlColors.border),
              ),
              focusedBorder: OutlineInputBorder(
                borderRadius: BorderRadius.circular(14),
                borderSide: const BorderSide(color: EbtlColors.teal),
              ),
            ),
          ),
          const SizedBox(height: 12),
          SizedBox(
            width: double.infinity,
            child: ElevatedButton(
              onPressed: isApplying ? null : applyCode,
              style: ElevatedButton.styleFrom(
                backgroundColor: EbtlColors.navy,
                foregroundColor: EbtlColors.white,
                padding: const EdgeInsets.symmetric(vertical: 15),
                elevation: 0,
                shape: RoundedRectangleBorder(
                  borderRadius: BorderRadius.circular(14),
                ),
              ),
              child: isApplying
                  ? const SizedBox(
                      width: 20,
                      height: 20,
                      child: CircularProgressIndicator(
                        strokeWidth: 2,
                        color: EbtlColors.white,
                      ),
                    )
                  : const Text('Apply code'),
            ),
          ),
        ],
      ),
    );
  }
}
