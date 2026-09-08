import 'biometric_copy.dart';
import 'kyc_config.dart';
import 'scope.dart';

// ─── The biometric scopes' flow options ─────────────────────────────────────
//
// Mirrors the server's lib/workflows/biometric-options.ts and the web/RN
// SDKs' biometric-options; keep the DEFAULTS in lockstep across the four. All
// three are UX policy this SDK enforces (user decision 2026-09-07, React
// Native first, ported here). A published workflow sets them in the builder's
// Presence Intelligence panel; a prop-configured mount passes the same
// `biometric` block.
//
//   selfieReview    Show the captured selfie with Retake and Continue before
//                   submitting. OFF by default on both biometric scopes: a
//                   re-authentication is a few-second check, and a review
//                   screen is a stop in the middle of it. The liveness step
//                   hands straight over once the ring has closed.
//   resultDelivery  WHERE the verdict lands. 'both' (the default) and 'app'
//                   both hold the person on one loading screen from the
//                   shutter to the verdict, polling the publishable status
//                   endpoint until the check settles, because a
//                   re-authentication is answered NOW or it is useless; they
//                   differ only on the SERVER, which sends no webhook for an
//                   'app' check. 'webhook' is the fire-and-forget model every
//                   other flow runs. Enrolment has no verdict to deliver, so
//                   it never waits.
//   doneButton      Whether the final screen carries a Done button (default
//                   ON). Off when the host app dismisses the flow itself from
//                   `onResult` (or `onSubmit` on a webhook delivery), so the
//                   person is never shown a button the app is about to act
//                   for. The screen then stays until the host closes the SDK.
//   copy            The org's own words on the loading and verdict screens
//                   (config/biometric_copy.dart).

class BiometricFlowConfig {
  final bool? selfieReview;

  /// 'app' | 'webhook' | 'both'. Any other value is ignored (the default applies).
  final String? resultDelivery;
  final bool? doneButton;
  final BiometricCopy? copy;

  const BiometricFlowConfig({this.selfieReview, this.resultDelivery, this.doneButton, this.copy});

  static const Set<String> deliveries = {'app', 'webhook', 'both'};

  factory BiometricFlowConfig.fromJson(Map<String, dynamic> json) {
    final delivery = json['resultDelivery'];
    final copy = json['copy'];
    return BiometricFlowConfig(
      selfieReview: json['selfieReview'] as bool?,
      resultDelivery: delivery is String && deliveries.contains(delivery) ? delivery : null,
      doneButton: json['doneButton'] as bool?,
      copy: copy is Map ? BiometricCopy.fromJson(copy.cast<String, dynamic>()) : null,
    );
  }

  /// Per-field merge: [over] wins on every field it sets, this fills the gaps
  /// (a flow that only switches the review on keeps a host's `doneButton`).
  BiometricFlowConfig merge(BiometricFlowConfig? over) => over == null
      ? this
      : BiometricFlowConfig(
          selfieReview: over.selfieReview ?? selfieReview,
          resultDelivery: over.resultDelivery ?? resultDelivery,
          doneButton: over.doneButton ?? doneButton,
          copy: (copy ?? const BiometricCopy()).merge(over.copy),
        );
}

class BiometricFlowOptions {
  final bool selfieReview;

  /// Null on enrolment: nothing is delivered, so there is nothing to wait for.
  final String? resultDelivery;
  final bool doneButton;

  const BiometricFlowOptions({
    required this.selfieReview,
    required this.resultDelivery,
    required this.doneButton,
  });
}

/// The effective options, or null when the flow is not a biometric scope.
BiometricFlowOptions? biometricFlowOptions({String? scope, BiometricFlowConfig? biometric}) {
  final resolved = configScope(scope);
  if (resolved != 'biometric-authentication' && resolved != 'biometric-enrollment') return null;
  final block = biometric ?? const BiometricFlowConfig();
  return BiometricFlowOptions(
    selfieReview: block.selfieReview ?? false,
    resultDelivery: resolved == 'biometric-authentication' ? (block.resultDelivery ?? 'both') : null,
    doneButton: block.doneButton ?? true,
  );
}

/// Whether the liveness step shows the selfie review before handing over. A
/// full verification always does; only the biometric scopes can switch it off.
bool showsSelfieReview({String? scope, BiometricFlowConfig? biometric}) =>
    biometricFlowOptions(scope: scope, biometric: biometric)?.selfieReview ?? true;

/// Whether the submitted step waits for the verdict in the flow ('app' and
/// 'both') rather than leaving it to the webhook. Only a re-authentication
/// ever does.
bool waitsForResult({String? scope, BiometricFlowConfig? biometric}) {
  final delivery = biometricFlowOptions(scope: scope, biometric: biometric)?.resultDelivery;
  return delivery == 'app' || delivery == 'both';
}

/// Whether the final screen carries a Done button. Always on off the
/// biometric scopes; only they can hide it.
bool showsDoneButton({String? scope, BiometricFlowConfig? biometric}) =>
    biometricFlowOptions(scope: scope, biometric: biometric)?.doneButton ?? true;

/// The same three questions asked of a whole config.
extension BiometricFlowConfigX on MyazaKYCConfig {
  bool get showsSelfieReviewOption => showsSelfieReview(scope: scope, biometric: biometric);
  bool get waitsForResultOption => waitsForResult(scope: scope, biometric: biometric);
  bool get showsDoneButtonOption => showsDoneButton(scope: scope, biometric: biometric);
}
