import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../config/theme.dart';
import '../providers/kyc_provider.dart';
import '../services/api_service.dart';
import '../services/contact_errors.dart';
import '../widgets/myaza_button.dart';
import 'contact_verification_parts.dart';
import 'contact_verification_settings.dart';

// ─── Contact verification screen (email / phone OTP) ──────────────────────────
//
// One component, two mounts (channel: 'email' | 'phone'): enter a destination →
// send a code → enter the OTP → verify → advance. A single primary button
// carries the flow (as in the web SDK): "Send code", then "Verify code" once a
// challenge exists. The last digit also auto-submits; the button covers the
// cases where that doesn't fire. Both show the button's loader while in flight.
// NOTE: each mount needs a distinct key — see _screenForStep.

final _emailRe = RegExp(r'.+@.+\..+');

/// Server-side minimum code length (the server clamps codeLength to 4–8).
const int _kMinCodeLength = 4;

class ContactVerificationScreen extends ConsumerStatefulWidget {
  final String channel; // 'email' | 'phone'
  const ContactVerificationScreen({super.key, required this.channel});

  @override
  ConsumerState<ContactVerificationScreen> createState() =>
      _ContactVerificationScreenState();
}

class _ContactVerificationScreenState
    extends ConsumerState<ContactVerificationScreen> {
  final _emailCtrl = TextEditingController();
  String _destination = '';
  bool _phoneValid = false;
  String? _challengeId;
  DateTime? _expiresAt;
  String _code = '';
  bool _sending = false;
  bool _checking = false;
  String? _error;

  bool get _isPhone => widget.channel == 'phone';
  ContactChannelSettings get _settings => ContactChannelSettings.resolve(
      ref.read(kycConfigProvider), widget.channel);

  /// Any request in flight — drives the button loader and input disabling.
  bool get _busy => _sending || _checking;
  bool get _canSend => _isPhone ? _phoneValid : _emailRe.hasMatch(_destination);
  bool get _canVerify => _code.trim().length >= _kMinCodeLength;

  KYCApiService get _api => ref.read(kYCNotifierProvider.notifier).api;
  void _advance() => ref.read(kYCNotifierProvider.notifier).nextStep();

  @override
  void dispose() {
    _emailCtrl.dispose();
    super.dispose();
  }

  Future<void> _send() async {
    if (!_canSend || _busy) return;
    setState(() {
      _sending = true;
      _error = null;
    });
    final settings = _settings;
    try {
      final res = await _api.contactSend(
        channel: widget.channel,
        destination: _destination,
        via: settings.via,
        codeLength: settings.codeLength,
        maxAttempts: settings.maxAttempts,
      );
      if (!mounted) return;
      setState(() {
        _challengeId = res.challengeId;
        _expiresAt = DateTime.tryParse(res.expiresAt ?? '');
        _code = '';
        _sending = false;
      });
    } catch (e) {
      // Catch everything: a non-API failure (socket/TLS/parse) must still clear
      // the spinner, otherwise the button stays stuck mid-send with no message.
      if (!mounted) return;
      setState(() {
        _sending = false;
        _error = describeSendError(e);
      });
    }
  }

  Future<void> _check(String code) async {
    final value = code.trim();
    if (_challengeId == null || _busy || value.length < _kMinCodeLength) return;
    setState(() {
      _checking = true;
      _error = null;
    });
    try {
      final res =
          await _api.contactCheck(challengeId: _challengeId!, code: value);
      if (!mounted) return;
      if (res.verified && res.token.isNotEmpty) {
        // Clear before advancing — a stuck `true` reads as an endless spinner.
        setState(() => _checking = false);
        ref
            .read(kYCNotifierProvider.notifier)
            .setContactProof(widget.channel, res.token, _destination);
        _advance();
      } else {
        setState(() {
          _checking = false;
          _error = 'That code is not correct. Please try again.';
        });
      }
    } catch (e) {
      if (!mounted) return;
      setState(() {
        _checking = false;
        _error = describeCheckError(e);
      });
    }
  }

  @override
  Widget build(BuildContext context) {
    final text = context.myazaText;
    final colors = context.myazaColors;
    final settings = _settings;
    final state = ref.watch(kYCNotifierProvider);
    final verifiedToken = _isPhone ? state.phoneToken : state.emailToken;

    if (verifiedToken != null) {
      return ContactVerifiedView(
        isPhone: _isPhone,
        destination: _isPhone ? state.phoneNumber : state.emailAddress,
        onContinue: _advance,
      );
    }

    final challengeId = _challengeId;
    final hasChallenge = challengeId != null;
    final canSubmit = hasChallenge ? _canVerify : _canSend;

    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        if (!hasChallenge)
          ContactDestinationField(
            isPhone: _isPhone,
            emailController: _emailCtrl,
            defaultCountry: settings.defaultCountry,
            enabled: !_busy,
            onEmailChanged: (v) => setState(() => _destination = v.trim()),
            onPhoneChanged: (e164, valid) => setState(() {
              _destination = e164;
              _phoneValid = valid;
            }),
          )
        else
          ContactCodePanel(
            destination: _destination,
            codeLength: settings.codeLength,
            style: settings.inputStyle,
            enabled: !_busy,
            challengeId: challengeId,
            expiresAt: _expiresAt,
            onChanged: (c) => setState(() => _code = c),
            onCompleted: _check,
            onResend: _busy ? null : _send,
          ),
        if (_error != null) ...[
          const SizedBox(height: MyazaSpacing.sm),
          Text(_error!,
              style: text.bodySmall.copyWith(color: MyazaColors.error)),
        ],
        const SizedBox(height: MyazaSpacing.xl),
        MyazaButton(
          label: hasChallenge ? 'Verify code' : 'Send code',
          isLoading: _busy,
          onPressed: canSubmit && !_busy
              ? (hasChallenge ? () => _check(_code) : _send)
              : null,
        ),
        if (!settings.required) ...[
          const SizedBox(height: MyazaSpacing.sm),
          Center(
            child: TextButton(
              onPressed: _busy ? null : _advance,
              child: Text('Skip for now',
                  style: text.bodyMedium.copyWith(color: colors.textSecondary)),
            ),
          ),
        ],
      ],
    );
  }
}
