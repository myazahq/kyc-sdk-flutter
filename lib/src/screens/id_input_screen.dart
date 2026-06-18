import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../config/id_types.dart';
import '../config/kyc_config.dart';
import '../config/theme.dart';
import '../providers/kyc_provider.dart';
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
  IdType? get _idType => ref.read(kYCNotifierProvider).selectedIdType;

  void _onIdChanged(String value) {
    final idType = _idType;
    if (idType == null) return;
    final result = validateIdNumber(value.trim(), _config.country, idType);
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
    return validateIdNumber(val, _config.country, idType).isValid;
  }

  TextInputType _keyboardType(IdType idType) => switch (idType) {
        IdType.bvn || IdType.bvnPremium || IdType.taxId || IdType.nin => TextInputType.number,
        _ => TextInputType.visiblePassword,
      };

  List<TextInputFormatter>? _inputFormatters(IdType idType) => switch (idType) {
        IdType.bvn || IdType.bvnPremium || IdType.taxId || IdType.nin => [FilteringTextInputFormatter.digitsOnly],
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
    final idType = state.selectedIdType;
    final idTypeCfg =
        idType != null ? getIdTypeConfig(_config.country, idType) : null;

    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        // ── ID number field ────────────────────────────────────────────────────
        if (idTypeCfg != null)
          Text(idTypeCfg.inputLabel ?? idTypeCfg.label, style: text.label),
        const SizedBox(height: MyazaSpacing.sm),
        MyazaInput(
          hint: _hintFor(idType, idTypeCfg),
          controller: _idCtrl,
          keyboardType: idType != null ? _keyboardType(idType) : TextInputType.text,
          inputFormatters: idType != null ? _inputFormatters(idType) : null,
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

String _hintFor(IdType? idType, IdTypeConfig? cfg) {
  if (idType == null || cfg == null) return 'Enter your ID number';
  final label = cfg.inputLabel ?? cfg.label;
  if (cfg.digits != null) {
    return 'Enter ${cfg.digits}-digit $label';
  }
  return 'Enter your $label';
}
