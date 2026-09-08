import 'dart:async';

// ─── Waiting for the selfie upload from a later step ────────────────────────
//
// With the selfie review hidden (the biometric scopes' default), the liveness
// step hands over the moment the capture ring has closed rather than when the
// upload lands, so the person sees ONE loading screen from the shutter to the
// verdict instead of three. The upload keeps running in the background and
// reports to the provider (`KYCState.selfieUpload`, written by the liveness
// screen); the submitted screen waits on that record before it submits. Pure
// and injectable, like the result wait: the screen owns nothing but the
// rendering. Mirrors the web and RN SDKs' selfie-upload-wait; keep in lockstep.

enum SelfieUploadStatus { idle, uploading, done, failed }

class SelfieUploadState {
  final SelfieUploadStatus status;

  /// The failure message, set only on `failed`.
  final String? message;

  const SelfieUploadState({required this.status, this.message});

  static const SelfieUploadState idle = SelfieUploadState(status: SelfieUploadStatus.idle);
  static const SelfieUploadState uploading = SelfieUploadState(status: SelfieUploadStatus.uploading);
  static const SelfieUploadState done = SelfieUploadState(status: SelfieUploadStatus.done);
  static SelfieUploadState failed(String message) =>
      SelfieUploadState(status: SelfieUploadStatus.failed, message: message);
}

const SelfieUploadState kIdleSelfieUpload = SelfieUploadState.idle;

sealed class SelfieUploadWait {
  const SelfieUploadWait();
}

class SelfieUploadOk extends SelfieUploadWait {
  const SelfieUploadOk();
}

class SelfieUploadFailed extends SelfieUploadWait {
  final String message;
  const SelfieUploadFailed(this.message);
}

class SelfieUploadSnapshot {
  final SelfieUploadState selfieUpload;

  /// `mediaIds.selfie`: the durable proof the selfie is on the server.
  final String? selfieMediaId;
  const SelfieUploadSnapshot({required this.selfieUpload, this.selfieMediaId});
}

const Duration kSelfieUploadWait = Duration(seconds: 90);

const String kSelfieUploadTimedOut =
    'Your selfie could not be sent. Check your connection and try again.';

/// Whether the upload has settled, and how. A restored session carries the
/// media id with the status still `idle` (nothing uploaded this visit), which
/// counts as settled; an `idle` record with no media id is an upload that has
/// not started yet, so the caller keeps waiting.
SelfieUploadWait? selfieUploadSettled(SelfieUploadSnapshot snapshot) {
  final status = snapshot.selfieUpload.status;
  if (status == SelfieUploadStatus.failed) {
    return SelfieUploadFailed(snapshot.selfieUpload.message ?? kSelfieUploadTimedOut);
  }
  final restored = status == SelfieUploadStatus.idle && snapshot.selfieMediaId != null;
  if (status == SelfieUploadStatus.done || restored) return const SelfieUploadOk();
  return null;
}

/// Resolve once the upload has settled, or with a failure at the deadline.
/// [subscribe] fires the listener on every store change and returns the
/// unsubscribe.
Future<SelfieUploadWait> awaitSelfieUpload({
  required SelfieUploadSnapshot Function() read,
  required void Function() Function(void Function() listener) subscribe,
  Duration timeout = kSelfieUploadWait,
}) {
  final settled = selfieUploadSettled(read());
  if (settled != null) return Future.value(settled);
  final completer = Completer<SelfieUploadWait>();
  late final void Function() unsubscribe;
  late final Timer timer;
  void finish(SelfieUploadWait result) {
    if (completer.isCompleted) return;
    unsubscribe();
    timer.cancel();
    completer.complete(result);
  }

  unsubscribe = subscribe(() {
    final next = selfieUploadSettled(read());
    if (next != null) finish(next);
  });
  timer = Timer(timeout, () => finish(const SelfieUploadFailed(kSelfieUploadTimedOut)));
  // The store may have moved between the first read and the subscription.
  final again = selfieUploadSettled(read());
  if (again != null) finish(again);
  return completer.future;
}
