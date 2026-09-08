import 'dart:io';

import 'package:flutter_test/flutter_test.dart';

// A MULTI-ID run must be able to submit.
//
// Every check commits its own slot and CLEARS the picker so the next check can
// choose — so by the time the run submits there is no current selection at all.
// The submit guard required one, which refused every multi-ID submission with
// "No ID type selected": the applicant walked the whole run, uploaded every
// document, and was rejected by the client before a request was ever made.
//
// A SOURCE test because the failure is of a CONDITION, not of behaviour a unit
// test can reach without a provider, a store and a live camera. The condition
// is one line, and it is the line that broke.
void main() {
  final source = File('lib/src/providers/kyc_provider.dart').readAsStringSync();

  test('the submit guard accepts a committed multi-ID run', () {
    // It must NOT throw on a null selection alone — the slots are the run's
    // record of what was picked.
    expect(
      source.contains(
          'if (idTypeConfig == null && committedSlots.isEmpty && configScope(_config.scope) == null)'),
      isTrue,
      reason: 'the guard must let a run with committed slots through '
          '(and a scoped flow, which never picks an ID)',
    );
    expect(
      source.contains('if (idTypeConfig == null) {\n      throw'),
      isFalse,
      reason: 'a bare null-selection guard refuses every multi-ID submission',
    );
  });

  test('number-only validation is scoped to the single-ID path', () {
    // Each multi-ID check validated its own number at its own step, and that
    // number rides its own slot — re-validating a state field that belongs to
    // no particular check would fail an otherwise complete run.
    expect(source.contains('if (idTypeConfig != null) {'), isTrue);
  });

  test('the top-level idType falls back to the first slot', () {
    // The FIRST slot fills the single-ID columns so anything reading a
    // verification's own idType keeps one meaning.
    expect(
      source.contains("primary?.idType ?? idTypeConfig?.key ?? ''"),
      isTrue,
    );
  });
}
