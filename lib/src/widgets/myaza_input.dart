import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../config/theme.dart';

// ─── Input ────────────────────────────────────────────────────────────────────

class MyazaInput extends StatefulWidget {
  final String? label;
  final String? hint;
  final String? errorText;
  final String? helperText;
  final TextEditingController? controller;
  final FocusNode? focusNode;
  final TextInputType keyboardType;
  final TextInputAction? textInputAction;
  final List<TextInputFormatter>? inputFormatters;
  final bool obscureText;
  final bool readOnly;
  final bool autofocus;
  final int? maxLength;
  final int maxLines;
  final Widget? prefix;
  final Widget? suffix;
  final ValueChanged<String>? onChanged;
  final ValueChanged<String>? onSubmitted;
  final VoidCallback? onTap;

  const MyazaInput({
    super.key,
    this.label,
    this.hint,
    this.errorText,
    this.helperText,
    this.controller,
    this.focusNode,
    this.keyboardType = TextInputType.text,
    this.textInputAction,
    this.inputFormatters,
    this.obscureText = false,
    this.readOnly = false,
    this.autofocus = false,
    this.maxLength,
    this.maxLines = 1,
    this.prefix,
    this.suffix,
    this.onChanged,
    this.onSubmitted,
    this.onTap,
  });

  @override
  State<MyazaInput> createState() => _MyazaInputState();
}

class _MyazaInputState extends State<MyazaInput> {
  late bool _obscured;

  @override
  void initState() {
    super.initState();
    _obscured = widget.obscureText;
  }

  // ── Border helpers ─────────────────────────────────────────────────────────

  static OutlineInputBorder _border(Color color, {double width = 1.0}) =>
      OutlineInputBorder(
        borderRadius: BorderRadius.circular(MyazaRadius.sm),
        borderSide: BorderSide(color: color, width: width),
      );

  // ── Build ──────────────────────────────────────────────────────────────────

  @override
  Widget build(BuildContext context) {
    final colors = context.myazaColors;
    final text   = context.myazaText;
    final hasError = widget.errorText != null && widget.errorText!.isNotEmpty;

    Widget? suffixIcon;
    if (widget.obscureText) {
      suffixIcon = GestureDetector(
        onTap: () => setState(() => _obscured = !_obscured),
        child: Icon(
          _obscured ? Icons.visibility_off_outlined : Icons.visibility_outlined,
          size: 20,
          color: colors.textMuted,
        ),
      );
    } else if (widget.suffix != null) {
      suffixIcon = widget.suffix;
    }

    final field = TextField(
      controller: widget.controller,
      focusNode: widget.focusNode,
      keyboardType: widget.keyboardType,
      textInputAction: widget.textInputAction,
      inputFormatters: widget.inputFormatters,
      obscureText: _obscured,
      readOnly: widget.readOnly,
      autofocus: widget.autofocus,
      maxLength: widget.maxLength,
      maxLines: widget.maxLines,
      onChanged: widget.onChanged,
      onSubmitted: widget.onSubmitted,
      onTap: widget.onTap,
      style: text.body,
      cursorColor: colors.primary,
      decoration: InputDecoration(
        hintText: widget.hint,
        hintStyle: text.body.copyWith(color: colors.textMuted),
        prefixIcon: widget.prefix != null
            ? Padding(
                padding: const EdgeInsets.symmetric(horizontal: 12),
                child: widget.prefix,
              )
            : null,
        prefixIconConstraints:
            const BoxConstraints(minWidth: 40, minHeight: 0),
        suffixIcon: suffixIcon != null
            ? Padding(
                padding: const EdgeInsets.only(right: 12),
                child: suffixIcon,
              )
            : null,
        suffixIconConstraints:
            const BoxConstraints(minWidth: 40, minHeight: 0),
        // Borders
        enabledBorder: _border(
          hasError ? MyazaColors.error : colors.border,
          width: hasError ? 1.5 : 1.0,
        ),
        focusedBorder: _border(
          hasError ? MyazaColors.error : colors.primary,
          width: 2.0,
        ),
        errorBorder: _border(MyazaColors.error, width: 1.5),
        focusedErrorBorder: _border(MyazaColors.error, width: 2.0),
        disabledBorder: _border(colors.gray300),
        // Sizing — use contentPadding to achieve 48px height for single-line
        contentPadding: const EdgeInsets.symmetric(
          horizontal: MyazaSpacing.md,
          vertical: 13,
        ),
        filled: true,
        fillColor: colors.backgroundSecondary,
        // Counter hidden — maxLength enforced silently
        counterText: '',
        isDense: false,
      ),
    );

    if (widget.label == null && !hasError && widget.helperText == null) {
      return field;
    }

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      mainAxisSize: MainAxisSize.min,
      children: [
        if (widget.label != null) ...[
          Text(widget.label!, style: text.label),
          const SizedBox(height: MyazaSpacing.xs),
        ],
        field,
        if (hasError) ...[
          const SizedBox(height: MyazaSpacing.xs),
          Row(
            children: [
              const Icon(Icons.error_outline,
                  size: 14, color: MyazaColors.error),
              const SizedBox(width: 4),
              Expanded(
                child: Text(
                  widget.errorText!,
                  style: text.bodySmall.copyWith(color: MyazaColors.error),
                ),
              ),
            ],
          ),
        ] else if (widget.helperText != null) ...[
          const SizedBox(height: MyazaSpacing.xs),
          Text(widget.helperText!, style: text.bodySmall),
        ],
      ],
    );
  }
}
