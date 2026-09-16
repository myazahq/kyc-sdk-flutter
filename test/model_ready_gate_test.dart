import 'package:flutter_test/flutter_test.dart';
import 'package:myaza_kyc_sdk_flutter/src/services/model_readiness.dart';

// ─── The one rule both model gates follow ─────────────────────────────────────
//
// A model that is not on the phone looks exactly like an empty frame, so the
// liveness step and the passport scanner wait on this gate before a camera
// opens. These pin how it settles: ready as soon as the native side says so,
// unavailable as soon as Play Services says it cannot deliver, and unavailable
// after the wait when a download simply never lands. Only the first question
// requests the install; every later one only asks.

typedef Ask = Future<NativeModelStatus> Function({required bool install});

Ask scripted(List<NativeModelStatus> answers, List<bool> calls) {
  var i = 0;
  return ({required bool install}) async {
    calls.add(install);
    final answer = answers[i < answers.length ? i : answers.length - 1];
    i++;
    return answer;
  };
}

void main() {
  const tick = Duration(milliseconds: 1);

  test('a model already on the phone settles ready after one question', () async {
    final calls = <bool>[];
    final gate = ModelReadyGate(
      ask: scripted([NativeModelStatus.ready], calls),
      poll: tick,
    );
    await gate.start();
    expect(gate.state.value, ModelReadyState.ready);
    expect(calls, [true]);
    gate.dispose();
  });

  test('a download that lands is noticed, and only the first question installs',
      () async {
    final calls = <bool>[];
    final gate = ModelReadyGate(
      ask: scripted(
        [NativeModelStatus.pending, NativeModelStatus.pending, NativeModelStatus.ready],
        calls,
      ),
      poll: tick,
    );
    await gate.start();
    expect(gate.state.value, ModelReadyState.ready);
    expect(calls, [true, false, false]);
    gate.dispose();
  });

  test('Play Services refusing settles unavailable without waiting out the clock',
      () async {
    final calls = <bool>[];
    final gate = ModelReadyGate(
      ask: scripted([NativeModelStatus.pending, NativeModelStatus.failed], calls),
      poll: tick,
      wait: const Duration(hours: 1),
    );
    await gate.start();
    expect(gate.state.value, ModelReadyState.unavailable);
    expect(calls, [true, false]);
    gate.dispose();
  });

  test('a download that never lands settles unavailable once the wait passes',
      () async {
    final start = DateTime(2026, 9, 13, 12);
    var reads = 0;
    final gate = ModelReadyGate(
      ask: scripted([NativeModelStatus.pending], []),
      poll: tick,
      // The first read is the start; every later one is past the wait.
      now: () => reads++ == 0 ? start : start.add(kModelWait),
    );
    await gate.start();
    expect(gate.state.value, ModelReadyState.unavailable);
    gate.dispose();
  });

  test('a gate that starts ready never asks, so iOS never calls the channel',
      () async {
    final calls = <bool>[];
    final gate = ModelReadyGate(
      ask: scripted([NativeModelStatus.failed], calls),
      initial: ModelReadyState.ready,
    );
    await gate.start();
    expect(gate.state.value, ModelReadyState.ready);
    expect(calls, isEmpty);
    gate.dispose();
  });

  test('disposing stops the questions', () async {
    final calls = <bool>[];
    final gate = ModelReadyGate(
      ask: scripted([NativeModelStatus.pending], calls),
      poll: const Duration(milliseconds: 5),
    );
    final running = gate.start();
    await Future<void>.delayed(const Duration(milliseconds: 12));
    gate.dispose();
    final asked = calls.length;
    await running;
    await Future<void>.delayed(const Duration(milliseconds: 20));
    expect(calls.length, asked);
  });

  test('the native words map to statuses, and anything unknown keeps waiting', () {
    expect(parseModelStatus('ready'), NativeModelStatus.ready);
    expect(parseModelStatus('failed'), NativeModelStatus.failed);
    expect(parseModelStatus('pending'), NativeModelStatus.pending);
    expect(parseModelStatus(null), NativeModelStatus.pending);
  });
}
