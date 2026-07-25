import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';

import '../../core/network/api_exception.dart';
import '../../core/theme/ebtl_colors.dart';
import '../../models/profile_models.dart';
import '../../services/api_service.dart';
import '../../shared/widgets/app_state_widgets.dart';
import '../../shared/widgets/checkout_input_field.dart';
import 'widgets/profile_widgets.dart';

class ProfileEditSheet extends StatefulWidget {
  final CustomerProfile profile;

  const ProfileEditSheet({super.key, required this.profile});

  @override
  State<ProfileEditSheet> createState() => _ProfileEditSheetState();
}

class _ProfileEditSheetState extends State<ProfileEditSheet> {
  static final RegExp egyptMobileRegex = RegExp(r'^0\d{10}$');
  static final RegExp emailRegex = RegExp(r'^[^@\s]+@[^@\s]+\.[^@\s]+$');

  late final TextEditingController nameController;
  late final TextEditingController emailController;
  late final TextEditingController phoneController;
  late String? selectedGender;
  late bool marketingOptIn;

  bool isSaving = false;
  bool showErrors = false;

  @override
  void initState() {
    super.initState();
    nameController = TextEditingController(text: widget.profile.fullName ?? '');
    emailController = TextEditingController(text: widget.profile.email ?? '');
    phoneController = TextEditingController(text: widget.profile.phone ?? '');
    selectedGender = CustomerProfile.normalizeGender(widget.profile.gender);
    marketingOptIn = widget.profile.marketingOptIn;
  }

  @override
  void dispose() {
    nameController.dispose();
    emailController.dispose();
    phoneController.dispose();
    super.dispose();
  }

  bool get isNameValid => nameController.text.trim().isNotEmpty;

  bool get isEmailValid {
    final value = emailController.text.trim();
    return value.isEmpty || emailRegex.hasMatch(value);
  }

  bool get isPhoneValid {
    final value = phoneController.text.trim();
    return value.isEmpty || egyptMobileRegex.hasMatch(value);
  }

  bool get isGenderValid {
    return selectedGender == null ||
        selectedGender == 'male' ||
        selectedGender == 'female';
  }

  bool get canSave {
    return isNameValid &&
        isEmailValid &&
        isPhoneValid &&
        isGenderValid &&
        !isSaving;
  }

  Future<void> save() async {
    setState(() => showErrors = true);

    if (!canSave) return;

    setState(() => isSaving = true);

    try {
      await ApiService.updateCustomerProfile(
        fullName: nameController.text.trim(),
        email: emailController.text.trim(),
        phone: phoneController.text.trim(),
        gender: selectedGender,
        includeGender: true,
        marketingOptIn: marketingOptIn,
      );

      if (!mounted) return;
      Navigator.of(context).pop(true);
    } catch (error) {
      if (!mounted) return;

      setState(() => isSaving = false);

      showAppSnackBar(
        context,
        apiErrorMessage(error),
      );
    }
  }

  @override
  Widget build(BuildContext context) {
    return SafeArea(
      child: Padding(
        padding: EdgeInsets.only(
          left: 14,
          right: 14,
          bottom: MediaQuery.of(context).viewInsets.bottom + 14,
        ),
        child: Container(
          padding: const EdgeInsets.fromLTRB(18, 18, 18, 18),
          decoration: BoxDecoration(
            color: EbtlColors.white,
            borderRadius: BorderRadius.circular(26),
            border: Border.all(color: EbtlColors.border),
          ),
          child: SingleChildScrollView(
            child: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Row(
                  children: [
                    Expanded(
                      child: Text(
                        'Edit Profile',
                        style: GoogleFonts.playfairDisplay(
                          fontSize: 30,
                          fontWeight: FontWeight.w800,
                          color: EbtlColors.navy,
                        ),
                      ),
                    ),
                    IconButton(
                      onPressed: () => Navigator.of(context).pop(false),
                      icon: const Icon(Icons.close, color: EbtlColors.navy),
                    ),
                  ],
                ),
                const SizedBox(height: 14),
                CheckoutInputField(
                  controller: nameController,
                  label: 'Name',
                  hintText: 'Your name',
                  icon: Icons.person_outline,
                  textInputAction: TextInputAction.next,
                  errorText: showErrors && !isNameValid
                      ? 'Name is required.'
                      : null,
                  onChanged: (_) => setState(() {}),
                ),
                const SizedBox(height: 12),
                CheckoutInputField(
                  controller: emailController,
                  label: 'Email',
                  hintText: 'you@example.com',
                  icon: Icons.email_outlined,
                  keyboardType: TextInputType.emailAddress,
                  textInputAction: TextInputAction.next,
                  errorText: showErrors && !isEmailValid
                      ? 'Enter a valid email.'
                      : null,
                  onChanged: (_) => setState(() {}),
                ),
                const SizedBox(height: 12),
                CheckoutInputField(
                  controller: phoneController,
                  label: 'Phone Number',
                  hintText: '01012345678',
                  icon: Icons.phone_outlined,
                  keyboardType: TextInputType.phone,
                  textInputAction: TextInputAction.done,
                  maxLength: 11,
                  errorText: showErrors && !isPhoneValid
                      ? 'Use 11 digits starting with 0.'
                      : null,
                  onChanged: (_) => setState(() {}),
                ),
                const SizedBox(height: 12),
                ProfileGenderSelector(
                  selectedGender: selectedGender,
                  onChanged: (gender) {
                    setState(() => selectedGender = gender);
                  },
                ),
                if (showErrors && !isGenderValid) ...[
                  const SizedBox(height: 8),
                  Text(
                    'Choose Male, Female, or leave gender unselected.',
                    style: GoogleFonts.manrope(
                      fontSize: 12,
                      fontWeight: FontWeight.w700,
                      color: EbtlColors.coral,
                    ),
                  ),
                ],
                const SizedBox(height: 8),
                SwitchListTile.adaptive(
                  contentPadding: EdgeInsets.zero,
                  value: marketingOptIn,
                  activeThumbColor: EbtlColors.coral,
                  activeTrackColor: EbtlColors.blush.withValues(alpha: 0.65),
                  title: Text(
                    'Send me EBTL updates',
                    style: GoogleFonts.manrope(
                      fontWeight: FontWeight.w900,
                      color: EbtlColors.navy,
                    ),
                  ),
                  subtitle: Text(
                    'Promos, new cocktails, and beach cart updates.',
                    style: GoogleFonts.manrope(
                      fontWeight: FontWeight.w600,
                      color: EbtlColors.muted,
                    ),
                  ),
                  onChanged: (value) => setState(() => marketingOptIn = value),
                ),
                const SizedBox(height: 14),
                SizedBox(
                  width: double.infinity,
                  height: 54,
                  child: ElevatedButton(
                    onPressed: canSave ? save : null,
                    style: ElevatedButton.styleFrom(
                      backgroundColor: EbtlColors.coral,
                      disabledBackgroundColor: EbtlColors.sand,
                      foregroundColor: Colors.white,
                      disabledForegroundColor: EbtlColors.muted,
                      elevation: 0,
                      shape: RoundedRectangleBorder(
                        borderRadius: BorderRadius.circular(18),
                      ),
                    ),
                    child: isSaving
                        ? const SizedBox(
                            width: 20,
                            height: 20,
                            child: CircularProgressIndicator(
                              color: Colors.white,
                              strokeWidth: 2,
                            ),
                          )
                        : Text(
                            'Save Profile',
                            style: GoogleFonts.manrope(
                              fontWeight: FontWeight.w900,
                              fontSize: 15,
                            ),
                          ),
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
