import 'dart:convert';
import '../nfc/dg2_image.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../config/theme.dart';
import '../services/mrz_parser.dart';
import '../widgets/nfc_scanned_summary.dart';
import '../widgets/staggered_reveal.dart';
import '../widgets/check_badge.dart';

// ─── NFC step — presentational parts ──────────────────────────────────────────

/// Confirms the chip actually opened and was read. The read is otherwise
/// invisible — no shutter, no preview — so without an explicit success state
/// the step simply disappears and the user can't tell it worked.
class NfcSuccessPanel extends StatefulWidget {
  final MrzScan? scan;

  /// Base64 DG2 — the chip's own portrait. Shown when this platform can decode
  /// it: the read is otherwise invisible, and the government's photo of the
  /// holder appearing on screen is the plainest possible evidence it worked.
  final String? dg2Base64;

  /// True when the chip opened but its signed security object didn't come
  /// back — the read succeeded, but authenticity can't be established from it.
  final bool missingSod;

  final VoidCallback? onRetry;

  const NfcSuccessPanel({
    super.key,
    this.scan,
    this.dg2Base64,
    this.missingSod = false,
    this.onRetry,
  });

  @override
  State<NfcSuccessPanel> createState() => _NfcSuccessPanelState();
}

class _NfcSuccessPanelState extends State<NfcSuccessPanel> {
  Uint8List? _portrait;

  @override
  void initState() {
    super.initState();
    _loadPortrait();
    // A chip read has no shutter, no sound, nothing physical — the haptic is
    // what makes it land as a completed action. Fire-and-forget: hardware
    // without a taptic engine simply does nothing.
    WidgetsBinding.instance.addPostFrameCallback((_) {
      HapticFeedback.mediumImpact();
    });
  }

  /// Best-effort: most chips store the portrait as JPEG 2000, which iOS decodes
  /// and Android does not. No preview is never an error — the read stands on
  /// its own, and the panel simply shows one less thing.
  Future<void> _loadPortrait() async {
    final encoded = widget.dg2Base64;
    if (encoded == null) return;
    try {
      final bytes = await decodeDg2Portrait(base64.decode(encoded));
      if (mounted && bytes != null) setState(() => _portrait = bytes);
    } catch (_) {
      // Malformed DG2 — the chip data is still submitted and checked server-side.
    }
  }

  @override
  Widget build(BuildContext context) {
    final colors = context.myazaColors;
    final text = context.myazaText;
    final scan = widget.scan;
    final name = scan?.displayName ?? '';

    // Lead-in above the badge, matching the submission screen's `xl`. Padding
    // rather than a leading child: a spacer inside StaggeredReveal would take a
    // stagger slot and delay everything below it by one step for no motion.
    return Padding(
      padding: const EdgeInsets.only(top: MyazaSpacing.xl),
      child: StaggeredReveal(
        children: [
          // The SAME mark the submission screen ends on — one success signal
          // across the flow, not a bespoke one per step.
          // The chip's own photo when we have it, the generic mark when we
          // don't. Seeing the issuing government's portrait of the holder is a
          // far stronger confirmation than a tick.
          Center(
            child: _portrait == null
                ? const CheckBadge(size: 88)
                : _ChipPortrait(bytes: _portrait!),
          ),
          const SizedBox(height: MyazaSpacing.lg),
          Text(
            'Chip read successfully',
            style: text.heading2,
            textAlign: TextAlign.center,
          ),
          const SizedBox(height: MyazaSpacing.xs),
          Text(
            name.isEmpty
                ? 'The secure chip in your document was read and verified.'
                : 'We read the secure chip in $name\u2019s document.',
            style: text.bodyMedium.copyWith(color: colors.textSecondary),
            textAlign: TextAlign.center,
          ),
          if (scan != null) ...[
            const SizedBox(height: MyazaSpacing.lg),
            NfcScannedSummary(scan: scan),
          ],
          if (widget.missingSod) ...[
            const SizedBox(height: MyazaSpacing.md),
            _MissingSodNotice(onRetry: widget.onRetry),
          ],
        ],
      ),
    );
  }
}

/// The portrait read off the chip, with the success mark tucked into its
/// corner so the panel still carries the same completion signal as every other
/// step.
class _ChipPortrait extends StatelessWidget {
  final Uint8List bytes;

  const _ChipPortrait({required this.bytes});

  @override
  Widget build(BuildContext context) {
    final colors = context.myazaColors;
    // Circular, to match the selfie the liveness step captures and the avatar
    // shape used elsewhere in the flow — a portrait in a rectangle reads as a
    // document scan, which this isn't. BoxFit.cover centre-crops the chip's
    // 3:4 image, which lands on the face.
    const size = 132.0;
    return SizedBox(
      width: size,
      height: size,
      child: Stack(
        clipBehavior: Clip.none,
        children: [
          Positioned.fill(
            child: DecoratedBox(
              decoration: BoxDecoration(
                shape: BoxShape.circle,
                border: Border.all(color: colors.border, width: 2),
              ),
              child: ClipOval(
                child: Image.memory(
                  bytes,
                  fit: BoxFit.cover,
                  width: size,
                  height: size,
                ),
              ),
            ),
          ),
          // Tucked onto the circle's lower-right edge rather than outside the
          // box, so the mark reads as attached to the portrait.
          const Positioned(
            right: 0,
            bottom: 2,
            child: CheckBadge(size: 38),
          ),
        ],
      ),
    );
  }
}

/// Shown when the chip opened but its certificate didn't arrive — the read is
/// real, the authenticity claim isn't.
class _MissingSodNotice extends StatelessWidget {
  final VoidCallback? onRetry;

  const _MissingSodNotice({this.onRetry});

  @override
  Widget build(BuildContext context) {
    final colors = context.myazaColors;
    final text = context.myazaText;

    return Container(
      padding: const EdgeInsets.all(MyazaSpacing.md),
      decoration: BoxDecoration(
        color: MyazaColors.warning.withValues(alpha: 0.12),
        borderRadius: BorderRadius.circular(MyazaRadius.md),
        border: Border.all(color: MyazaColors.warning.withValues(alpha: 0.35)),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            'We read your details, but not the chip\u2019s security '
            'certificate \u2014 so we can\u2019t confirm the chip is genuine.',
            style: text.bodySmall,
          ),
          if (onRetry != null) ...[
            const SizedBox(height: MyazaSpacing.sm),
            GestureDetector(
              onTap: onRetry,
              child: Text(
                'Scan again, holding the document still for longer',
                style: text.bodySmall.copyWith(
                  color: colors.primary,
                  fontWeight: FontWeight.w600,
                ),
              ),
            ),
          ],
        ],
      ),
    );
  }
}
