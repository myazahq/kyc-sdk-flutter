import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:phone_numbers_parser/phone_numbers_parser.dart';

import '../config/dial_codes.g.dart';
import '../config/theme.dart';
import 'country_flag.dart';
import 'dial_code_picker.dart';
import 'myaza_input.dart';

// ─── Phone number input ───────────────────────────────────────────────────────
//
// Dial-code country picker + national number → E.164. A pragmatic port of the
// web SDK's libphonenumber-backed input: the picker uses the generated dial-code
// table; validity is a length check (6–15 national digits) since the server
// re-validates by actually delivering the OTP. Emits `(e164, isValid)`.

typedef PhoneChanged = void Function(String e164, bool isValid);

class PhoneNumberInput extends StatefulWidget {
  /// Initial dial-code country (ISO-2). Falls back to NG if unknown.
  final String defaultCountry;
  final PhoneChanged onChanged;

  /// The current E.164 value, when the OWNER holds one (e.g. the register's
  /// phone number prefilled into the business form). The widget displays it —
  /// a prefill the applicant cannot SEE is a value they cannot correct — and
  /// re-seeds itself when it changes under it (a register prefill landing, or
  /// a company change clearing it). The widget's own keystrokes never loop
  /// back through this.
  final String? value;

  /// The contact-verification step autofocuses (the phone IS the screen);
  /// a phone sitting mid-form must not steal focus from the fields above it.
  final bool autofocus;

  const PhoneNumberInput({
    super.key,
    required this.defaultCountry,
    required this.onChanged,
    this.value,
    this.autofocus = true,
  });

  @override
  State<PhoneNumberInput> createState() => _PhoneNumberInputState();
}

class _PhoneNumberInputState extends State<PhoneNumberInput> {
  late String _iso;
  String _national = '';
  String? _lastEmitted;
  final _controller = TextEditingController();

  @override
  void initState() {
    super.initState();
    final up = widget.defaultCountry.toUpperCase();
    _iso = kDialCodes.containsKey(up) ? up : 'NG';
    if ((widget.value ?? '').isNotEmpty) _seedFrom(widget.value!);
  }

  @override
  void didUpdateWidget(PhoneNumberInput oldWidget) {
    super.didUpdateWidget(oldWidget);
    // Only an EXTERNAL change re-seeds: our own emit comes straight back as
    // the new `value`, and re-seeding on that would fight the formatter
    // mid-keystroke.
    final incoming = widget.value ?? '';
    if (incoming != (oldWidget.value ?? '') && incoming != _lastEmitted) {
      _seedFrom(incoming);
    }
  }

  /// Display a value handed down from above: split an E.164 into dial code +
  /// national digits (preferring the current country when its code matches,
  /// since +1 alone cannot say US or CA), or show bare digits as national.
  void _seedFrom(String raw) {
    final trimmed = raw.trim();
    var digits = trimmed.replaceAll(RegExp(r'\D'), '');
    if (trimmed.startsWith('+') && digits.isNotEmpty) {
      String? matchedIso;
      if (digits.startsWith(_dial)) {
        matchedIso = _iso;
      } else {
        var bestLen = 0;
        kDialCodes.forEach((iso, dial) {
          if (digits.startsWith(dial) && dial.length > bestLen) {
            matchedIso = iso;
            bestLen = dial.length;
          }
        });
      }
      if (matchedIso != null) {
        _iso = matchedIso!;
        digits = digits.substring(_dial.length);
      }
    }
    final formatted = digits.isEmpty ? '' : _format(digits);
    _controller.value = TextEditingValue(
      text: formatted,
      selection: TextSelection.collapsed(offset: formatted.length),
    );
    _national = formatted;
    if (mounted) setState(() {});
  }

  String get _dial => kDialCodes[_iso] ?? '234';

  /// Formats the typed national digits for the selected country and reports
  /// real validity, mirroring the web SDK's libphonenumber `AsYouType`.
  ///
  /// Validity now comes from the country's actual numbering plan rather than a
  /// 6–15 digit length guess, so a wrong-length NG number is rejected while a
  /// legitimately short number elsewhere is not.
  void _emit() {
    final digits = _national.replaceAll(RegExp(r'\D'), '');
    final e164 = '+$_dial$digits';
    _lastEmitted = e164;

    var valid = digits.length >= 6 && digits.length <= 15;
    try {
      final parsed = PhoneNumber.parse(
        digits,
        callerCountry: IsoCode.values.byName(_iso),
        destinationCountry: IsoCode.values.byName(_iso),
      );
      valid = parsed.isValid();
    } catch (_) {
      // Unknown ISO or unparseable input — keep the length heuristic rather
      // than blocking the user on a country the parser doesn't cover.
    }
    widget.onChanged(e164, valid);
  }

  /// National-format the raw digits for display ("8031234567" → "803 123 4567").
  /// Falls back to the raw text when the country has no known format.
  String _format(String raw) {
    final digits = raw.replaceAll(RegExp(r'\D'), '');
    if (digits.isEmpty) return '';
    try {
      final parsed = PhoneNumber.parse(
        digits,
        callerCountry: IsoCode.values.byName(_iso),
        destinationCountry: IsoCode.values.byName(_iso),
      );
      final formatted = parsed.formatNsn();
      return formatted.isEmpty ? digits : formatted;
    } catch (_) {
      return digits;
    }
  }

  Future<void> _pickCountry() async {
    final picked = await showDialCodePicker(context, _iso);
    if (picked != null && picked != _iso) {
      setState(() => _iso = picked);
      // Regroup the existing digits for the new country's plan.
      _onTyped(_controller.text);
    }
  }

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  /// Re-formats the field in place. The caret is parked at the end: this field
  /// is typed left-to-right, and separators shift on nearly every keystroke, so
  /// tracking an interior caret would fight the formatter more than it helps.
  void _onTyped(String value) {
    final formatted = _format(value);
    if (formatted != _controller.text) {
      _controller.value = TextEditingValue(
        text: formatted,
        selection: TextSelection.collapsed(offset: formatted.length),
      );
    }
    _national = formatted;
    _emit();
  }

  @override
  Widget build(BuildContext context) {
    final colors = context.myazaColors;
    final text = context.myazaText;

    return Row(
      children: [
        InkWell(
          onTap: _pickCountry,
          borderRadius: BorderRadius.circular(MyazaRadius.md),
          child: Container(
            height: 52,
            padding: const EdgeInsets.symmetric(horizontal: MyazaSpacing.sm),
            decoration: BoxDecoration(
              border: Border.all(color: colors.border),
              borderRadius: BorderRadius.circular(MyazaRadius.md),
            ),
            child: Row(
              mainAxisSize: MainAxisSize.min,
              children: [
                MyazaCountryFlag(country: _iso, size: 22),
                const SizedBox(width: MyazaSpacing.xs),
                Text('+$_dial', style: text.label),
                Icon(Icons.arrow_drop_down, color: colors.textSecondary),
              ],
            ),
          ),
        ),
        const SizedBox(width: MyazaSpacing.sm),
        Expanded(
          child: MyazaInput(
            controller: _controller,
            hint: '803 123 4567',
            keyboardType: TextInputType.phone,
            // Digits only, but spaces the formatter inserts must survive.
            inputFormatters: [
              FilteringTextInputFormatter.allow(RegExp(r'[0-9 ]')),
            ],
            autofocus: widget.autofocus,
            onChanged: _onTyped,
          ),
        ),
      ],
    );
  }
}
