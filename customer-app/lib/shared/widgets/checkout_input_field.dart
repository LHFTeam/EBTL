import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';

import '../../core/theme/ebtl_colors.dart';
import '../../core/utils/keyboard.dart';

class CheckoutInputField extends StatelessWidget {
  final TextEditingController controller;
  final String label;
  final String hintText;
  final IconData icon;
  final TextInputType? keyboardType;
  final TextInputAction? textInputAction;
  final int? maxLength;
  final int maxLines;
  final String? errorText;
  final ValueChanged<String> onChanged;

  const CheckoutInputField({
    super.key,
    required this.controller,
    required this.label,
    required this.hintText,
    required this.icon,
    required this.onChanged,
    this.keyboardType,
    this.textInputAction,
    this.maxLength,
    this.maxLines = 1,
    this.errorText,
  });

  @override
  Widget build(BuildContext context) {
    return TextField(
      controller: controller,
      keyboardType: keyboardType,
      textInputAction: textInputAction,
      maxLength: maxLength,
      maxLines: maxLines,
      onChanged: onChanged,
      onTapOutside: dismissKeyboard,
      style: GoogleFonts.manrope(
        fontSize: 14,
        fontWeight: FontWeight.w700,
        color: EbtlColors.navy,
      ),
      decoration: InputDecoration(
        counterText: '',
        labelText: label,
        hintText: hintText,
        errorText: errorText,
        prefixIcon: Icon(icon, color: EbtlColors.teal),
        filled: true,
        fillColor: EbtlColors.cream.withValues(alpha: 0.62),
        labelStyle: GoogleFonts.manrope(
          color: EbtlColors.muted,
          fontWeight: FontWeight.w700,
        ),
        hintStyle: GoogleFonts.manrope(
          color: EbtlColors.muted.withValues(alpha: 0.72),
          fontWeight: FontWeight.w600,
        ),
        enabledBorder: OutlineInputBorder(
          borderRadius: BorderRadius.circular(18),
          borderSide: const BorderSide(color: EbtlColors.border),
        ),
        focusedBorder: OutlineInputBorder(
          borderRadius: BorderRadius.circular(18),
          borderSide: const BorderSide(color: EbtlColors.teal, width: 1.4),
        ),
        errorBorder: OutlineInputBorder(
          borderRadius: BorderRadius.circular(18),
          borderSide: const BorderSide(color: EbtlColors.coral),
        ),
        focusedErrorBorder: OutlineInputBorder(
          borderRadius: BorderRadius.circular(18),
          borderSide: const BorderSide(color: EbtlColors.coral, width: 1.4),
        ),
      ),
    );
  }
}
