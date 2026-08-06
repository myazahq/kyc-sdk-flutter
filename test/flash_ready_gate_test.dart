import 'package:flutter_test/flutter_test.dart';
import 'package:myaza_kyc_sdk_flutter/src/liveness/flash_ready_gate.dart';

void main() {
  // A fixed epoch — the gate takes an injected clock, so time is deterministic.
  final t0 = DateTime.utc(2026);
  DateTime at(int ms) => t0.add(Duration(milliseconds: ms));

  FlashReadyState feed(
    FlashReadyGate gate, {
    required bool framed,
    required bool lit,
    required bool lightingConfirmed,
    required int atMs,
  }) =>
      gate.update(
        framed: framed,
        lit: lit,
        lightingConfirmed: lightingConfirmed,
        now: at(atMs),
      );

  group('does not flash prematurely', () {
    test('never ready on the very first framed+lit frame', () {
      final gate = FlashReadyGate();
      final r = feed(gate, framed: true, lit: true, lightingConfirmed: true, atMs: 0);
      expect(r.ready, isFalse);
      // The whole bug this guards against: one good frame used to trigger the
      // flash immediately, before any guidance could show.
    });

    test('not ready until the dwell has fully elapsed', () {
      final gate = FlashReadyGate(dwell: const Duration(milliseconds: 1200));
      feed(gate, framed: true, lit: true, lightingConfirmed: true, atMs: 0);
      expect(feed(gate, framed: true, lit: true, lightingConfirmed: true, atMs: 1199).ready, isFalse);
      expect(feed(gate, framed: true, lit: true, lightingConfirmed: true, atMs: 1200).ready, isTrue);
    });
  });

  group('lighting must be confirmed, not merely unwarned', () {
    test('a framed face with UNCONFIRMED lighting does not flash on the dwell alone', () {
      // The warmup race: `lit` is true because no warning has fired YET, but the
      // sampler has not actually measured the room. Flashing here would skip the
      // "more light" prompt entirely.
      final gate = FlashReadyGate(
        dwell: const Duration(milliseconds: 1200),
        lightingWait: const Duration(milliseconds: 3000),
      );
      feed(gate, framed: true, lit: true, lightingConfirmed: false, atMs: 0);
      expect(feed(gate, framed: true, lit: true, lightingConfirmed: false, atMs: 1200).ready, isFalse);
    });

    test('flashes once lighting is confirmed and the dwell is met', () {
      final gate = FlashReadyGate(dwell: const Duration(milliseconds: 1200));
      feed(gate, framed: true, lit: true, lightingConfirmed: false, atMs: 0);
      // Sampler confirms lighting at 800ms; dwell completes at 1200ms.
      expect(feed(gate, framed: true, lit: true, lightingConfirmed: true, atMs: 1200).ready, isTrue);
    });

    test('safety valve: proceeds if lighting is NEVER confirmed, after the wait', () {
      // A device whose brightness sampling never yields must not trap the user
      // on a permanent hold.
      final gate = FlashReadyGate(
        dwell: const Duration(milliseconds: 1200),
        lightingWait: const Duration(milliseconds: 3000),
      );
      feed(gate, framed: true, lit: true, lightingConfirmed: false, atMs: 0);
      expect(feed(gate, framed: true, lit: true, lightingConfirmed: false, atMs: 2999).ready, isFalse);
      expect(feed(gate, framed: true, lit: true, lightingConfirmed: false, atMs: 3000).ready, isTrue);
    });
  });

  group('the hold must be continuous', () {
    test('losing framing mid-dwell restarts it', () {
      final gate = FlashReadyGate(dwell: const Duration(milliseconds: 1200));
      feed(gate, framed: true, lit: true, lightingConfirmed: true, atMs: 0);
      feed(gate, framed: true, lit: true, lightingConfirmed: true, atMs: 800);
      // Face drifts out of frame.
      feed(gate, framed: false, lit: true, lightingConfirmed: true, atMs: 900);
      // Re-framed at 1200ms — the clock starts over from there, so it must not
      // be ready until 1200ms LATER (2400ms), not at the original 1200 mark.
      expect(feed(gate, framed: true, lit: true, lightingConfirmed: true, atMs: 1200).ready, isFalse);
      expect(feed(gate, framed: true, lit: true, lightingConfirmed: true, atMs: 2399).ready, isFalse);
      expect(feed(gate, framed: true, lit: true, lightingConfirmed: true, atMs: 2400).ready, isTrue);
    });

    test('a lighting warning mid-dwell restarts it', () {
      final gate = FlashReadyGate(dwell: const Duration(milliseconds: 1200));
      feed(gate, framed: true, lit: true, lightingConfirmed: true, atMs: 0);
      feed(gate, framed: true, lit: false, lightingConfirmed: true, atMs: 600); // went dark
      expect(feed(gate, framed: true, lit: true, lightingConfirmed: true, atMs: 1200).ready, isFalse);
    });

    test('progress resets to 0 when the hold breaks', () {
      final gate = FlashReadyGate(dwell: const Duration(milliseconds: 1200));
      feed(gate, framed: true, lit: true, lightingConfirmed: true, atMs: 600);
      final broken = feed(gate, framed: false, lit: true, lightingConfirmed: true, atMs: 700);
      expect(broken.progress, 0);
    });
  });

  test('progress climbs 0 → 1 across the dwell', () {
    final gate = FlashReadyGate(dwell: const Duration(milliseconds: 1000));
    expect(feed(gate, framed: true, lit: true, lightingConfirmed: true, atMs: 0).progress, 0);
    expect(feed(gate, framed: true, lit: true, lightingConfirmed: true, atMs: 500).progress, closeTo(0.5, 1e-9));
    expect(feed(gate, framed: true, lit: true, lightingConfirmed: true, atMs: 1000).progress, 1);
  });

  test('reset clears the hold for a retry', () {
    final gate = FlashReadyGate(dwell: const Duration(milliseconds: 1200));
    feed(gate, framed: true, lit: true, lightingConfirmed: true, atMs: 0);
    gate.reset();
    // 1200ms of wall-time passed, but the hold was reset — so measuring from a
    // fresh start, this frame is the beginning again.
    expect(feed(gate, framed: true, lit: true, lightingConfirmed: true, atMs: 1200).ready, isFalse);
  });
}
