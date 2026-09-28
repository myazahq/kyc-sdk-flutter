import 'package:flutter_test/flutter_test.dart';
import 'package:myaza_kyc_sdk_flutter/src/liveness/flash_detector.dart';
import 'package:myaza_kyc_sdk_flutter/src/liveness/flash_outcome.dart';
import 'package:myaza_kyc_sdk_flutter/src/config/liveness_resume.dart';
import 'package:myaza_kyc_sdk_flutter/src/providers/kyc_state.dart';

FlashResult _result({
  required bool passed,
  required int total,
  required int inconclusive,
}) => FlashResult(
  passed: passed,
  score: 0,
  matched: 0,
  total: total,
  inconclusive: inconclusive,
  sequence: const [],
);

void main() {
  group('flashOutcome (port of the web rule)', () {
    test('passes a measured match and fails a measured mismatch', () {
      expect(
        flashOutcome(
          result: _result(passed: true, total: 4, inconclusive: 0),
          mode: 'flash',
          retriesUsed: 0,
        ),
        FlashOutcome.pass,
      );
      expect(
        flashOutcome(
          result: _result(passed: false, total: 4, inconclusive: 0),
          mode: 'both',
          retriesUsed: 0,
        ),
        FlashOutcome.fail,
      );
    });

    test('retries an unmeasurable flash once, then lets gestures carry it', () {
      final none = _result(passed: false, total: 4, inconclusive: 4);
      expect(
        flashOutcome(result: none, mode: 'flash', retriesUsed: 0),
        FlashOutcome.retry,
      );
      expect(
        flashOutcome(result: none, mode: 'both', retriesUsed: 1),
        FlashOutcome.acceptGestures,
      );
      expect(
        flashOutcome(result: none, mode: 'flash', retriesUsed: 1),
        FlashOutcome.fallbackGestures,
      );
    });

    test('a sequence that could not run is unmeasurable, never passed', () {
      expect(flashUnmeasurable(null), isTrue);
      expect(
        flashOutcome(result: null, mode: 'flash', retriesUsed: 0),
        FlashOutcome.retry,
      );
    });
  });

  test('an all-inconclusive run does not pass', () {
    final r = evaluateFlashSequence(const [], [
      const FlashSample(inconclusive: true, matched: false, score: 0),
      const FlashSample(inconclusive: true, matched: false, score: 0),
    ]);
    expect(r.passed, isFalse);
  });

  group('resumeStepWithoutSelfie', () {
    test('sends a step past liveness back to it', () {
      expect(resumeStepWithoutSelfie(KYCStep.questionnaire), KYCStep.liveness);
      expect(resumeStepWithoutSelfie(KYCStep.submitted), KYCStep.liveness);
    });

    test('leaves an earlier step alone', () {
      expect(resumeStepWithoutSelfie(KYCStep.idType), KYCStep.idType);
    });
  });
}
