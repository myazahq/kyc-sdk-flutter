import 'dart:async';
import 'dart:io' show Platform;

import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart';

// ─── Whether the on-device models can run ─────────────────────────────────────
//
// On Android the SDK fetches its two ML Kit models through Google Play Services
// instead of shipping them in the APK (android/build.gradle). That keeps about
// 18.5 MB per device out of every host app, and it opens a window where a model
// is not on the phone yet: a fresh install, a slow connection, or a phone with
// no Play Services at all.
//
// Nothing a detector returns can reveal that window. A face detector with no
// model finds no face, exactly as it does looking at a wall, and a text
// recogniser with no model finds no lines, exactly as it does on a blank page.
// Without an explicit question the liveness step would say "position your face"
// forever and the passport scanner would never read. So each screen that needs
// a model asks first, through this file.
//
// iOS answers ready without asking: Apple Vision ships with the OS.

/// What a screen should show about a model.
enum ModelReadyState { ready, preparing, unavailable }

/// The two models the SDK runs on the device.
enum OnDeviceModel { face, text }

/// What the native side reports (MlKitModelReadiness.kt).
enum NativeModelStatus { ready, pending, failed }

/// How long a screen waits for a download before saying it cannot run. A slow
/// connection is the common case, and the text model is about 10 MB, so this is
/// deliberately generous. Play Services reports a real failure much sooner.
const Duration kModelWait = Duration(seconds: 60);

/// How often a waiting screen asks again.
const Duration kModelPoll = Duration(milliseconds: 500);

const MethodChannel _faceChannel = MethodChannel('kyc_sdk_flutter/face_detection');
const MethodChannel _textChannel = MethodChannel('kyc_sdk_flutter/text_recognition');

NativeModelStatus parseModelStatus(Object? raw) => switch (raw) {
      'ready' => NativeModelStatus.ready,
      'failed' => NativeModelStatus.failed,
      _ => NativeModelStatus.pending,
    };

/// Asks the native side about [model]. With [install], also requests the model
/// when it is absent.
Future<NativeModelStatus> askModelStatus(
  OnDeviceModel model, {
  required bool install,
}) async {
  if (!Platform.isAndroid) return NativeModelStatus.ready;
  final channel = model == OnDeviceModel.face ? _faceChannel : _textChannel;
  final method = switch (model) {
    OnDeviceModel.face => install ? 'prepareFaceModel' : 'faceModelStatus',
    OnDeviceModel.text => install ? 'prepareTextModel' : 'textModelStatus',
  };
  try {
    return parseModelStatus(await channel.invokeMethod<String>(method));
  } on MissingPluginException {
    // A native side without the readiness contract predates fetched models, so
    // it bundles them: behave exactly as it always did.
    return NativeModelStatus.ready;
  } on PlatformException {
    return NativeModelStatus.failed;
  }
}

/// Starts fetching the face model if the phone does not have it. Called when
/// the flow opens, so the download overlaps the first screens.
void primeFaceModel() =>
    unawaited(askModelStatus(OnDeviceModel.face, install: true));

/// Starts fetching the text model if the phone does not have it. The text model
/// is the larger of the two and is needed earlier in the flow.
void primeTextModel() =>
    unawaited(askModelStatus(OnDeviceModel.text, install: true));

/// Whether the face model can run right now.
Future<bool> isFaceModelReady() async =>
    await askModelStatus(OnDeviceModel.face, install: false) ==
    NativeModelStatus.ready;

/// Whether the text model can run right now.
Future<bool> isTextModelReady() async =>
    await askModelStatus(OnDeviceModel.text, install: false) ==
    NativeModelStatus.ready;

/// Follows one model until it can run, cannot, or the screen goes away.
///
/// The one rule both screens share, so the face and text gates cannot drift.
/// [ask] and [now] are injectable for tests.
class ModelReadyGate {
  ModelReadyGate({
    required Future<NativeModelStatus> Function({required bool install}) ask,
    ModelReadyState initial = ModelReadyState.preparing,
    this.wait = kModelWait,
    this.poll = kModelPoll,
    DateTime Function()? now,
  })  : _ask = ask,
        _now = now ?? DateTime.now,
        _state = ValueNotifier<ModelReadyState>(initial);

  /// The gate for one of the SDK's models. Starts ready off Android, so iOS
  /// never paints a single frame of "getting ready".
  factory ModelReadyGate.forModel(OnDeviceModel model) => ModelReadyGate(
        ask: ({required bool install}) =>
            askModelStatus(model, install: install),
        initial: Platform.isAndroid
            ? ModelReadyState.preparing
            : ModelReadyState.ready,
      );

  final Future<NativeModelStatus> Function({required bool install}) _ask;
  final DateTime Function() _now;
  final ValueNotifier<ModelReadyState> _state;
  final Duration wait;
  final Duration poll;

  bool _started = false;
  bool _disposed = false;

  ValueListenable<ModelReadyState> get state => _state;

  /// Requests the model, then asks again until it settles. Safe to call more
  /// than once; only the first call does anything.
  Future<void> start() async {
    if (_started || _disposed) return;
    _started = true;
    if (_state.value == ModelReadyState.ready) return;

    final startedAt = _now();
    var status = await _ask(install: true);
    while (!_disposed) {
      switch (status) {
        case NativeModelStatus.ready:
          return _set(ModelReadyState.ready);
        case NativeModelStatus.failed:
          return _set(ModelReadyState.unavailable);
        case NativeModelStatus.pending:
          if (_now().difference(startedAt) >= wait) {
            return _set(ModelReadyState.unavailable);
          }
      }
      await Future<void>.delayed(poll);
      if (_disposed) return;
      status = await _ask(install: false);
    }
  }

  void _set(ModelReadyState next) {
    if (!_disposed) _state.value = next;
  }

  void dispose() {
    _disposed = true;
    _state.dispose();
  }
}
