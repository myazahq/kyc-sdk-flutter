import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:myaza_kyc_sdk_flutter/src/config/kyc_config.dart';
import 'package:myaza_kyc_sdk_flutter/src/config/theme.dart';
import 'package:myaza_kyc_sdk_flutter/src/screens/submitted_error_view.dart';

// A refused submission offered only Close, while its message said "go back".

Widget _host(Widget child) => MaterialApp(
      theme: ThemeData(extensions: const [MyazaColorScheme.light]),
      home: Scaffold(body: SizedBox(height: 700, child: child)),
    );

void main() {
  const error = KYCError(code: 'unknown', message: 'Some required business documents are missing.');

  testWidgets('offers Go back when there is a step to return to', (tester) async {
    var wentBack = false;
    await tester.pumpWidget(_host(ErrorView(error: error, onClose: () {}, onGoBack: () => wentBack = true)));
    await tester.pumpAndSettle();
    expect(find.text('Close'), findsOneWidget);
    await tester.tap(find.text('Go back'));
    expect(wentBack, isTrue);
  });

  testWidgets('shows Close alone when there is nowhere to go', (tester) async {
    await tester.pumpWidget(_host(ErrorView(error: error, onClose: () {})));
    await tester.pumpAndSettle();
    expect(find.text('Go back'), findsNothing);
    expect(find.text('Close'), findsOneWidget);
  });
}
