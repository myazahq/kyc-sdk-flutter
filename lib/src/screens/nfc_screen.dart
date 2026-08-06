import 'dart:io' show Platform;

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../config/theme.dart';
import '../widgets/nfc_read_progress.dart';
import '../widgets/nfc_read_sheet.dart';
import '../widgets/passport_illustration.dart';
import '../providers/kyc_provider.dart';
import '../services/mrz_parser.dart';
import '../services/nfc_reader.dart';
import '../services/nfc_reader_emrtd.dart';
import '../widgets/myaza_button.dart';
import 'mrz_scan_view.dart';
import '../widgets/nfc_scanned_summary.dart';
import 'nfc_screen_parts.dart';

// ─── NFC chip step ────────────────────────────────────────────────────────────
//
// Reads the document's eMRTD chip.
//
// ICAO 9303 Basic Access Control derives the chip's session key from three MRZ
// fields (document number, date of birth, expiry) — the chip refuses to open
// without them, so they are not optional. Rather than making the user type
// them, we SCAN the printed MRZ off the photo page: camera → on-device text
// recognition → check-digit-validated parse → BAC key. No keyboard in the step.
//
// A misread can't slip through: nothing is accepted until every 7-3-1 check
// digit validates, so a bad frame is discarded and the next one tried.
//
// The MRZ normally comes from the DOCUMENT CAPTURE step, which already
// photographed the page it's printed on — this step only falls back to its own
// scanner when that produced nothing (gallery photo cropped past the MRZ, blurry
// capture). Scanning the same document twice is a step users shouldn't take.
//
// On a device with no NFC radio the step auto-skips. `allowSkip` adds a manual
// skip affordance. The chip read is a SOFT sub-result — skipping never fails
// the verification.

class NfcScreen extends ConsumerStatefulWidget {
  const NfcScreen({super.key});

  @override
  ConsumerState<NfcScreen> createState() => _NfcScreenState();
}

enum _Phase { checking, scanning, reading, success, failed }

class _NfcScreenState extends ConsumerState<NfcScreen> {
  final _reader = createNfcChipReader();

  _Phase _phase = _Phase.checking;
  MrzScan? _scan;
  String? _error;

  /// How far the chip read has got. iOS narrates this in its system sheet;
  /// Android has no system NFC UI, so the SDK draws it — as a modal sheet
  /// (showNfcReadSheet) plus the same step list inline behind it.
  NfcReadStage _stage = NfcReadStage.waiting;

  /// Drives the sheet, which is a route of its own and so does not rebuild with
  /// this widget's setState.
  final _stageNotifier = ValueNotifier<NfcReadStage>(NfcReadStage.waiting);

  /// True while our sheet is on screen, so it is closed exactly once.
  bool _sheetOpen = false;

  @override
  void dispose() {
    _stageNotifier.dispose();
    super.dispose();
  }

  void _setStage(NfcReadStage stage) {
    _stageNotifier.value = stage;
    if (mounted) setState(() => _stage = stage);
  }

  /// Android only: iOS already shows the system NFC sheet, and two sheets would
  /// fight over the screen.
  void _openSheet() {
    if (!Platform.isAndroid || _sheetOpen) return;
    _sheetOpen = true;
    showNfcReadSheet(context, stage: _stageNotifier)
        .whenComplete(() => _sheetOpen = false);
  }

  void _closeSheet() {
    if (!_sheetOpen) return;
    _sheetOpen = false;
    // The sheet may already be gone if the user swiped it away.
    Navigator.of(context, rootNavigator: true).maybePop();
  }

  bool get _allowSkip => ref.read(kycConfigProvider).nfc?.allowSkip ?? false;

  @override
  void initState() {
    super.initState();
    _checkAvailability();
  }

  Future<void> _checkAvailability() async {
    final available = await _reader.isAvailable();
    if (!mounted) return;
    if (!available) {
      // No NFC radio (or disabled) — skip the step entirely.
      ref.read(kYCNotifierProvider.notifier).nextStep();
      return;
    }

    // Document capture already read the MRZ off the photo page, so go straight
    // to the chip — no second scan of the same document.
    final known = ref.read(kYCNotifierProvider).mrzScan;
    if (known != null) {
      await _onScanned(known);
      return;
    }
    setState(() => _phase = _Phase.scanning);
  }

  Future<void> _onScanned(MrzScan scan) async {
    if (!mounted) return;
    setState(() {
      _scan = scan;
      _phase = _Phase.reading;
      _error = null;
      _stage = NfcReadStage.waiting;
    });
    _stageNotifier.value = NfcReadStage.waiting;
    _openSheet();
    try {
      final data = await _reader.read(
        NfcMrzKey(
          documentNumber: scan.documentNumber,
          dateOfBirth: scan.dateOfBirth,
          dateOfExpiry: scan.dateOfExpiry,
        ),
        onStage: _setStage,
      );
      if (!mounted) return;
      _closeSheet();
      ref.read(kYCNotifierProvider.notifier).setNfcChipData(data);
      // Confirm before moving on: the chip read is invisible (no shutter, no
      // preview), so without this the step just vanishes and the user can't
      // tell whether it worked.
      setState(() => _phase = _Phase.success);
    } on NfcReadException catch (e) {
      if (!mounted) return;
      _closeSheet();
      setState(() {
        _phase = _Phase.failed;
        _error = _messageFor(e);
      });
    }
  }

  String _messageFor(NfcReadException e) => switch (e.code) {
        // The MRZ is check-digit validated, so a BAC failure here means the
        // chip didn't match the printed page — not a typo.
        'auth_failed' =>
          "Couldn't unlock the chip with this document's details. Make sure "
              'you scanned the photo page of the same document.',
        'tag_lost' =>
          'The chip moved out of range. Hold the document still against the '
              'back of your phone.',
        _ => "Couldn't read the chip. Please try again.",
      };

  void _skip() => ref.read(kYCNotifierProvider.notifier).nextStep();

  void _rescan() => setState(() {
        _phase = _Phase.scanning;
        _scan = null;
        _error = null;
      });

  @override
  Widget build(BuildContext context) {
    final text = context.myazaText;

    if (_phase == _Phase.checking) {
      return const Padding(
        padding: EdgeInsets.symmetric(vertical: MyazaSpacing.xl),
        child: Center(child: CircularProgressIndicator()),
      );
    }

    final scan = _scan;

    if (_phase == _Phase.success) {
      return Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          NfcSuccessPanel(
            scan: scan,
            dg2Base64: ref.read(kYCNotifierProvider).nfcChipData?.dg2Base64,
            missingSod:
                ref.read(kYCNotifierProvider).nfcChipData?.missingSod ?? false,
            onRetry: _rescan,
          ),
          const SizedBox(height: MyazaSpacing.xl),
          MyazaButton(
            label: 'Continue',
            onPressed: () =>
                ref.read(kYCNotifierProvider.notifier).nextStep(),
          ),
        ],
      );
    }

    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        if (_phase == _Phase.scanning) ...[
          Text(
            'Point your camera at the photo page of your document. We’ll read '
            'the printed code that unlocks its chip.',
            style: text.bodyMedium,
          ),
          const SizedBox(height: MyazaSpacing.md),
          MrzScanView(onScanned: _onScanned),
        ] else ...[
          const PassportIllustration(),
          const SizedBox(height: MyazaSpacing.lg),
          Text(
            _phase == _Phase.reading
                ? (_stage == NfcReadStage.waiting
                    // Nothing has been detected yet — this is an instruction.
                    ? 'Hold the top edge of your document flat against the '
                        'back of your phone and keep still…'
                    // The chip IS connected: the risk now is the user lifting
                    // the document mid-read, so say that it is working.
                    : 'Chip detected — keep the document still until this '
                        'finishes.')
                : 'We read your document’s details — the chip didn’t open.',
            style: text.bodyMedium,
            textAlign: TextAlign.center,
          ),
          if (scan != null) ...[
            const SizedBox(height: MyazaSpacing.md),
            NfcScannedSummary(scan: scan),
          ],
          if (_phase == _Phase.reading) ...[
            const SizedBox(height: MyazaSpacing.lg),
            NfcReadProgress(stage: _stage),
          ],
        ],
        if (_error != null) ...[
          const SizedBox(height: MyazaSpacing.sm),
          Text(_error!,
              style: text.bodySmall.copyWith(color: MyazaColors.error)),
        ],
        if (_phase == _Phase.failed) ...[
          const SizedBox(height: MyazaSpacing.lg),
          MyazaButton(
            label: 'Try the chip again',
            onPressed: scan == null ? null : () => _onScanned(scan),
          ),
          const SizedBox(height: MyazaSpacing.sm),
          Center(
            child: TextButton(
              onPressed: _rescan,
              child: const Text('Scan the document again'),
            ),
          ),
        ],
        if (_allowSkip && _phase != _Phase.reading) ...[
          const SizedBox(height: MyazaSpacing.sm),
          Center(
            child: TextButton(
              onPressed: _skip,
              child: const Text('My device can’t scan the chip — skip'),
            ),
          ),
        ],
      ],
    );
  }
}
