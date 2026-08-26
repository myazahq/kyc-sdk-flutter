import 'package:flutter_test/flutter_test.dart';
import 'package:myaza_kyc_sdk_flutter/src/providers/kyc_state.dart';
import 'package:myaza_kyc_sdk_flutter/src/utils/step_log.dart';

// The step log powers the dashboard's verification timeline.
//
// It never once worked: the snapshot cast its entries to Map<String, String>,
// but an entry carries an int `slot`, so the literal infers Map<String, Object>
// and the cast threw a TypeError on EVERY recorded step. The collector wrapped
// its whole body in a catch returning null, so the throw discarded the entire
// device block — no fingerprint, no SDK identity, no journey. Nothing reported
// an error; the verification simply arrived looking like it came from an
// unknown device.
void main() {
  setUp(StepLog.reset);

  test('survives a plain step', () {
    StepLog.record(KYCStep.consent);
    final snap = StepLog.snapshot();
    expect(snap, isNotNull);
    expect((snap!['steps'] as List).single['step'], 'consent');
    expect(snap['sentAt'], isA<String>());
  });

  test('survives a multi-ID step carrying an int slot — the case that threw', () {
    StepLog.record(KYCStep.idType, slot: 2, idType: 'passport');
    final steps = StepLog.snapshot()!['steps'] as List;
    expect(steps.single['slot'], 2);
    expect(steps.single['idType'], 'passport');
  });

  test('emits the kebab-case wire names, never the Dart enum names', () {
    // The server's timeline titles key off these, and camelCase would match
    // nothing — the events would be dropped rather than mislabelled.
    StepLog.record(KYCStep.documentCapture);
    StepLog.record(KYCStep.contactEmail);
    final steps = StepLog.snapshot()!['steps'] as List;
    expect(steps.map((e) => e['step']), ['document-capture', 'email-verification']);
  });

  test('collapses a consecutive duplicate but keeps a genuine revisit', () {
    StepLog.record(KYCStep.idType, slot: 1, idType: 'nin');
    StepLog.record(KYCStep.idType, slot: 1, idType: 'nin');
    // A NEW check on the same screen is a different visit, not a duplicate —
    // the server cannot tell a slot advance from a back-press without this.
    StepLog.record(KYCStep.idType, slot: 2, idType: 'bvn');
    expect((StepLog.snapshot()!['steps'] as List).length, 2);
  });

  test('is absent, not empty, when nothing was recorded', () {
    expect(StepLog.snapshot(), isNull);
  });
}
