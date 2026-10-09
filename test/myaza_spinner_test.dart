import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:myaza_kyc_sdk_flutter/src/widgets/myaza_pulse_loader.dart';
import 'package:myaza_kyc_sdk_flutter/src/widgets/myaza_spinner.dart';

// One loading spinner across the SDK: the web SDK's and the dashboard's own
// (their `Loader2`, Hugeicons' Loading02). Material's indicator is a different
// drawing and is not used anywhere.

void main() {
  test('is the web icon: the same path, stroke and turn', () {
    expect(kSpinnerPath.startsWith('M18.001 20C16.3295 21.2558'), isTrue);
    expect(kSpinnerPath.endsWith('15.6076 18'), isTrue);
    expect(kSpinnerStroke, 1.6);
    expect(kSpinnerTurn, const Duration(milliseconds: 1000));
  });

  test('the path is read whole and sits inside the icon box', () {
    final bounds = spinnerPath().getBounds();
    expect(bounds.left, closeTo(2, 0.01));
    expect(bounds.top, closeTo(2, 0.01));
    expect(bounds.right, closeTo(22, 0.01));
    expect(bounds.bottom, closeTo(22, 0.01));
  });

  test('fills a small loader box and half of a large one', () {
    expect(MyazaPulseLoader.spinnerSize(20), 20);
    expect(MyazaPulseLoader.spinnerSize(64), 32);
    expect(MyazaPulseLoader.spinnerSize(80), 40);
  });

  testWidgets('fills the box it is given, and is 36 across without one', (tester) async {
    await tester.pumpWidget(const MaterialApp(
      home: Center(child: SizedBox(width: 20, height: 20, child: MyazaSpinner())),
    ));
    expect(tester.getSize(find.byType(RotationTransition).last), const Size(20, 20));
    await tester.pumpWidget(const MaterialApp(
      home: SingleChildScrollView(
        scrollDirection: Axis.horizontal,
        child: UnconstrainedBox(child: MyazaSpinner()),
      ),
    ));
    expect(tester.getSize(find.byType(RotationTransition).last), const Size(36, 36));
    await tester.pumpWidget(const SizedBox.shrink());
  });

  test('is the only spinner: no screen mounts the Material indicator', () {
    final offenders = Directory('lib')
        .listSync(recursive: true)
        .whereType<File>()
        .where((f) => f.path.endsWith('.dart') && !f.path.endsWith('myaza_spinner.dart'))
        .where((f) => f.readAsStringSync().contains('CircularProgressIndicator'))
        .map((f) => f.path)
        .toList();
    expect(offenders, isEmpty);
  });
}
