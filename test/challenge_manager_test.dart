import 'package:flutter_test/flutter_test.dart';
import 'package:myaza_kyc_sdk_flutter/src/liveness/challenge_manager.dart';
import 'package:myaza_kyc_sdk_flutter/src/liveness/liveness_types.dart';

// Selection mirrors the web SDK's liveness/challenge-manager.ts. A head TURN is
// always one of the gestures, because the server's shape-from-movement test
// needs one; its position stays random, a nod never sits beside it, and no
// prompt repeats. Passive Liveness asks only for the hold.

List<LivenessChallenge> _types(ChallengeManager m) =>
    [for (final c in m.selectedChallenges) c.type];

void main() {
  group('3D Active Motion (gestures)', () {
    test('always includes a head turn, never beside a nod', () {
      for (var i = 0; i < 200; i++) {
        final types = _types(ChallengeManager());
        expect(types, contains(LivenessChallenge.turn));
        expect(types, isNot(contains(LivenessChallenge.nod)));
        expect(types.toSet(), hasLength(types.length));
        expect(types, hasLength(2));
      }
    });

    test('keeps the order random: the turn is not always first', () {
      final firsts = {
        for (var i = 0; i < 200; i++) _types(ChallengeManager()).first,
      };
      expect(firsts.length, greaterThan(1));
    });

    test('a fresh set on reset still carries the turn', () {
      final manager = ChallengeManager();
      for (var i = 0; i < 50; i++) {
        manager.reset();
        expect(_types(manager), contains(LivenessChallenge.turn));
      }
    });

    test('a pool without a turn still picks, and never repeats', () {
      final pool = kDefaultChallengePool
          .where((c) => c.type != LivenessChallenge.turn)
          .toList();
      final types = _types(ChallengeManager(pool: pool, count: 3));
      expect(types, hasLength(3));
      expect(types.toSet(), hasLength(3));
    });

    test('three prompts: the turn plus two others, still no nod', () {
      for (var i = 0; i < 100; i++) {
        final types = _types(ChallengeManager(count: 3));
        expect(types, contains(LivenessChallenge.turn));
        expect(types, isNot(contains(LivenessChallenge.nod)));
        expect(types.toSet(), hasLength(3));
      }
    });
  });

  group('by liveness mode', () {
    test('gestures and both pick gestures with a turn', () {
      for (final mode in ['gestures', 'both']) {
        expect(_types(ChallengeManager.forMode(mode)), contains(LivenessChallenge.turn));
      }
    });

    test('flash-only asks for no gestures (the flash runs at capture)', () {
      expect(_types(ChallengeManager.forMode('flash')), isEmpty);
    });

    test('Passive Liveness asks only for a hold', () {
      final manager = ChallengeManager.forMode('passive');
      expect(_types(manager), [LivenessChallenge.hold]);
      manager.reset();
      expect(_types(manager), [LivenessChallenge.hold]);
      expect(manager.current!.instruction, 'Hold still and look at the camera');
    });
  });

  group('the claim lists the prompts that ran', () {
    const gestures = [LivenessChallenge.blink, LivenessChallenge.turn];

    test('gestures, in order', () {
      expect(
        livenessClaimChallenges(mode: 'gestures', gestures: gestures),
        ['blink', 'turn'],
      );
    });

    test('Dual Check puts the flash last', () {
      expect(
        livenessClaimChallenges(mode: 'both', gestures: gestures),
        ['blink', 'turn', 'flash'],
      );
    });

    test('3D Flash Check lists only the flash', () {
      expect(livenessClaimChallenges(mode: 'flash', gestures: const []), ['flash']);
    });

    test('a flash-only fallback lists the flash, then the fallback gestures', () {
      expect(
        livenessClaimChallenges(
          mode: 'flash',
          gestures: gestures,
          fellBackToGestures: true,
        ),
        ['flash', 'blink', 'turn'],
      );
    });

    test('Passive Liveness lists the hold', () {
      expect(
        livenessClaimChallenges(
          mode: 'passive',
          gestures: const [LivenessChallenge.hold],
        ),
        ['hold'],
      );
    });
  });
}
