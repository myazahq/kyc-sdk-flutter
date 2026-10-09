import 'package:flutter_test/flutter_test.dart';
import 'package:myaza_kyc_sdk_flutter/src/presence/presence_auto_arm.dart';
import 'package:myaza_kyc_sdk_flutter/src/presence/presence_store.dart';
import 'package:myaza_kyc_sdk_flutter/src/presence/presence_watch_wait.dart';

// ─── The reporter arms background monitoring for a running check ─────────────
//
// People verified before the SDK could ask for "allow all the time", and
// always-on arrangements, never pass the submit step again, so their checks
// collected app-open reports only. A port of the RN SDK's
// presenceAutoArm.test.ts: keep the two in lockstep.

StoredPin _pin({bool alwaysOn = false, bool background = true, bool asked = false}) => StoredPin(
      lat: 4.95,
      lng: 8.32,
      savedAt: '2026-09-01T00:00:00.000Z',
      alwaysOn: alwaysOn,
      background: background,
      backgroundAsked: asked,
    );

const _running = WatchState('in_progress', stopped: false);

ArmDecision _decide({
  bool optedOut = false,
  bool fresh = false,
  StoredPin? pin,
  WatchState? watch = _running,
  bool armed = false,
  bool alwaysGranted = false,
}) =>
    shouldArmBackground(
      optedOut: optedOut,
      fresh: fresh,
      pin: pin ?? _pin(),
      watch: watch,
      armed: armed,
      alwaysGranted: alwaysGranted,
    );

void main() {
  group('shouldArmBackground', () {
    test('asks once for a running check that has no background monitoring', () {
      expect(_decide(), ArmDecision.ask);
    });

    test('never asks a second time for the same stored address', () {
      expect(_decide(pin: _pin(asked: true)), ArmDecision.skip);
    });

    test('arms without a prompt when "allow all the time" is already granted, asked or not', () {
      expect(_decide(alwaysGranted: true), ArmDecision.silent);
      expect(_decide(alwaysGranted: true, pin: _pin(asked: true)), ArmDecision.silent);
    });

    test('does nothing when the host opted out', () {
      expect(_decide(optedOut: true), ArmDecision.skip);
    });

    test('leaves a just-saved address to the submit step', () {
      expect(_decide(fresh: true), ArmDecision.skip);
    });

    test('does nothing when the fence is already armed', () {
      expect(_decide(armed: true, alwaysGranted: true), ArmDecision.skip);
    });

    test('respects a workflow that switched background monitoring off', () {
      expect(_decide(pin: _pin(background: false)), ArmDecision.skip);
      expect(_decide(pin: _pin(background: false), alwaysGranted: true), ArmDecision.skip);
    });

    test('asks nobody when the server could not be read, or monitoring was stopped', () {
      expect(_decide(watch: null), ArmDecision.skip);
      expect(_decide(watch: const WatchState('revoked', stopped: true)), ArmDecision.skip);
      expect(
        _decide(watch: const WatchState('verified', stopped: true), pin: _pin(alwaysOn: true)),
        ArmDecision.skip,
      );
    });

    test('does nothing for a finished one-off check', () {
      expect(_decide(watch: const WatchState('verified', stopped: false)), ArmDecision.skip);
      expect(_decide(watch: const WatchState('not_started', stopped: false)), ArmDecision.skip);
    });

    test('keeps an always-on arrangement armed between two checks', () {
      expect(
        _decide(watch: const WatchState('verified', stopped: false), pin: _pin(alwaysOn: true)),
        ArmDecision.ask,
      );
      expect(
        _decide(watch: const WatchState('inconclusive', stopped: false), pin: _pin(alwaysOn: true)),
        ArmDecision.ask,
      );
    });

    test('does not re-arm an always-on arrangement that ended in a failed check', () {
      expect(
        _decide(watch: const WatchState('failed', stopped: false), pin: _pin(alwaysOn: true)),
        ArmDecision.skip,
      );
    });
  });
}
