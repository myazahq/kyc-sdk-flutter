import 'dart:async';

import 'package:camera/camera.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../config/theme.dart';
import '../providers/camera_provider.dart';
import '../services/model_readiness.dart';
import '../services/mrz_extract.dart';
import '../services/mrz_parser.dart';
import '../services/text_recognition.dart';
import 'mrz_scan_overlay.dart';

// ─── MRZ scan view ────────────────────────────────────────────────────────────
//
// Camera view that reads the Machine Readable Zone off a document's photo page
// and hands back the parsed result. This is what replaces typing the chip's BAC
// key: the same three values (document number, date of birth, expiry) come off
// the printed MRZ instead of the keyboard.
//
// Frames are recognized one at a time and dropped while a recognition is in
// flight — OCR is much slower than the camera, so queueing would just add lag.
// A frame that doesn't yield a check-digit-valid MRZ is silently discarded and
// the next one tried, which is what makes continuous scanning feel instant
// while still refusing a misread.
//
// On Android the text model is fetched rather than bundled, and a recogniser
// with no model finds no lines, exactly as it does on a blank page. So the
// camera waits for the model (model_readiness.dart). This is the one place a
// missing model is a dead end, because the printed strip IS the chip key.

class MrzScanView extends ConsumerStatefulWidget {
  final ValueChanged<MrzScan> onScanned;

  const MrzScanView({super.key, required this.onScanned});

  @override
  ConsumerState<MrzScanView> createState() => _MrzScanViewState();
}

class _MrzScanViewState extends ConsumerState<MrzScanView> {
  final _recognizer = TextRecognitionService();
  final ModelReadyGate _textModel = ModelReadyGate.forModel(OnDeviceModel.text);

  /// Captured while mounted: `ref` is unusable inside dispose(), but the
  /// notifier outlives this widget and the stream MUST be stopped there or the
  /// next step inherits a running camera.
  CameraNotifier? _camera;

  bool _cameraStarted = false;
  bool _done = false;
  DateTime _lastAttempt = DateTime.fromMillisecondsSinceEpoch(0);

  // MRZ glyphs are small; 720p is the floor for a reliable read, and going
  // higher would make each frame too large to marshal over the channel.
  static const _resolution = ResolutionPreset.high;

  // Recognition costs ~100–200ms; anything faster just burns battery.
  static const _interval = Duration(milliseconds: 350);

  @override
  void initState() {
    super.initState();
    _textModel.state.addListener(_onTextModelChanged);
    unawaited(_textModel.start());
    WidgetsBinding.instance.addPostFrameCallback((_) => _start());
  }

  void _onTextModelChanged() {
    if (!mounted) return;
    setState(() {});
    if (_textModel.state.value == ModelReadyState.ready) _start();
  }

  Future<void> _start() async {
    if (!mounted || _cameraStarted) return;
    if (_textModel.state.value != ModelReadyState.ready) return;
    _cameraStarted = true;
    final camera = ref.read(cameraNotifierProvider.notifier);
    _camera = camera;
    await camera.initialize(
      direction: CameraLensDirection.back,
      resolution: _resolution,
    );
    if (!mounted) return;
    await camera.startStream(_onFrame);
  }

  void _onFrame(CameraImage image) {
    // Frames can still arrive after teardown — the stream stops asynchronously.
    if (!mounted || _done || _recognizer.isBusy) return;
    final now = DateTime.now();
    if (now.difference(_lastAttempt) < _interval) return;
    _lastAttempt = now;
    _scan(image);
  }

  Future<void> _scan(CameraImage image) async {
    final orientation = _camera?.controller?.description.sensorOrientation ?? 0;

    final lines = await _recognizer.recognize(
      image,
      sensorOrientation: orientation,
    );
    if (!mounted || _done || lines.isEmpty) return;

    final scan = extractMrz(lines);
    if (scan == null) return; // misread or partial — keep looking

    _done = true;
    await _camera?.stopStream();
    if (!mounted) return;
    widget.onScanned(scan);
  }

  @override
  void dispose() {
    _textModel.state.removeListener(_onTextModelChanged);
    _textModel.dispose();
    // Fire-and-forget on the CAPTURED notifier — `ref` is already invalid here.
    _camera?.stopStream();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final text = context.myazaText;
    // Watched FIRST, before the model gate can return early. The camera
    // provider is auto-disposed: while the text model was still preparing,
    // nothing here watched it, so the instance _start() read and initialised
    // was thrown away and the one watched later stayed `uninitialized`. The
    // camera streamed behind a spinner that never cleared (Android,
    // 2026-09-15).
    final camera = ref.watch(cameraNotifierProvider);

    // Worded like the camera-denied case, and for the same reason: the chip is
    // optional, so the honest thing is to say the code cannot be read and let
    // the user carry on rather than wait on something that will not arrive.
    switch (_textModel.state.value) {
      case ModelReadyState.unavailable:
        return _message(
          text,
          'The text reader could not be set up on this device, so the printed '
          'code cannot be read. You can still continue without the chip.',
        );
      case ModelReadyState.preparing:
        return _message(
          text,
          'Getting the text reader ready. This only happens once.',
          busy: true,
        );
      case ModelReadyState.ready:
        break;
    }

    final controller = ref.read(cameraNotifierProvider.notifier).controller;

    if (camera.status == CameraStatus.error ||
        camera.status == CameraStatus.permissionDenied) {
      return Padding(
        padding: const EdgeInsets.symmetric(vertical: MyazaSpacing.xl),
        child: Text(
          camera.error ?? 'Camera unavailable.',
          style: text.bodyMedium.copyWith(color: MyazaColors.error),
          textAlign: TextAlign.center,
        ),
      );
    }

    if (!camera.isReady || controller == null) {
      return const Padding(
        padding: EdgeInsets.symmetric(vertical: MyazaSpacing.xl),
        child: Center(child: CircularProgressIndicator()),
      );
    }

    return MrzScanOverlay(controller: controller);
  }

  Widget _message(MyazaThemeText text, String message, {bool busy = false}) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: MyazaSpacing.xl),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          if (busy) ...[
            const Center(child: CircularProgressIndicator()),
            const SizedBox(height: MyazaSpacing.md),
          ],
          Text(message, style: text.bodyMedium, textAlign: TextAlign.center),
        ],
      ),
    );
  }
}
