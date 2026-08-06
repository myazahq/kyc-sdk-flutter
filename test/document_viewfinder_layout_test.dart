import 'package:flutter/material.dart';
import 'package:lucide_icons_flutter/lucide_icons.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:myaza_kyc_sdk_flutter/src/config/id_types.dart';
import 'package:myaza_kyc_sdk_flutter/src/services/document_framing_gate.dart';
import 'package:myaza_kyc_sdk_flutter/src/widgets/country_flag.dart';
import 'package:myaza_kyc_sdk_flutter/src/widgets/document_ghost.dart';
import 'package:myaza_kyc_sdk_flutter/src/widgets/document_info_pill.dart';
import 'package:myaza_kyc_sdk_flutter/src/widgets/document_viewfinder.dart';

// The full-screen viewfinder stacks controls over a live camera, where a
// mis-parented or overlapping child is invisible in tests but obvious (and
// unusable) on a phone — the hint spent a build sitting behind the shutter.
// These render it for real and assert the things that actually broke.

// context.myazaColors falls back to the light scheme without a MyazaTheme
// ancestor, so a plain MaterialApp is enough here.
Widget _host(Widget child) => MaterialApp(home: Scaffold(body: child));

DocumentViewfinder _viewfinder({
  DocumentHint hint = DocumentHint.searching,
  IdTypeConfig? idType,
  VoidCallback? onUpload,
  VoidCallback? onToggleTorch,
  DocumentFraming framing = DocumentFraming.none,
}) =>
    DocumentViewfinder(
      controller: null,
      isLoading: false,
      error: null,
      isBack: false,
      isProcessing: false,
      guideAspect: 1.586,
      framing: framing,
      onCapture: () {},
      hint: hint,
      hintLabel: 'Passport',
      idType: idType,
      country: 'NG',
      onBack: () {},
      onUpload: onUpload,
      onToggleTorch: onToggleTorch,
    );

void main() {
  testWidgets('renders without a ParentDataWidget error', (tester) async {
    // A Positioned nested in the bottom Column compiles fine and throws only at
    // runtime — which is exactly how the info pill first shipped.
    await tester.pumpWidget(_host(_viewfinder()));
    expect(tester.takeException(), isNull);
  });

  testWidgets('the hint never sits behind the shutter', (tester) async {
    await tester.pumpWidget(_host(_viewfinder(
      hint: DocumentHint.wrongDocument,
      onUpload: () {},
    )));
    await tester.pump();

    final hint = tester.getRect(find.byKey(kDocumentHintKey));
    final shutter = tester.getRect(find.byKey(kDocumentShutterKey));
    expect(hint.bottom, lessThanOrEqualTo(shutter.top),
        reason: 'hint overlaps the shutter');
  });

  testWidgets('the torch sits on the shutter row, not the top corner',
      (tester) async {
    await tester.pumpWidget(_host(_viewfinder(onToggleTorch: () {})));
    await tester.pump();

    final torch = tester.getRect(find.byKey(kDocumentTorchKey));
    final shutter = tester.getRect(find.byKey(kDocumentShutterKey));
    // Same row as the shutter, and to its right.
    expect(torch.center.dy, closeTo(shutter.center.dy, 8));
    expect(torch.left, greaterThan(shutter.right));
  });

  testWidgets('the shutter stays centred with or without a torch',
      (tester) async {
    for (final onToggleTorch in [null, () {}]) {
      await tester.pumpWidget(_host(_viewfinder(onToggleTorch: onToggleTorch)));
      await tester.pump();
      final screen = tester.getRect(find.byType(DocumentViewfinder));
      final shutter = tester.getRect(find.byKey(kDocumentShutterKey));
      expect(shutter.center.dx, closeTo(screen.center.dx, 1),
          reason: 'shutter drifts off centre when torch is '
              '${onToggleTorch == null ? "absent" : "present"}');
    }
  });

  testWidgets('shows the ID type and country when given one', (tester) async {
    final idType = curatedIdType('NG', 'passport')!;
    await tester.pumpWidget(_host(_viewfinder(idType: idType)));
    await tester.pump();

    expect(find.byType(DocumentInfoPill), findsOneWidget);
    // The flag stands in for the country; the name would be the same fact twice.
    expect(find.byType(MyazaCountryFlag), findsOneWidget);
    expect(find.text('Nigeria'), findsNothing);
    // Shown short: the catalogue label ("International Passport") is written
    // for a picker, not for a pill beside a flag.
    expect(find.text('Passport'), findsOneWidget);
  });

  testWidgets('the layout ghost shows, then gets out of the way', (tester) async {
    await tester.pumpWidget(_host(_viewfinder()));
    await tester.pump();

    // AnimatedOpacity builds a FadeTransition, not an Opacity.
    double ghostOpacity() => tester
        .widget<FadeTransition>(
          find.descendant(
            of: find.byType(DocumentGhost),
            matching: find.byType(FadeTransition),
          ),
        )
        .opacity
        .value;

    expect(ghostOpacity(), 1, reason: 'ghost should be visible at open');

    // It is guidance for an empty frame — it must not sit over the document
    // for the whole session.
    await tester.pump(kDocumentGhostDuration);
    await tester.pump(const Duration(milliseconds: 500));
    expect(ghostOpacity(), 0, reason: 'ghost should fade out');
  });

  testWidgets('the ghost yields as soon as a document is framed',
      (tester) async {
    await tester.pumpWidget(_host(_viewfinder(framing: DocumentFraming.holding)));
    await tester.pump(const Duration(milliseconds: 500));

    final opacity = tester
        .widget<FadeTransition>(
          find.descendant(
            of: find.byType(DocumentGhost),
            matching: find.byType(FadeTransition),
          ),
        )
        .opacity
        .value;
    expect(opacity, 0);
  });

  testWidgets('top controls clear the status bar through a removePadding '
      'ancestor', (tester) async {
    // Reproduces the real tree: the flow is shown with
    // showModalBottomSheet(useSafeArea: false), which Flutter wraps in
    // MediaQuery.removePadding(removeTop: true) — that zeroes padding.top AND
    // reduces viewPadding.top to zero, so reading either from the inherited
    // MediaQuery puts the back button under the status bar.
    const statusBar = 59.0;
    tester.view.devicePixelRatio = 3.0;
    tester.view.viewPadding = const FakeViewPadding(top: statusBar * 3);
    tester.view.padding = const FakeViewPadding(top: statusBar * 3);
    addTearDown(tester.view.reset);

    await tester.pumpWidget(MaterialApp(
      home: Builder(
        builder: (ctx) => MediaQuery.removePadding(
          context: ctx,
          removeTop: true,
          child: Scaffold(body: _viewfinder(onToggleTorch: () {})),
        ),
      ),
    ));
    await tester.pump();

    final back = tester.getRect(find.byIcon(LucideIcons.arrowLeft));
    expect(back.top, greaterThanOrEqualTo(statusBar),
        reason: 'back button overlaps the status bar');
  });

  testWidgets('omits the pill when no ID type is known', (tester) async {
    await tester.pumpWidget(_host(_viewfinder()));
    expect(find.byType(DocumentInfoPill), findsNothing);
  });
}
