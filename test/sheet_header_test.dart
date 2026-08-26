import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:lucide_icons_flutter/lucide_icons.dart';
import 'package:myaza_kyc_sdk_flutter/src/config/theme.dart';
import 'package:myaza_kyc_sdk_flutter/src/widgets/themed_sheet.dart';

// The sheet's close button, which is the half of this that can fail invisibly.
//
// showMyazaSheet's own header comment warns that an SDK sheet is a SIBLING
// route, not a descendant — that is exactly the situation where
// `Navigator.of(context).pop()` reaches for the wrong navigator. A close button
// that renders perfectly and either does nothing or tears down the whole flow
// looks identical to a working one until somebody taps it.

Widget _host(GlobalKey<NavigatorState> nav) => MaterialApp(
      navigatorKey: nav,
      theme: ThemeData(extensions: const [MyazaColorScheme.light]),
      home: Builder(
        builder: (context) => Scaffold(
          body: Center(
            child: ElevatedButton(
              onPressed: () => showMyazaSheet<void>(
                context,
                builder: (_) => const SizedBox(height: 200, child: Text('sheet body')),
              ),
              child: const Text('open'),
            ),
          ),
        ),
      ),
    );

void main() {
  testWidgets('a sheet carries a way out, and it closes only the sheet',
      (tester) async {
    final nav = GlobalKey<NavigatorState>();
    await tester.pumpWidget(_host(nav));

    await tester.tap(find.text('open'));
    await tester.pumpAndSettle();
    expect(find.text('sheet body'), findsOneWidget);
    expect(find.byIcon(LucideIcons.x), findsOneWidget, reason: 'no way out');

    await tester.tap(find.byIcon(LucideIcons.x));
    await tester.pumpAndSettle();

    expect(find.text('sheet body'), findsNothing);
    // The page underneath must survive: popping the wrong navigator would take
    // the flow with it and leave a blank screen behind the dismissed sheet.
    expect(find.text('open'), findsOneWidget);
  });

  testWidgets('a sheet that draws its own dismiss does not get a second one',
      (tester) async {
    final nav = GlobalKey<NavigatorState>();
    await tester.pumpWidget(
      MaterialApp(
        navigatorKey: nav,
        theme: ThemeData(extensions: const [MyazaColorScheme.light]),
        home: Builder(
          builder: (context) => Scaffold(
            body: Center(
              child: ElevatedButton(
                onPressed: () => showMyazaSheet<void>(
                  context,
                  showHeader: false,
                  builder: (_) => const SizedBox(height: 200, child: Text('own chrome')),
                ),
                child: const Text('open'),
              ),
            ),
          ),
        ),
      ),
    );

    await tester.tap(find.text('open'));
    await tester.pumpAndSettle();
    expect(find.text('own chrome'), findsOneWidget);
    expect(find.byIcon(LucideIcons.x), findsNothing);
  });

  testWidgets('the handle rides at the lip, not halfway down the panel',
      (tester) async {
    // The regression this pins: laid out as a ROW, the handle centred against
    // the tallest child, so the close button's 44pt touch box decided how far
    // down the sheet the grabber sat. It read as correct in review and shipped.
    final nav = GlobalKey<NavigatorState>();
    await tester.pumpWidget(_host(nav));
    await tester.tap(find.text('open'));
    await tester.pumpAndSettle();

    final handleTop = tester.getTopLeft(find.byKey(kMyazaSheetHandleKey)).dy;
    final closeTop = tester.getTopLeft(find.byType(IconButton)).dy;

    // Both hang off the top of the header. Centring the handle against a 44pt
    // button would put this gap around 20.
    expect(handleTop - closeTop, lessThan(12),
        reason: 'the close button is pushing the handle down the panel');
  });

  testWidgets('a tall sheet stops below the status bar', (tester) async {
    // Invisible without a notched device: `isScrollControlled` lets a sheet
    // grow to the full screen, and on a phone with an island that put the
    // sheet's own close button behind it and the title in the status bar.
    const topInset = 59.0; // a Dynamic Island phone
    final nav = GlobalKey<NavigatorState>();
    await tester.pumpWidget(
      MaterialApp(
        navigatorKey: nav,
        theme: ThemeData(extensions: const [MyazaColorScheme.light]),
        home: MediaQuery(
          data: const MediaQueryData(padding: EdgeInsets.only(top: topInset)),
          child: Builder(
            builder: (context) => Scaffold(
              body: Center(
                child: ElevatedButton(
                  onPressed: () => showMyazaSheet<void>(
                    context,
                    isScrollControlled: true,
                    // Taller than the screen: it must be capped, not clipped
                    // off the top.
                    builder: (_) => const SizedBox(height: 5000, child: Text('tall')),
                  ),
                  child: const Text('open'),
                ),
              ),
            ),
          ),
        ),
      ),
    );

    await tester.tap(find.text('open'));
    await tester.pumpAndSettle();

    final panel = tester.getRect(find.byKey(kMyazaSheetHandleKey));
    expect(panel.top, greaterThanOrEqualTo(topInset),
        reason: 'the sheet header is under the status bar');
  });
}
