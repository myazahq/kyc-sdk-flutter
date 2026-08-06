import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../config/id_types.dart';
import '../config/kyc_config.dart';
import '../config/theme.dart';
import '../providers/kyc_provider.dart';
import '../providers/step_order.dart';
import '../services/validators.dart';
import '../widgets/myaza_button.dart';
import '../widgets/myaza_input.dart';

// ─── ID input screen ──────────────────────────────────────────────────────────

class IdInputScreen extends ConsumerStatefulWidget {
  const IdInputScreen({super.key});

  @override
  ConsumerState<IdInputScreen> createState() => _IdInputScreenState();
}

class _IdInputScreenState extends ConsumerState<IdInputScreen> {
  late final TextEditingController _idCtrl;
  String? _idError;

  @override
  void initState() {
    super.initState();
    // No OCR pre-fill — for number-only IDs (BVN, NIN, vNIN) the user
    // always types the number manually.
    final s = ref.read(kYCNotifierProvider);
    _idCtrl = TextEditingController(text: s.idNumber ?? '');
  }

  @override
  void dispose() {
    _idCtrl.dispose();
    super.dispose();
  }

  MyazaKYCConfig get _config => ref.read(kycConfigProvider);
  IdTypeConfig? get _idType => ref.read(kYCNotifierProvider).selectedIdType;
  String get _country =>
      effectiveCountry(_config, ref.read(kYCNotifierProvider));

  void _onIdChanged(String value) {
    final idType = _idType;
    if (idType == null) return;
    final result = validateIdNumber(value.trim(), _country, idType.key);
    setState(() {
      _idError = (result.isValid || value.trim().isEmpty)
          ? null
          : result.errorMessage;
    });
  }

  bool get _canSubmit {
    final val = _idCtrl.text.trim();
    final idType = _idType;
    if (val.isEmpty || idType == null) return false;
    return validateIdNumber(val, _country, idType.key).isValid;
  }

  TextInputType _keyboardType(String key) => switch (key) {
        'bvn' || 'bvn-premium' || 'tax-id' || 'nin' => TextInputType.number,
        _ => TextInputType.visiblePassword,
      };

  List<TextInputFormatter>? _inputFormatters(String key) => switch (key) {
        'bvn' || 'bvn-premium' || 'tax-id' || 'nin' => [
            FilteringTextInputFormatter.digitsOnly,
          ],
        _ => null,
      };

  void _onContinue() {
    if (!_canSubmit) return;
    final notifier = ref.read(kYCNotifierProvider.notifier);
    final configUserData = _config.userData;
    final existing = ref.read(kYCNotifierProvider).userData;

    notifier.setIdNumber(_idCtrl.text.trim());

    notifier.setUserData(UserData(
      firstName: existing?.firstName ?? configUserData?.firstName,
      lastName: existing?.lastName ?? configUserData?.lastName,
      dateOfBirth: existing?.dateOfBirth ?? configUserData?.dateOfBirth,
      gender: existing?.gender ?? configUserData?.gender,
      address: existing?.address ?? configUserData?.address,
    ));

    notifier.nextStep();
  }

  @override
  Widget build(BuildContext context) {
    final text   = context.myazaText;
    final state  = ref.watch(kYCNotifierProvider);
    final idTypeCfg = state.selectedIdType;

    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        // ── ID number field ────────────────────────────────────────────────────
        if (idTypeCfg != null)
          Text(idTypeCfg.inputLabel ?? idTypeCfg.label, style: text.label),
        const SizedBox(height: MyazaSpacing.sm),
        MyazaInput(
          hint: _hintFor(idTypeCfg),
          controller: _idCtrl,
          keyboardType: idTypeCfg != null
              ? _keyboardType(idTypeCfg.key)
              : TextInputType.text,
          inputFormatters:
              idTypeCfg != null ? _inputFormatters(idTypeCfg.key) : null,
          maxLength: idTypeCfg?.digits,
          errorText: _idError,
          autofocus: true,
          onChanged: _onIdChanged,
        ),

        const SizedBox(height: MyazaSpacing.xl),

        ListenableBuilder(
          listenable: _idCtrl,
          builder: (_, __) => MyazaButton(
            label: 'Continue',
            onPressed: _canSubmit ? _onContinue : null,
          ),
        ),
      ],
    );
  }
}

// ─── Hint text helper ─────────────────────────────────────────────────────────

String _hintFor(IdTypeConfig? cfg) {
  if (cfg == null) return 'Enter your ID number';
  final label = cfg.inputLabel ?? cfg.label;
  if (cfg.digits != null) {
    return 'Enter ${cfg.digits}-digit $label';
  }
  return 'Enter your $label';
}
