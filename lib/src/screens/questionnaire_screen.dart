import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../config/questionnaire.dart';
import '../config/currency_flags.dart';
import '../config/theme.dart';
import '../providers/kyc_provider.dart';
import '../widgets/myaza_button.dart';
import '../widgets/amount_input_formatter.dart';
import '../widgets/country_flag.dart';
import '../widgets/myaza_input.dart';
import '../widgets/myaza_select.dart';
import '../widgets/themed_sheet.dart';

// ─── Questionnaire screen ─────────────────────────────────────────────────────
//
// Renders the org-authored questionnaire (7 field types) after capture, before
// submission. Answers are validated client-side (required / min / max / money
// ≥ 0) and re-validated server-side against the published definition. Money
// fields store both `<key>` (amount) and `<key>_currency`.

class QuestionnaireScreen extends ConsumerStatefulWidget {
  const QuestionnaireScreen({super.key});

  @override
  ConsumerState<QuestionnaireScreen> createState() =>
      _QuestionnaireScreenState();
}

class _QuestionnaireScreenState extends ConsumerState<QuestionnaireScreen> {
  final Map<String, dynamic> _answers = {};
  final Map<String, TextEditingController> _controllers = {};
  final Map<String, String?> _errors = {};

  QuestionnaireConfig get _cfg =>
      ref.read(kycConfigProvider).questionnaire ??
      const QuestionnaireConfig();

  @override
  void initState() {
    super.initState();
    // Seed from any previously entered answers (e.g. returning via back).
    _answers.addAll(ref.read(kYCNotifierProvider).questionnaireAnswers);
    for (final f in _cfg.fields) {
      if (f.type == QuestionnaireFieldType.text ||
          f.type == QuestionnaireFieldType.number ||
          f.type == QuestionnaireFieldType.money) {
        _controllers[f.key] =
            TextEditingController(text: _answers[f.key]?.toString() ?? '');
      }
      if (f.type == QuestionnaireFieldType.money &&
          _answers['${f.key}_currency'] == null &&
          f.currencies.isNotEmpty) {
        _answers['${f.key}_currency'] = f.currencies.first;
      }
    }
  }

  @override
  void dispose() {
    for (final c in _controllers.values) {
      c.dispose();
    }
    super.dispose();
  }

  String? _validateField(QuestionnaireField f) {
    final v = _answers[f.key];
    final empty = v == null ||
        (v is String && v.trim().isEmpty) ||
        (v is List && v.isEmpty);
    if (f.required && empty) return 'This field is required.';
    if (empty) return null;
    if (f.type == QuestionnaireFieldType.number ||
        f.type == QuestionnaireFieldType.money) {
      final n = v is num ? v : num.tryParse(v.toString());
      if (n == null) return 'Enter a valid number.';
      if (f.type == QuestionnaireFieldType.money && n < 0) {
        return 'Amount cannot be negative.';
      }
      if (f.min != null && n < f.min!) return 'Must be at least ${f.min}.';
      if (f.max != null && n > f.max!) return 'Must be at most ${f.max}.';
    }
    return null;
  }

  void _onContinue() {
    final errors = <String, String?>{};
    var ok = true;
    for (final f in _cfg.fields) {
      final err = _validateField(f);
      errors[f.key] = err;
      if (err != null) ok = false;
    }
    setState(() => _errors
      ..clear()
      ..addAll(errors));
    if (!ok) return;
    ref.read(kYCNotifierProvider.notifier).setQuestionnaireAnswers(
          Map<String, dynamic>.from(_answers),
        );
    ref.read(kYCNotifierProvider.notifier).nextStep();
  }

  @override
  Widget build(BuildContext context) {
    final text = context.myazaText;
    final cfg = _cfg;

    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        if (cfg.description != null) ...[
          Text(cfg.description!, style: text.bodyMedium),
          const SizedBox(height: MyazaSpacing.lg),
        ],
        for (final f in cfg.fields) ...[
          _FieldLabel(field: f),
          const SizedBox(height: MyazaSpacing.xs),
          _buildField(f),
          if (_errors[f.key] != null) ...[
            const SizedBox(height: MyazaSpacing.xs),
            Text(_errors[f.key]!,
                style: text.bodySmall.copyWith(color: MyazaColors.error)),
          ],
          const SizedBox(height: MyazaSpacing.lg),
        ],
        MyazaButton(label: 'Continue', onPressed: _onContinue),
      ],
    );
  }

  Widget _buildField(QuestionnaireField f) => switch (f.type) {
        QuestionnaireFieldType.text => MyazaInput(
            controller: _controllers[f.key],
            hint: f.placeholder ?? 'Enter ${f.label.toLowerCase()}',
            onChanged: (v) => _answers[f.key] = v,
          ),
        QuestionnaireFieldType.number => MyazaInput(
            controller: _controllers[f.key],
            hint: f.placeholder ?? '0',
            keyboardType:
                const TextInputType.numberWithOptions(decimal: true),
            inputFormatters: [
              FilteringTextInputFormatter.allow(RegExp(r'[0-9.]'))
            ],
            onChanged: (v) => _answers[f.key] = num.tryParse(v.trim()),
          ),
        QuestionnaireFieldType.money => _MoneyField(
            field: f,
            controller: _controllers[f.key]!,
            currency: _answers['${f.key}_currency'] as String?,
            onAmount: (n) => _answers[f.key] = n,
            onCurrency: (c) => setState(() => _answers['${f.key}_currency'] = c),
          ),
        QuestionnaireFieldType.select => _SelectField(
            field: f,
            value: _answers[f.key] as String?,
            onChanged: (v) => setState(() => _answers[f.key] = v),
          ),
        QuestionnaireFieldType.multiselect => _MultiSelectField(
            field: f,
            values: (_answers[f.key] as List?)?.cast<String>() ?? const [],
            onChanged: (list) =>
                setState(() => _answers[f.key] = list.isEmpty ? null : list),
          ),
        QuestionnaireFieldType.boolean => _BooleanField(
            value: _answers[f.key] as bool?,
            onChanged: (v) => setState(() => _answers[f.key] = v),
          ),
        QuestionnaireFieldType.date => _DateField(
            field: f,
            value: _answers[f.key] as String?,
            onChanged: (v) => setState(() => _answers[f.key] = v),
          ),
      };
}

// ─── Field label (+ optional/help) ─────────────────────────────────────────────

class _FieldLabel extends StatelessWidget {
  final QuestionnaireField field;
  const _FieldLabel({required this.field});

  @override
  Widget build(BuildContext context) {
    final text = context.myazaText;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text.rich(TextSpan(children: [
          TextSpan(text: field.label, style: text.label),
          if (field.required)
            TextSpan(text: ' *',
                style: text.label.copyWith(color: MyazaColors.error)),
        ])),
        if (field.helpText != null)
          Text(field.helpText!,
              style: text.bodySmall.copyWith(color: context.myazaColors.textSecondary)),
      ],
    );
  }
}

// ─── Money field (amount + currency) ───────────────────────────────────────────

class _MoneyField extends StatelessWidget {
  final QuestionnaireField field;
  final TextEditingController controller;
  final String? currency;
  final void Function(num?) onAmount;
  final void Function(String) onCurrency;

  const _MoneyField({
    required this.field,
    required this.controller,
    required this.currency,
    required this.onAmount,
    required this.onCurrency,
  });

  @override
  Widget build(BuildContext context) {
    final colors = context.myazaColors;
    final text = context.myazaText;
    // Matches MyazaInput's 48px single-line height so the currency control
    // lines up with the amount field instead of sitting short.
    const controlHeight = 48.0;

    return Row(
      crossAxisAlignment: CrossAxisAlignment.center,
      children: [
        Expanded(
          child: MyazaInput(
            controller: controller,
            hint: field.placeholder ?? '0.00',
            keyboardType: const TextInputType.numberWithOptions(decimal: true),
            inputFormatters: const [AmountInputFormatter()],
            onChanged: (v) {
              final n = parseGroupedAmount(v);
              onAmount(n == null ? null : double.parse(n.toStringAsFixed(2)));
            },
          ),
        ),
        const SizedBox(width: MyazaSpacing.sm),
        if (field.currencies.length > 1)
          SizedBox(
            height: controlHeight,
            child: MyazaSelect<String>(
              compact: true,
              sheetTitle: 'Currency',
              value: currency ?? field.currencies.first,
              options: [
                for (final c in field.currencies)
                  MyazaSelectOption(
                    value: c,
                    label: c,
                    leading: _CurrencyFlag(currency: c),
                  ),
              ],
              onChanged: onCurrency,
            ),
          )
        else if (field.currencies.isNotEmpty)
          Container(
            height: controlHeight,
            alignment: Alignment.center,
            padding: const EdgeInsets.symmetric(horizontal: MyazaSpacing.md),
            decoration: BoxDecoration(
              color: colors.primary50,
              borderRadius: BorderRadius.circular(MyazaRadius.sm),
            ),
            child: Row(
              mainAxisSize: MainAxisSize.min,
              children: [
                _CurrencyFlag(currency: field.currencies.first),
                const SizedBox(width: MyazaSpacing.xs),
                Text(field.currencies.first,
                    style: text.label.copyWith(fontWeight: FontWeight.w600)),
              ],
            ),
          ),
      ],
    );
  }
}

/// Flag for a currency code — omitted for supranational codes that no single
/// country represents.
class _CurrencyFlag extends StatelessWidget {
  final String currency;
  const _CurrencyFlag({required this.currency});

  @override
  Widget build(BuildContext context) {
    final country = currencyFlagCountry(currency);
    if (country == null) return const SizedBox.shrink();
    return MyazaCountryFlag(country: country, size: 18);
  }
}

// ─── Select (single) ───────────────────────────────────────────────────────────

class _SelectField extends StatelessWidget {
  final QuestionnaireField field;
  final String? value;
  final void Function(String?) onChanged;

  const _SelectField({
    required this.field,
    required this.value,
    required this.onChanged,
  });

  @override
  Widget build(BuildContext context) {
    return MyazaSelect<String>(
      value: value,
      hint: field.placeholder ?? 'Select an option',
      sheetTitle: field.label,
      options: [
        for (final o in field.options)
          MyazaSelectOption(value: o.value, label: o.label),
      ],
      onChanged: onChanged,
    );
  }
}

// ─── Multi-select ──────────────────────────────────────────────────────────────

class _MultiSelectField extends StatelessWidget {
  final QuestionnaireField field;
  final List<String> values;
  final void Function(List<String>) onChanged;

  const _MultiSelectField({
    required this.field,
    required this.values,
    required this.onChanged,
  });

  @override
  Widget build(BuildContext context) {
    final colors = context.myazaColors;
    return Column(
      children: [
        for (final o in field.options)
          CheckboxListTile(
            contentPadding: EdgeInsets.zero,
            dense: true,
            controlAffinity: ListTileControlAffinity.leading,
            activeColor: colors.primary,
            value: values.contains(o.value),
            title: Text(o.label, style: context.myazaText.bodyMedium),
            onChanged: (checked) {
              final next = List<String>.from(values);
              if (checked == true) {
                next.add(o.value);
              } else {
                next.remove(o.value);
              }
              onChanged(next);
            },
          ),
      ],
    );
  }
}

// ─── Boolean (Yes / No) ────────────────────────────────────────────────────────

class _BooleanField extends StatelessWidget {
  final bool? value;
  final void Function(bool) onChanged;

  const _BooleanField({required this.value, required this.onChanged});

  @override
  Widget build(BuildContext context) {
    return Row(
      children: [
        Expanded(child: _choice(context, 'Yes', true)),
        const SizedBox(width: MyazaSpacing.sm),
        Expanded(child: _choice(context, 'No', false)),
      ],
    );
  }

  Widget _choice(BuildContext context, String label, bool v) {
    final colors = context.myazaColors;
    final selected = value == v;
    return InkWell(
      onTap: () => onChanged(v),
      borderRadius: BorderRadius.circular(MyazaRadius.md),
      child: Container(
        height: 48,
        alignment: Alignment.center,
        decoration: BoxDecoration(
          color: selected ? colors.primary50 : colors.background,
          border: Border.all(
            color: selected ? colors.primary : colors.border,
            width: selected ? 1.5 : 1.0,
          ),
          borderRadius: BorderRadius.circular(MyazaRadius.md),
        ),
        child: Text(label,
            style: context.myazaText.label.copyWith(
              fontWeight: FontWeight.w600,
              color: selected ? colors.primary : colors.textDark,
            )),
      ),
    );
  }
}

// ─── Date ──────────────────────────────────────────────────────────────────────

class _DateField extends StatelessWidget {
  final QuestionnaireField field;
  final String? value;
  final void Function(String) onChanged;

  const _DateField({
    required this.field,
    required this.value,
    required this.onChanged,
  });

  @override
  Widget build(BuildContext context) {
    final colors = context.myazaColors;
    final text = context.myazaText;
    return InkWell(
      onTap: () async {
        final now = DateTime.now();
        final initial = DateTime.tryParse(value ?? '') ?? now;
        final picked = await showMyazaDatePicker(
          context,
          initialDate: initial,
          firstDate: DateTime(1900),
          lastDate: DateTime(now.year + 5),
        );
        if (picked != null) {
          final iso = picked.toIso8601String().split('T').first;
          onChanged(iso);
        }
      },
      borderRadius: BorderRadius.circular(MyazaRadius.md),
      child: Container(
        height: 52,
        padding: const EdgeInsets.symmetric(horizontal: MyazaSpacing.md),
        decoration: BoxDecoration(
          border: Border.all(color: colors.border),
          borderRadius: BorderRadius.circular(MyazaRadius.md),
        ),
        child: Row(
          children: [
            Icon(Icons.calendar_today, size: 18, color: colors.textSecondary),
            const SizedBox(width: MyazaSpacing.sm),
            Text(
              value ?? (field.placeholder ?? 'Select a date'),
              style: text.bodyMedium.copyWith(
                color: value == null ? colors.textSecondary : colors.textDark,
              ),
            ),
          ],
        ),
      ),
    );
  }
}
