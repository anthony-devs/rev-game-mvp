import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../core/app_colors.dart';
import '../core/app_text.dart';
import '../core/app_tokens.dart';

/// Labelled text input for forms (sign in, limits, support).
///
/// ```dart
/// AppTextField(label: 'Email', hint: 'you@example.com', keyboardType: TextInputType.emailAddress, onChanged: (v) => email = v)
/// AppTextField(label: 'Password', obscure: true, errorText: error)
/// ```
class AppTextField extends StatelessWidget {
  const AppTextField({
    super.key,
    required this.label,
    this.hint,
    this.controller,
    this.onChanged,
    this.errorText,
    this.obscure = false,
    this.keyboardType,
    this.inputFormatters,
    this.suffix,
    this.enabled = true,
    this.maxLines = 1,
    this.textInputAction,
    this.onSubmitted,
    this.autofillHints,
    this.autofocus = false,
  });

  final String label;
  final String? hint;
  final TextEditingController? controller;
  final ValueChanged<String>? onChanged;
  final String? errorText;
  final bool obscure;
  final TextInputType? keyboardType;
  final List<TextInputFormatter>? inputFormatters;
  final Widget? suffix;
  final bool enabled;
  final int maxLines;
  final TextInputAction? textInputAction;
  final ValueChanged<String>? onSubmitted;
  final Iterable<String>? autofillHints;
  final bool autofocus;

  @override
  Widget build(BuildContext context) {
    final hasError = errorText != null;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(label, style: AppText.body(13, weight: FontWeight.w600, color: AppColors.textMuted)),
        const SizedBox(height: 8),
        Container(
          constraints: const BoxConstraints(minHeight: 52),
          padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 4),
          decoration: BoxDecoration(
            color: AppColors.surfaceAlt,
            borderRadius: BorderRadius.circular(AppRadius.md),
            border: Border.all(color: hasError ? AppColors.lossStrong : AppColors.line),
          ),
          child: Row(
            children: [
              Expanded(
                child: TextField(
                  controller: controller,
                  onChanged: onChanged,
                  enabled: enabled,
                  obscureText: obscure,
                  maxLines: maxLines,
                  keyboardType: keyboardType,
                  textInputAction: textInputAction,
                  onSubmitted: onSubmitted,
                  autofillHints: autofillHints,
                  autofocus: autofocus,
                  inputFormatters: inputFormatters,
                  cursorColor: AppColors.gold,
                  style: AppText.body(15, color: AppColors.text),
                  decoration: InputDecoration(
                    border: InputBorder.none,
                    hintText: hint,
                    hintStyle: AppText.body(15, color: AppColors.textFaint),
                  ),
                ),
              ),
              if (suffix != null) suffix!,
            ],
          ),
        ),
        if (hasError) ...[
          const SizedBox(height: 6),
          Text(errorText!, style: AppText.body(12, color: AppColors.loss)),
        ],
      ],
    );
  }
}
