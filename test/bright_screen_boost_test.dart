import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:myaza_kyc_sdk_flutter/src/liveness/screen_brightness.dart';
import 'package:myaza_kyc_sdk_flutter/src/widgets/bright_screen_boost.dart';

// ─── The screen is held bright while the selfie camera is on ─────────────────
//
// And given back on every way out: the flag dropping, the app leaving the
// foreground, and the flow going away. A platform that refuses must never
// throw into the flow.

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  const channel = MethodChannel('kyc_sdk_flutter/capture_tuning');
  final calls = <String>[];
  final messenger =
      TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger;

  void mockChannel({bool throws = false}) {
    messenger.setMockMethodCallHandler(channel, (call) async {
      calls.add(call.method);
      if (call.method == 'setBrightness') {
        expect((call.arguments as Map)['brightness'], kBrightScreenLevel);
      }
      if (throws) throw PlatformException(code: 'unsupported');
      return null;
    });
  }

  setUp(calls.clear);
  tearDown(() => messenger.setMockMethodCallHandler(channel, null));

  Widget host(bool active) =>
      BrightScreenBoost(active: active, child: const SizedBox());

  testWidgets('raises once while active and restores when it drops',
      (tester) async {
    mockChannel();
    await tester.pumpWidget(host(false));
    expect(calls, isEmpty);

    await tester.pumpWidget(host(true));
    await tester.pumpWidget(host(true)); // idempotent
    expect(calls, ['setBrightness']);

    await tester.pumpWidget(host(false));
    expect(calls, ['setBrightness', 'restoreBrightness']);
  });

  testWidgets('gives the screen back when the app is backgrounded',
      (tester) async {
    mockChannel();
    await tester.pumpWidget(host(true));
    tester.binding.handleAppLifecycleStateChanged(AppLifecycleState.inactive);
    tester.binding.handleAppLifecycleStateChanged(AppLifecycleState.hidden);
    tester.binding.handleAppLifecycleStateChanged(AppLifecycleState.paused);
    expect(calls, ['setBrightness', 'restoreBrightness']);

    tester.binding.handleAppLifecycleStateChanged(AppLifecycleState.hidden);
    tester.binding.handleAppLifecycleStateChanged(AppLifecycleState.inactive);
    tester.binding.handleAppLifecycleStateChanged(AppLifecycleState.resumed);
    expect(calls, ['setBrightness', 'restoreBrightness', 'setBrightness']);
  });

  testWidgets('restores when the flow goes away', (tester) async {
    mockChannel();
    await tester.pumpWidget(host(true));
    await tester.pumpWidget(const SizedBox());
    expect(calls, ['setBrightness', 'restoreBrightness']);
  });

  testWidgets('a refusing platform never throws into the flow', (tester) async {
    mockChannel(throws: true);
    await tester.pumpWidget(host(true));
    await tester.pumpWidget(host(false));
    await tester.pumpWidget(const SizedBox());
    expect(tester.takeException(), isNull);
    expect(calls, ['setBrightness', 'restoreBrightness']);
  });

  test('restore without a raise sends nothing', () async {
    mockChannel();
    await ScreenBrightnessBoost().restore();
    expect(calls, isEmpty);
  });
}
