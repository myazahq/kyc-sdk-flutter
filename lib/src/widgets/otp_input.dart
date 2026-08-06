import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../config/contact_verification.dart';
import '../config/theme.dart';
import 'myaza_input.dart';

// ─── OTP input ────────────────────────────────────────────────────────────────
//
// Enters an N-digit OTP. Two styles (org-config-driven, matching the web SDK):
// `segmented` (N boxes, default) or `text` (a single spaced numeric field).
// Fires `onCompleted` when the last digit lands (auto-submit).

class OtpInput extends StatefulWidget {
  final int length;
  final OtpInputStyle style;
  final ValueChanged<String>? onChanged;
  final ValueChanged<String> onCompleted;
  final bool enabled;

  const OtpInput({
    super.key,
    required this.length,
    required this.style,
    required this.onCompleted,
    this.onChanged,
    this.enabled = true,
  });

  @override
  State<OtpInput> createState() => _OtpInputState();
}

class _OtpInputState extends State<OtpInput> {
  final _controller = TextEditingController();
  final _focus = FocusNode();

  @override
  void dispose() {
    _controller.dispose();
    _focus.dispose();
    super.dispose();
  }

  void _onChanged(String raw) {
    final digits = raw.replaceAll(RegExp(r'\D'), '');
    final clipped =
        digits.length > widget.length ? digits.substring(0, widget.length) : digits;
    if (clipped != _controller.text) {
      _controller.value = TextEditingValue(
        text: clipped,
        selection: TextSelection.collapsed(offset: clipped.length),
      );
    }
    setState(() {});
    widget.onChanged?.call(clipped);
    if (clipped.length == widget.length) widget.onCompleted(clipped);
  }

  @override
  Widget build(BuildContext context) {
    if (widget.style == OtpInputStyle.text) {
      return MyazaInput(
        controller: _controller,
        hint: '•' * widget.length,
        keyboardType: TextInputType.number,
        maxLength: widget.length,
        autofocus: true,
        onChanged: _onChanged,
      );
    }
    return _segmented(context);
  }

  Widget _segmented(BuildContext context) {
    final colors = context.myazaColors;
    final text = context.myazaText;

    return Stack(
      children: [
        Row(
          mainAxisAlignment: MainAxisAlignment.spaceBetween,
          children: [
            for (var i = 0; i < widget.length; i++)
              Expanded(
                child: Padding(
                  padding: EdgeInsets.only(
                    right: i == widget.length - 1 ? 0 : MyazaSpacing.xs,
                  ),
                  child: AspectRatio(
                    aspectRatio: 0.82,
                    child: Container(
                      alignment: Alignment.center,
                      decoration: BoxDecoration(
                        color: colors.background,
                        border: Border.all(
                          color: i < _controller.text.length
                              ? colors.primary
                              : colors.border,
                          width: i < _controller.text.length ? 1.5 : 1.0,
                        ),
                        borderRadius: BorderRadius.circular(MyazaRadius.md),
                      ),
                      child: Text(
                        i < _controller.text.length ? _controller.text[i] : '',
                        style: text.heading2,
                      ),
                    ),
                  ),
                ),
              ),
          ],
        ),
        // Transparent field over the boxes captures taps + keyboard input.
        Positioned.fill(
          child: Opacity(
            opacity: 0,
            child: TextField(
              controller: _controller,
              focusNode: _focus,
              enabled: widget.enabled,
              autofocus: true,
              keyboardType: TextInputType.number,
              inputFormatters: [FilteringTextInputFormatter.digitsOnly],
              showCursor: false,
              onChanged: _onChanged,
              decoration: const InputDecoration(
                counterText: '',
                border: InputBorder.none,
              ),
            ),
          ),
        ),
      ],
    );
  }
}
