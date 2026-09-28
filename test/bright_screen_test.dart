import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:myaza_kyc_sdk_flutter/myaza_kyc_sdk_flutter.dart';
import 'package:myaza_kyc_sdk_flutter/src/config/bright_screen.dart';
import 'package:myaza_kyc_sdk_flutter/src/config/theme.dart';
import 'package:myaza_kyc_sdk_flutter/src/config/workflow_merge.dart';
import 'package:myaza_kyc_sdk_flutter/src/liveness/flash_overlay_color.dart';
import 'package:myaza_kyc_sdk_flutter/src/services/api_service.dart';

// ─── Bright screen during liveness ────────────────────────────────────────────
//
// While the selfie camera is on, the flow renders light and the screen is held
// at full; a flash sequence's neutral frames are black whatever the theme. The
// same rules as the web and React Native SDKs.

const _base = MyazaKYCConfig(apiKey: 'pk_test_x', country: 'NG');

WorkflowFlowConfig _flow(Map<String, dynamic> config) => WorkflowResolution.fromJson({
      'flow': {'id': 'wf_x', 'name': 'Face', 'version': 1},
      'config': {'country': 'NG', ...config},
      'environment': 'SANDBOX',
      'idTypes': <dynamic>[],
    }).config;

void main() {
  group('flashOverlayColor', () {
    const red = Color(0xFFFF0000);

    test('the colour under test always shows', () {
      expect(flashOverlayColor(flashColor: red, sequenceRunning: true), red);
    });

    test('between colours the neutral frame is black, never the screen behind', () {
      expect(
        flashOverlayColor(flashColor: null, sequenceRunning: true),
        kFlashBaselineColor,
      );
      expect(kFlashBaselineColor, const Color(0xFF000000));
    });

    test('outside a sequence the overlay shows nothing', () {
      expect(flashOverlayColor(flashColor: null, sequenceRunning: false), isNull);
    });
  });

  group('when the screen is lit', () {
    test('only on the liveness step, with its camera on, unless switched off', () {
      expect(
        livenessBrightScreenActive(enabled: true, onLivenessStep: true, cameraOn: true),
        isTrue,
      );
      expect(
        livenessBrightScreenActive(enabled: false, onLivenessStep: true, cameraOn: true),
        isFalse,
      );
      expect(
        livenessBrightScreenActive(enabled: true, onLivenessStep: false, cameraOn: true),
        isFalse,
      );
      expect(
        livenessBrightScreenActive(enabled: true, onLivenessStep: true, cameraOn: false),
        isFalse,
      );
    });

    test('the camera counts as on only once started and before the selfie', () {
      bool running({
        bool started = true,
        bool pastPrimers = true,
        bool faceModelReady = true,
        bool permissionDenied = false,
        bool selfieTaken = false,
      }) =>
          livenessCameraRunning(
            started: started,
            pastPrimers: pastPrimers,
            faceModelReady: faceModelReady,
            permissionDenied: permissionDenied,
            selfieTaken: selfieTaken,
          );
      expect(running(), isTrue);
      expect(running(started: false), isFalse);
      expect(running(pastPrimers: false), isFalse);
      expect(running(faceModelReady: false), isFalse);
      expect(running(permissionDenied: true), isFalse);
      expect(running(selfieTaken: true), isFalse);
    });

    test('the primers keep the normal theme; the camera screen lights the rest of the step', () {
      // One liveness step, frame by frame: the ready screen, the camera
      // permission primer, the camera starting, the camera, then the review
      // after the selfie. The lit flag is the step's latch.
      var lit = false;
      bool frame({
        bool started = false,
        bool pastPrimers = false,
        bool selfieTaken = false,
      }) =>
          lit = livenessStepLit(
            alreadyLit: lit,
            cameraRunning: livenessCameraRunning(
              started: started,
              pastPrimers: pastPrimers,
              faceModelReady: true,
              permissionDenied: false,
              selfieTaken: selfieTaken,
            ),
          );
      expect(frame(), isFalse, reason: 'ready screen');
      // "Grant access" tapped: the primer is still up while _init starts.
      expect(frame(started: true), isFalse, reason: 'permission primer');
      expect(frame(started: true, pastPrimers: true), isTrue, reason: 'camera');
      expect(
        frame(started: true, pastPrimers: true, selfieTaken: true),
        isTrue,
        reason: 'the review after the selfie stays lit',
      );
      expect(
        livenessBrightScreenActive(enabled: true, onLivenessStep: true, cameraOn: lit),
        isTrue,
      );
      // Leaving the step drops it, whatever the latch says.
      expect(
        livenessBrightScreenActive(enabled: true, onLivenessStep: false, cameraOn: lit),
        isFalse,
      );
    });

    test('a step that opens on a stored selfie never lights up', () {
      expect(
        livenessStepLit(
          alreadyLit: false,
          cameraRunning: livenessCameraRunning(
            started: false,
            pastPrimers: false,
            faceModelReady: true,
            permissionDenied: false,
            selfieTaken: true,
          ),
        ),
        isFalse,
      );
    });

    test('brightness lets go when the app leaves the foreground', () {
      expect(brightScreenBoostWanted(active: true), isTrue);
      expect(
        brightScreenBoostWanted(active: true, lifecycle: AppLifecycleState.resumed),
        isTrue,
      );
      // The control centre or a permission prompt: still on screen.
      expect(
        brightScreenBoostWanted(active: true, lifecycle: AppLifecycleState.inactive),
        isTrue,
      );
      for (final gone in [
        AppLifecycleState.paused,
        AppLifecycleState.hidden,
        AppLifecycleState.detached,
      ]) {
        expect(brightScreenBoostWanted(active: true, lifecycle: gone), isFalse);
      }
      expect(brightScreenBoostWanted(active: false), isFalse);
    });

    test('no transition under reduced motion', () {
      expect(brightScreenTransition(disableAnimations: false), kBrightScreenTransition);
      expect(kBrightScreenTransition, const Duration(milliseconds: 300));
      expect(brightScreenTransition(disableAnimations: true), Duration.zero);
    });
  });

  group('the lit palette', () {
    const appearance = MyazaKYCAppearance(
      backgroundColor: Color(0xFFFAFAF7),
      dark: MyazaKYCAppearance(backgroundColor: Color(0xFF101010)),
    );

    test("is the organisation's base palette, never its dark overrides", () {
      final lit = brightScreenScheme(appearance);
      expect(lit.background, const Color(0xFFFAFAF7));
      expect(brightScreenScheme(null).background, MyazaColorScheme.light.background);
    });

    test('blends from the person\'s theme and flips to light at the midpoint', () {
      const dark = MyazaColorScheme.dark;
      final lit = brightScreenScheme(appearance);
      final start = blendBrightScreen(userScheme: dark, userIsDark: true, litScheme: lit, t: 0);
      expect(start.scheme.background, dark.background);
      expect(start.isDark, isTrue);
      expect(start.headerSurface, kycHeaderSurface(dark, isDark: true));

      final early = blendBrightScreen(userScheme: dark, userIsDark: true, litScheme: lit, t: 0.4);
      expect(early.isDark, isTrue);

      final end = blendBrightScreen(userScheme: dark, userIsDark: true, litScheme: lit, t: 1);
      expect(end.scheme.background, lit.background);
      expect(end.isDark, isFalse);
      expect(end.headerSurface, kycHeaderSurface(lit, isDark: false));
    });
  });

  group('livenessBrightScreen', () {
    test('is on by default', () {
      expect(_base.livenessBrightScreen, isTrue);
      expect(_base.copyWith().livenessBrightScreen, isTrue);
    });

    test('rides a workflow: absent leaves it on, only false turns it off', () {
      expect(mergeWorkflowIntoConfig(_base, _flow({})).livenessBrightScreen, isTrue);
      expect(
        mergeWorkflowIntoConfig(_base, _flow({'livenessBrightScreen': true}))
            .livenessBrightScreen,
        isTrue,
      );
      expect(
        mergeWorkflowIntoConfig(_base, _flow({'livenessBrightScreen': false}))
            .livenessBrightScreen,
        isFalse,
      );
    });

    test("an applicant workflow's own setting governs the applicant's selfie", () {
      const applicant = ApplicantWorkflow(
        id: 'wf_app',
        name: 'Applicant',
        version: 1,
        config: {'country': 'NG', 'livenessBrightScreen': false},
      );
      expect(overlayApplicantWorkflow(_base, applicant).livenessBrightScreen, isFalse);
      const silent = ApplicantWorkflow(id: 'wf_s', name: 'S', version: 1, config: {'country': 'NG'});
      expect(overlayApplicantWorkflow(_base, silent).livenessBrightScreen, isTrue);
    });
  });
}
