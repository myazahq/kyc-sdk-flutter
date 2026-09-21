import 'package:flutter_test/flutter_test.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:myaza_kyc_sdk_flutter/myaza_kyc_sdk_flutter.dart';
import 'package:myaza_kyc_sdk_flutter/src/providers/kyc_provider.dart';
import 'package:myaza_kyc_sdk_flutter/src/widgets/kyc_flow_scope.dart';

// ─── Leaving document capture hands the chrome back ──────────────────────────
//
// Regression (user report 2026-09-19, Flutter): open the camera, press back,
// pick the ID again, and the step rendered with no header and its content
// under the status bar.
//
// `immersiveCapture` is raised by the document-capture screen while a
// full-bleed camera is on screen, but it lives on the SHELL and outlives that
// screen. The screen's write is deferred to a post-frame callback guarded on
// `mounted`, so backing out unmounts it first and the write never lands. The
// shell also gates on the step, which hid the raised flag while another step
// was showing — and then applied it again the moment the applicant returned.
//
// Clearing it on every step transition means a return can never inherit it.

ProviderContainer _container() => ProviderContainer(
      overrides: kycFlowOverrides(
        const MyazaKYCConfig(
          apiKey: 'pk_test_x',
          country: 'NG',
          idTypes: ['passport'],
        ),
        null,
      ),
    );

void main() {
  group('immersiveCapture', () {
    test('is cleared when the flow leaves document capture', () {
      final c = _container();
      addTearDown(c.dispose);
      final notifier = c.read(kYCNotifierProvider.notifier);

      notifier.goToStep(KYCStep.documentCapture);
      notifier.setImmersiveCapture(true);
      expect(c.read(kYCNotifierProvider).immersiveCapture, isTrue);

      notifier.goToStep(KYCStep.idType);
      expect(
        c.read(kYCNotifierProvider).immersiveCapture,
        isFalse,
        reason: 'the shell must get its chrome back on another step',
      );
    });

    test('a return to document capture does not inherit the raised flag', () {
      final c = _container();
      addTearDown(c.dispose);
      final notifier = c.read(kYCNotifierProvider.notifier);

      // Camera open, then back out to the ID picker without the screen's
      // post-frame write ever landing — exactly what unmounting does.
      notifier.goToStep(KYCStep.documentCapture);
      notifier.setImmersiveCapture(true);
      notifier.goToStep(KYCStep.idType);

      // Pick the ID again.
      notifier.goToStep(KYCStep.documentCapture);
      expect(
        c.read(kYCNotifierProvider).immersiveCapture,
        isFalse,
        reason: 'the ready primer has no camera, so it keeps the chrome',
      );
    });

    test('staying on document capture keeps the camera full-bleed', () {
      final c = _container();
      addTearDown(c.dispose);
      final notifier = c.read(kYCNotifierProvider.notifier);

      notifier.goToStep(KYCStep.documentCapture);
      notifier.setImmersiveCapture(true);
      // A no-op transition must not drop the flag out from under a live camera.
      notifier.goToStep(KYCStep.documentCapture);
      expect(c.read(kYCNotifierProvider).immersiveCapture, isTrue);
    });
  });
}
