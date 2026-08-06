import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:myaza_kyc_sdk_flutter/src/liveness/capture_tuning.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  const channel = MethodChannel('kyc_sdk_flutter/capture_tuning');
  final calls = <MethodCall>[];

  void mockChannel({bool throws = false}) {
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(channel, (call) async {
      calls.add(call);
      if (throws) throw PlatformException(code: 'unsupported');
      return null;
    });
  }

  setUp(calls.clear);
  tearDown(() {
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(channel, null);
  });

  test('raises the screen to full brightness before sampling', () async {
    mockChannel();
    await beginFlashTuning();
    expect(calls.single.method, 'beginFlash');
    expect(calls.single.arguments['brightness'], kFlashBrightness);
  });

  test('locks exposure alongside the native white-balance lock', () async {
    mockChannel();
    var locked = false;
    await beginFlashTuning(lockExposure: () async => locked = true);
    expect(locked, isTrue);
  });

  test('restores brightness and unlocks exposure', () async {
    mockChannel();
    var unlocked = false;
    await endFlashTuning(unlockExposure: () async => unlocked = true);
    expect(calls.single.method, 'restore');
    expect(unlocked, isTrue);
  });

  // Tuning is an enhancement, not a gate. A device that won't hold a lock
  // should produce a weaker signal (more flashes scored inconclusive), never a
  // failed verification — so nothing here may throw into the capture flow.
  test('a platform failure never propagates', () async {
    mockChannel(throws: true);
    await expectLater(beginFlashTuning(), completes);
    await expectLater(endFlashTuning(), completes);
  });

  test('an exposure-lock failure never propagates', () async {
    mockChannel();
    await expectLater(
      beginFlashTuning(lockExposure: () async => throw Exception('busy')),
      completes,
    );
    await expectLater(
      endFlashTuning(unlockExposure: () async => throw Exception('busy')),
      completes,
    );
  });

  test('restore still runs when the platform call fails', () async {
    mockChannel(throws: true);
    var unlocked = false;
    await endFlashTuning(unlockExposure: () async => unlocked = true);
    // The user's screen brightness is theirs; a failed native restore must not
    // skip the rest of the cleanup.
    expect(unlocked, isTrue);
  });
}
