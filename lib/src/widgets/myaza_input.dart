import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../config/theme.dart';
import 'icons/icons.dart';

// ─── Input ────────────────────────────────────────────────────────────────────

class MyazaInput extends StatefulWidget {
  final String? label;

  /// Marks the label with an asterisk in the error colour: a field the flow
  /// will not continue without.
  final bool required;
  final String? hint;
  final String? errorText;
  final String? helperText;
  final TextEditingController? controller;
  final FocusNode? focusNode;
  final TextInputType keyboardType;
  final TextCapitalization textCapitalization;
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

  /// Compact overrides for inline fields (e.g. the 40px search-results filter,
  /// mirroring the RN MyazaInput's height/fontSize props). Null = the standard
  /// 48px field at body size.
  final double? height;
  final double? fontSize;

  /// Off for proper-noun fields (company names, registration numbers): iOS
  /// autocorrect rewrites them right before the person submits, so a search
  /// for the company they typed silently becomes a search for a word the
  /// keyboard preferred. Defaults on, like the platform.
  final bool autocorrect;

  const MyazaInput({
    super.key,
    this.label,
    this.required = false,
    this.hint,
    this.errorText,
    this.helperText,
    this.controller,
    this.focusNode,
    this.keyboardType = TextInputType.text,
    this.textCapitalization = TextCapitalization.none,
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
    this.height,
    this.fontSize,
    this.autocorrect = true,
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
    final fieldStyle = widget.fontSize != null
        ? text.body.copyWith(fontSize: widget.fontSize)
        : text.body;
    // The standard field is 48px = 22px of text + 13px padding either side;
    // a height override keeps the text centred by taking the difference off
    // the vertical padding.
    final verticalPad = widget.height != null
        ? ((widget.height! - (widget.fontSize ?? 16) * 1.375) / 2)
            .clamp(4.0, 13.0)
        : 13.0;

    Widget? suffixIcon;
    if (widget.obscureText) {
      suffixIcon = GestureDetector(
        onTap: () => setState(() => _obscured = !_obscured),
        child: MyazaIcon(
          _obscured ? MyazaIcons.eyeOff : MyazaIcons.eye,
          size: 20,
          color: colors.textMuted,
        ),
      );
    } else if (widget.suffix != null) {
      suffixIcon = widget.suffix;
    }

    final field = TextField(
      // Space kept BELOW the caret when the field is auto-scrolled into view on
      // focus. Flutter's 20px default only guarantees the caret itself clears
      // the keyboard, which leaves the step's action button hidden right under
      // it — so reserve roughly a button's height and the gap above it, and the
      // Continue action scrolls into view along with the field.
      scrollPadding: const EdgeInsets.only(bottom: 140),
      controller: widget.controller,
      focusNode: widget.focusNode,
      keyboardType: widget.keyboardType,
      textCapitalization: widget.textCapitalization,
      textInputAction: widget.textInputAction,
      inputFormatters: widget.inputFormatters,
      obscureText: _obscured,
      autocorrect: widget.autocorrect,
      enableSuggestions: widget.autocorrect,
      readOnly: widget.readOnly,
      autofocus: widget.autofocus,
      maxLength: widget.maxLength,
      maxLines: widget.maxLines,
      onChanged: widget.onChanged,
      onSubmitted: widget.onSubmitted,
      onTap: widget.onTap,
      style: fieldStyle,
      cursorColor: colors.primary,
      decoration: InputDecoration(
        hintText: widget.hint,
        hintStyle: fieldStyle.copyWith(color: colors.textMuted),
        prefixIcon: widget.prefix != null
            ? Padding(
                padding: const EdgeInsets.symmetric(horizontal: 12),
                child: widget.prefix,
              )
            : null,
        prefixIconConstraints:
            const BoxConstraints(minWidth: 40, minHeight: 0),
        // Aligned to the field's right edge, and through an Align so the
        // slot's minimum width reaches the child as LOOSE constraints: fed
        // the 28px directly, a 16px spinner became a 28x16 oval, and centred
        // it floated off the edge (user reports 2026-09-08).
        suffixIcon: suffixIcon != null
            ? Padding(
                // RN's input holds its suffix `md` in from the edge.
                padding: const EdgeInsets.only(right: MyazaSpacing.md),
                child: Align(alignment: Alignment.centerRight, child: suffixIcon),
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
        // (or the caller's height override, e.g. the 40px results filter)
        contentPadding: EdgeInsets.symmetric(
          horizontal: MyazaSpacing.md,
          vertical: verticalPad,
        ),
        filled: true,
        fillColor: colors.backgroundSecondary,
        // Counter hidden — maxLength enforced silently
        counterText: '',
        // Dense only under a height override, so the tighter padding is
        // honoured; the standard field keeps Material's roomier metrics.
        isDense: widget.height != null,
      ),
    );

    // Always return the same tree shape (a Column wrapping the field) regardless
    // of label/error/helper state. Returning a bare `field` in some states and a
    // `Column`-wrapped one in others reparents the TextField when the error row
    // appears/disappears, destroying its element and dropping the keyboard — most
    // visibly on the first invalid character and the last character that makes the
    // value valid. `stretch` keeps the field full-width as it was when bare.
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      mainAxisSize: MainAxisSize.min,
      children: [
        if (widget.label != null) ...[
          Text.rich(TextSpan(
            text: widget.label,
            style: text.label,
            children: [
              if (widget.required)
                TextSpan(
                  text: ' *',
                  style: text.label.copyWith(color: MyazaColors.error),
                ),
            ],
          )),
          const SizedBox(height: MyazaSpacing.xs),
        ],
        field,
        if (hasError) ...[
          const SizedBox(height: MyazaSpacing.xs),
          Row(
            children: [
              const MyazaIcon(MyazaIcons.circleAlert,
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
