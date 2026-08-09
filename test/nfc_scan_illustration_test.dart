import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:myaza_kyc_sdk_flutter/src/widgets/nfc_scan_illustration.dart';
import 'package:myaza_kyc_sdk_flutter/src/widgets/nfc_scan_painter.dart';

/// Parity pins for the NFC illustration port. The web component is the design
/// source of truth; these assert the constants and the animation curve that
/// would otherwise drift silently.
void main() {
  test('waves match the web SDK digit for digit', () {
    expect(nfcScanCoupling, const Offset(173, 88));
    expect(nfcScanWaves.map((w) => w.$1), [16.0, 28.0, 40.0, 50.0]);
    expect(nfcScanWaves.map((w) => w.$2), [0.9, 0.65, 0.42, 0.25]);
    expect(nfcScanWaves.map((w) => w.$3), [0, 150, 300, 450]);
  });

  test('pulse follows the web keyframes: .25 at the ends, 1 at 45%', () {
    expect(nfcWavePulse(0, 0), closeTo(0.25, 1e-9));
    expect(nfcWavePulse(0.45, 0), closeTo(1, 1e-9));
    expect(nfcWavePulse(0.9999, 0), closeTo(0.25, 0.01));
    // A delayed ripple is the same curve shifted, never a different curve.
    expect(nfcWavePulse(450 / 1800, 450), closeTo(nfcWavePulse(0, 0), 1e-9));
  });

  test('pulse never leaves the web animation range', () {
    for (var t = 0.0; t < 1; t += 0.01) {
      for (final (_, _, delay) in nfcScanWaves) {
        final v = nfcWavePulse(t, delay);
        expect(v, inInclusiveRange(0.25, 1.0));
      }
    }
  });

  testWidgets('renders at the web footprint: max 384 wide, 320:240', (tester) async {
    await tester.pumpWidget(
      const MaterialApp(home: Scaffold(body: Center(child: NfcScanIllustration()))),
    );
    final paintSize = tester.getSize(find.byType(CustomPaint).last);
    expect(paintSize.width, lessThanOrEqualTo(384));
    expect(paintSize.width / paintSize.height, closeTo(320 / 240, 1e-6));
    // The pulse is live by default…
    expect(tester.hasRunningAnimations, isTrue);
  });

  testWidgets('reduced motion stops the pulse but keeps the drawing', (tester) async {
    await tester.pumpWidget(
      const MediaQuery(
        data: MediaQueryData(disableAnimations: true),
        child: MaterialApp(home: Scaffold(body: NfcScanIllustration())),
      ),
    );
    await tester.pump();
    expect(tester.hasRunningAnimations, isFalse);
    expect(find.byType(CustomPaint), findsWidgets);
  });
}
