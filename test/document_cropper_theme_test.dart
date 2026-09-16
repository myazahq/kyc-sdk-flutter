import 'dart:convert';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:myaza_kyc_sdk_flutter/src/config/theme.dart';
import 'package:myaza_kyc_sdk_flutter/src/widgets/document_cropper.dart';
import 'package:myaza_kyc_sdk_flutter/src/widgets/myaza_button.dart';

// ─── The photo cropper takes the workflow's colours ──────────────────────────
//
// It used to paint a fixed navy bar, white text and the static Myaza purple
// whatever the workflow's appearance said (2026-09-15). The route is pushed
// outside the flow's own Theme, so document_capture_screen hands it the flow
// theme; this pins that the screen reads it.

// A 1×1 PNG, so the cropper has an image to decode.
final _png = base64Decode(
  'iVBORw0KGgoAAAANSUhEUgAAAAEAAAABCAYAAAAfFcSJAAAADUlEQVR42mNkYPhfDwAChwGA60e6kgAAAABJRU5ErkJggg==',
);

void main() {
  for (final (name, base, isDark) in [
    ('light', MyazaColorScheme.light, false),
    ('dark', MyazaColorScheme.dark, true),
  ]) {
    testWidgets('takes the workflow colours ($name)', (tester) async {
      final scheme = base.copyWith(primary: const Color(0xFFD9480F));
      await tester.pumpWidget(MaterialApp(
        theme: ThemeData(extensions: [scheme]),
        home: DocumentCropperScreen(imageBytes: _png),
      ));

      final appBar = tester.widget<AppBar>(find.byType(AppBar));
      expect(appBar.backgroundColor, kycHeaderSurface(scheme, isDark: isDark));
      expect(appBar.foregroundColor, scheme.textDark);

      // The action bar is the flow's surface, and the button is the flow's own.
      final button = find.widgetWithText(MyazaButton, 'Crop & Use');
      expect(button, findsOneWidget);
      final bar = tester.widget<DecoratedBox>(
        find.ancestor(of: button, matching: find.byType(DecoratedBox)).first,
      );
      expect((bar.decoration as BoxDecoration).color, scheme.background);

      // The photo stage stays neutral in both themes.
      expect(
        tester.widget<Scaffold>(find.byType(Scaffold)).backgroundColor,
        const Color(0xFF171717),
      );
    });
  }
}
