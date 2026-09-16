import 'dart:io';

import 'package:flutter_test/flutter_test.dart';

// ─── Both ML Kit models are fetched, and every screen that needs one asks ─────
//
// The models are the largest thing this SDK puts in a host's APK: 18.5 MB per
// device bundled, about 0.4 MB of shims fetched. The default fetches them, and
// that buys a window where a model is not on the phone. The failure in that
// window is SILENT by construction: a face detector with no model finds no
// face, and a text recogniser with no model finds no lines, exactly what an
// empty frame and a blank page report. Nothing throws and nothing logs.
//
// So the dependency swap and the readiness checks are ONE change, and these pin
// that they stay one. Every assertion is about a line that would compile, pass
// every other test, and fail only as a person aiming a phone at a passport that
// never reads. Mirrors the React Native suite, __tests__/mlKitOnDemand.test.ts.

String read(String path) => File(path).readAsStringSync();

void main() {
  group('the ML Kit artifacts are chosen together', () {
    final gradle = read('android/build.gradle');

    test('one resolved flag drives the choice, read in one place', () {
      expect('def bundledMlKit = '.allMatches(gradle).length, 1);
      final declaration = gradle.substring(
        gradle.indexOf('def bundledMlKit = '),
        gradle.indexOf('android {'),
      );
      // A second read of the property is how one model ends up bundled and the
      // other fetched: a build that is neither small nor offline.
      expect(
        "'myazaKycBundledMlKit'".allMatches(gradle).length,
        "'myazaKycBundledMlKit'".allMatches(declaration).length,
      );
    });

    test('the bundled branch takes BOTH bundled artifacts', () {
      final branch = gradle.substring(
        gradle.indexOf('if (bundledMlKit)'),
        gradle.indexOf('} else {'),
      );
      expect(branch, contains('com.google.mlkit:face-detection'));
      expect(branch, contains('com.google.mlkit:text-recognition'));
    });

    test('the default branch takes BOTH fetched artifacts', () {
      final branch = gradle.substring(
        gradle.indexOf('} else {'),
        gradle.indexOf('// CameraX'),
      );
      expect(branch,
          contains('com.google.android.gms:play-services-mlkit-face-detection'));
      expect(branch,
          contains('com.google.android.gms:play-services-mlkit-text-recognition'));
    });

    test('no bundled model is declared outside the branch', () {
      expect("implementation 'com.google.mlkit:".allMatches(gradle).length, 2);
    });

    test('the flag reaches native code, so a bundled build never waits', () {
      expect(gradle, contains('buildConfigField "boolean", "BUNDLED_ML_KIT"'));
      expect(gradle, contains('buildConfig true'));
      expect(
        read('android/src/main/kotlin/co/myazahq/kyc/MlKitModelReadiness.kt'),
        contains('BuildConfig.BUNDLED_ML_KIT'),
      );
    });

    test('compileSdk is at least 36, or every host release build fails', () {
      final sdk = RegExp(r'compileSdk (\d+)').firstMatch(gradle);
      expect(sdk, isNotNull);
      expect(int.parse(sdk!.group(1)!), greaterThanOrEqualTo(36));
    });
  });

  group('the readiness check settles', () {
    final gate =
        read('android/src/main/kotlin/co/myazahq/kyc/MlKitModelReadiness.kt');

    test('the manifest names both models, so Play fetches them at install', () {
      expect(read('android/src/main/AndroidManifest.xml'),
          contains('android:value="face,ocr"'));
    });

    test('the install is urgent, never deferred', () {
      // A deferred install waits for Play Services to choose a moment, which
      // can be an idle, charging phone. The person is waiting now.
      expect(gate, contains('client.installModules('));
      expect(gate, isNot(contains('deferredInstall(')));
    });

    test('the plugin routes every question the Dart side asks', () {
      final plugin =
          read('android/src/main/kotlin/co/myazahq/kyc/KycSdkFlutterPlugin.kt');
      final dart = read('lib/src/services/model_readiness.dart');
      for (final method in const [
        'faceModelStatus',
        'prepareFaceModel',
        'textModelStatus',
        'prepareTextModel',
      ]) {
        expect(plugin, contains('"$method"'), reason: method);
        expect(dart, contains("'$method'"), reason: method);
      }
    });

    test('iOS never asks: Apple Vision ships with the OS', () {
      expect(read('lib/src/services/model_readiness.dart'),
          contains('if (!Platform.isAndroid) return NativeModelStatus.ready;'));
    });
  });

  group('where each gate bites is deliberate', () {
    test('the flow asks for both models the moment it opens', () {
      final flow = read('lib/src/widgets/myaza_kyc_widget.dart');
      expect(flow, contains('primeFaceModel();'));
      expect(flow, contains('primeTextModel();'));
    });

    test('the MRZ scanner GATES: there a missing model is a dead end', () {
      final source = read('lib/src/screens/mrz_scan_view.dart');
      expect(source, contains('ModelReadyGate.forModel(OnDeviceModel.text)'));
      expect(source, contains('case ModelReadyState.unavailable:'));
      expect(source, contains('case ModelReadyState.preparing:'));
      // The camera never starts before the model can read.
      final start = source.substring(source.indexOf('Future<void> _start()'));
      expect(
        start.indexOf('ModelReadyState.ready'),
        lessThan(start.indexOf('camera.initialize(')),
      );
    });

    test('liveness gates its camera on the face model', () {
      final source = read('lib/src/screens/liveness_screen.dart');
      expect(source, contains('ModelReadyGate.forModel(OnDeviceModel.face)'));
      expect(source,
          contains('if (_faceModel.state.value != ModelReadyState.ready) return;'));
      expect(source, contains('faceModel == ModelReadyState.unavailable'));
    });

    test('document auto-capture asks for the model but never waits on it', () {
      // An accelerator with a live shutter: a missing model costs a tap.
      final source = read('lib/src/screens/document_capture_screen.dart');
      expect(source, contains('primeTextModel();'));
      expect(source, isNot(contains('ModelReadyGate')));
    });
  });
}
