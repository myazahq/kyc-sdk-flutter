import 'package:camera/camera.dart';
import 'package:flutter/material.dart';
import 'package:lucide_icons_flutter/lucide_icons.dart';

import '../config/capture_hints.dart';
import '../config/theme.dart';
import '../config/id_types.dart' show IdTypeConfig;
import '../services/document_framing_gate.dart';
import 'document_ghost.dart';
import 'document_info_pill.dart';
import 'document_plugin_preview.dart';
import 'document_scan_overlay.dart';
import 'native_camera_preview.dart';

/// Keys for the two controls whose overlap is a real (and once-shipped) bug:
/// the hint sat behind the shutter. Layout tests target these.
const kDocumentHintKey = ValueKey('kyc.document.hint');
const kDocumentShutterKey = ValueKey('kyc.document.shutter');
const kDocumentTorchKey = ValueKey('kyc.document.torch');

/// Width of the slots either side of the shutter. Equal on both sides so the
/// shutter stays centred on the screen, not merely centred in what's left.
const double _kSideSlot = 72;

/// The document camera viewfinder: live feed + guide overlay + shutter.
///
/// The feed comes from one of two sources, in order:
///   * [nativeTextureId] — Android's native CameraX camera (the normal path
///     there). Upright from the first frame, nothing to cover.
///   * [controller] — the Flutter camera plugin (iOS, and Android's fallback),
///     rendered through [DocumentPluginPreview] with its rotation workarounds.
class DocumentViewfinder extends StatelessWidget {
  /// Flutter camera-plugin controller — iOS, or the Android fallback.
  final CameraController? controller;

  /// Android native camera texture + its buffer size (null off that path).
  final int? nativeTextureId;
  final int nativePreviewW;
  final int nativePreviewH;

  final bool isLoading;
  final String? error;
  final bool isBack;
  final bool isProcessing;
  final double guideAspect;
  final VoidCallback? onCapture;

  /// Torch controls. Null [onToggleTorch] hides the button (no flash unit).
  final bool torchOn;
  final VoidCallback? onToggleTorch;

  /// Auto-capture framing state + dwell progress, driving the scan overlay.
  final DocumentFraming framing;
  final double scanProgress;

  /// Live instruction for the user, and the document's own name to put in it.
  final DocumentHint hint;
  final String hintLabel;

  /// The document being captured, and where it is from — shown in-frame,
  /// because full-screen took away the header that used to say so.
  final IdTypeConfig? idType;
  final String? country;

  /// Draw the machine-readable band in the layout ghost (passport pages have
  /// one, and auto-capture requires it in frame).
  final bool showMrzBand;

  /// Stands in for the sheet's back control, which the full-screen camera
  /// hides.
  final VoidCallback? onBack;

  /// "Upload a photo instead" — the escape hatch, which must survive losing the
  /// chrome that used to host it.
  final VoidCallback? onUpload;

  const DocumentViewfinder({
    super.key,
    required this.controller,
    required this.isLoading,
    required this.error,
    required this.isBack,
    required this.isProcessing,
    required this.guideAspect,
    required this.onCapture,
    this.torchOn = false,
    this.onToggleTorch,
    this.nativeTextureId,
    this.nativePreviewW = 0,
    this.nativePreviewH = 0,
    this.framing = DocumentFraming.none,
    this.scanProgress = 0,
    this.hint = DocumentHint.searching,
    this.hintLabel = 'document',
    this.idType,
    this.country,
    this.showMrzBand = false,
    this.onBack,
    this.onUpload,
  });

  @override
  Widget build(BuildContext context) {
    // The feed runs under the system bars on purpose, so the controls are
    // inset by the real intrusions — read from the VIEW, not from MediaQuery.
    //
    // The flow is presented with showModalBottomSheet(useSafeArea: false),
    // which Flutter wraps in MediaQuery.removePadding(removeTop: true). That
    // zeroes `padding.top` AND reduces `viewPadding.top` by the same amount
    // (viewPadding.top - padding.top), so BOTH read zero here and the back
    // button and side badge end up underneath the status bar. Going to the
    // view gives the physical inset whatever any ancestor has done to the
    // inherited MediaQuery — which is what a full-bleed overlay actually needs.
    final insets = MediaQueryData.fromView(View.of(context)).viewPadding;
    final topInset = insets.top + 8;
    final bottomInset = insets.bottom + 12;

    final stack = Stack(
          fit: StackFit.expand,
          children: [
            _buildFeed(),

            // Layout ghost — where the portrait, the details and (on a
            // passport) the MRZ band belong. Shown for a few seconds when the
            // camera opens, then out of the way.
            Positioned.fill(
              child: DocumentGhost(
                aspect: guideAspect,
                showMrzBand: showMrzBand,
                documentFound: framing != DocumentFraming.none &&
                    framing != DocumentFraming.wrongShape,
              ),
            ),

            // The ONLY guide. It draws the scrim, outline, corners and all the
            // auto-capture feedback from one rect (config/document_guide.dart),
            // which the post-shutter crop shares. An earlier second painter drew
            // its own geometry — two misaligned rectangles, and the user aimed
            // at the wrong one.
            Positioned.fill(
              child: DocumentScanOverlay(
                framing: framing,
                progress: scanProgress,
                aspect: guideAspect,
              ),
            ),

            Positioned(
              top: topInset,
              right: 10,
              child: _SideBadge(isBack: isBack),
            ),

            // Back — the sheet's own control is gone in fill mode, and a camera
            // with no way out is a trap.
            if (onBack != null)
              Positioned(
                top: topInset,
                left: 10,
                child: _CircleButton(
                  icon: LucideIcons.arrowLeft,
                  onTap: onBack!,
                ),
              ),

            // Below the top row rather than in it: the back button and the
            // side badge hold both corners, and this needs the full width.
            if (idType != null)
              Positioned(
                top: topInset + 46,
                left: MyazaSpacing.lg,
                right: MyazaSpacing.lg,
                child: Center(
                  child: DocumentInfoPill(idType: idType!, country: country),
                ),
              ),

            // Everything along the bottom edge lives in ONE column: hint, then
            // the upload link, then the shutter row. The hint used to be
            // positioned separately at a fixed offset above the shutter, which
            // worked until the upload link joined the cluster and made it
            // taller — the hint then sat behind the button. Stacking them means
            // the layout cannot disagree with itself whatever is or isn't shown.
            Positioned(
              left: 0,
              right: 0,
              bottom: bottomInset,
              child: Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  // Live instruction from the framing gate — which way to move,
                  // whether it is the wrong document, or to add light.
                  Padding(
                    key: kDocumentHintKey,
                    // Side padding so a long hint ("Include the code strip
                    // along the bottom of the page") wraps inside the screen
                    // instead of running to the edges.
                    padding: const EdgeInsets.fromLTRB(
                        MyazaSpacing.lg, 0, MyazaSpacing.lg, MyazaSpacing.md),
                    child: Container(
                      padding: const EdgeInsets.symmetric(
                          horizontal: 12, vertical: 5),
                      decoration: BoxDecoration(
                        color: Colors.black.withValues(alpha: 0.55),
                        borderRadius: BorderRadius.circular(MyazaRadius.full),
                      ),
                      child: Text(
                        documentHintText(hint, label: hintLabel),
                        textAlign: TextAlign.center,
                        style: TextStyle(
                          color: Colors.white,
                          fontSize: 13,
                          fontWeight: documentHintIsAction(hint)
                              ? FontWeight.w700
                              : FontWeight.w500,
                        ),
                      ),
                    ),
                  ),
                  // Secondary action ABOVE the primary one, so the shutter
                  // stays the lowest thing on screen — where the thumb rests
                  // and where every camera app puts it. Kept in frame at all
                  // because losing the chrome would otherwise lose the only
                  // route out for a document the camera can't read.
                  if (onUpload != null && !isProcessing) ...[
                    TextButton.icon(
                      onPressed: onUpload,
                      icon: const Icon(LucideIcons.upload,
                          size: 15, color: Colors.white),
                      label: const Text(
                        'Upload a photo instead',
                        style: TextStyle(
                          color: Colors.white,
                          fontSize: 13,
                          fontWeight: FontWeight.w600,
                        ),
                      ),
                    ),
                    const SizedBox(height: MyazaSpacing.sm),
                  ],
                  // Shutter row: the torch sits beside the shutter rather than
                  // up in the corner — it is a capture control, and this is
                  // where the thumb already is. The fixed-width slots either
                  // side keep the shutter centred whether or not the device
                  // has a flash unit to show.
                  Row(
                    children: [
                      const SizedBox(width: _kSideSlot),
                      Expanded(
                        child: Center(
                          child: isProcessing
                              ? const _ProcessingPill()
                              : _ShutterButton(
                                  key: kDocumentShutterKey,
                                  onCapture: onCapture,
                                ),
                        ),
                      ),
                      SizedBox(
                        width: _kSideSlot,
                        child: onToggleTorch == null
                            ? null
                            : Center(
                                child: _TorchButton(
                                  key: kDocumentTorchKey,
                                  on: torchOn,
                                  onTap: onToggleTorch!,
                                ),
                              ),
                      ),
                    ],
                  ),
                ],
              ),
            ),
          ],
        );

    // Fill whatever room there is — but survive being handed none.
    //
    // The camera normally owns the whole screen, so expanding is right. On the
    // frames before the immersive flag flips, though, the step is still inside
    // the sheet's scroll view, which offers INFINITE height; SizedBox.expand
    // asserts there and the whole subtree fails to lay out. A camera preview is
    // not worth crashing a screen over, so an unbounded parent gets a sensible
    // height instead of an exception.
    return LayoutBuilder(
      builder: (context, constraints) {
        if (constraints.hasBoundedHeight) return SizedBox.expand(child: stack);
        final fallback = MediaQuery.sizeOf(context).height;
        return SizedBox(
          width: constraints.hasBoundedWidth ? constraints.maxWidth : null,
          height: fallback,
          child: stack,
        );
      },
    );
  }

  Widget _buildFeed() {
    final textureId = nativeTextureId;
    if (textureId != null) {
      return NativeCameraPreview(
        textureId: textureId,
        bufferWidth: nativePreviewW,
        bufferHeight: nativePreviewH,
      );
    }
    final ctrl = controller;
    if (ctrl != null && ctrl.value.isInitialized) {
      return DocumentPluginPreview(ctrl, isCapturing: isProcessing);
    }
    return _ViewfinderPlaceholder(isLoading: isLoading, error: error);
  }
}

class _ViewfinderPlaceholder extends StatelessWidget {
  final bool isLoading;
  final String? error;

  const _ViewfinderPlaceholder({required this.isLoading, this.error});

  @override
  Widget build(BuildContext context) {
    return Container(
      color: const Color(0xFF111111),
      child: Center(
        child: error != null
            ? Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  const Icon(LucideIcons.videoOff,
                      color: Colors.white54, size: 36),
                  const SizedBox(height: MyazaSpacing.sm),
                  Text('Camera unavailable',
                      style: context.myazaText.bodySmall
                          .copyWith(color: Colors.white70)),
                ],
              )
            : CircularProgressIndicator(
                color: context.myazaColors.primary, strokeWidth: 2),
      ),
    );
  }
}

class _SideBadge extends StatelessWidget {
  final bool isBack;

  const _SideBadge({required this.isBack});

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
      decoration: BoxDecoration(
        color: isBack ? MyazaColors.success : context.myazaColors.primary,
        borderRadius: BorderRadius.circular(MyazaRadius.full),
      ),
      child: Text(
        isBack ? 'BACK' : 'FRONT',
        style: const TextStyle(
          color: Colors.white,
          fontSize: 11,
          fontWeight: FontWeight.w700,
          letterSpacing: 0.8,
        ),
      ),
    );
  }
}

class _ShutterButton extends StatelessWidget {
  final VoidCallback? onCapture;

  const _ShutterButton({super.key, required this.onCapture});

  @override
  Widget build(BuildContext context) {
    final colors = context.myazaColors;
    final isEnabled = onCapture != null;
    // The classic shutter: a ring with a disc inside it. No glyph — a camera
    // icon inside a camera is telling the user what they can already see, and
    // this is the shape every phone camera has trained them on, so it reads as
    // "take the photo" without being read at all.
    return GestureDetector(
      onTap: onCapture,
      child: AnimatedContainer(
        duration: const Duration(milliseconds: 150),
        width: 68,
        height: 68,
        decoration: BoxDecoration(
          shape: BoxShape.circle,
          border: Border.all(
            color: isEnabled ? Colors.white : Colors.white38,
            width: 3.5,
          ),
          boxShadow: isEnabled
              ? [
                  // Lifts the ring off a bright document, where a plain white
                  // outline would disappear.
                  BoxShadow(
                    color: Colors.black.withValues(alpha: 0.35),
                    blurRadius: 10,
                  ),
                ]
              : null,
        ),
        child: Padding(
          padding: const EdgeInsets.all(4),
          child: DecoratedBox(
            decoration: BoxDecoration(
              shape: BoxShape.circle,
              color: isEnabled ? colors.primary : colors.gray400,
            ),
            // A scan glyph rather than a camera one: this shutter reads a
            // document, and the corner-bracket shape echoes the guide the user
            // is lining the document up inside.
            child: Icon(
              LucideIcons.scanLine,
              size: 24,
              color: isEnabled ? Colors.white : Colors.white54,
            ),
          ),
        ),
      ),
    );
  }
}

class _ProcessingPill extends StatelessWidget {
  const _ProcessingPill();

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
      decoration: BoxDecoration(
        color: Colors.black.withValues(alpha: 0.6),
        borderRadius: BorderRadius.circular(MyazaRadius.full),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          const SizedBox(
            width: 14,
            height: 14,
            child: CircularProgressIndicator(color: Colors.white, strokeWidth: 2),
          ),
          const SizedBox(width: 8),
          Text(
            'Capturing…',
            style: context.myazaText.bodySmall.copyWith(color: Colors.white),
          ),
        ],
      ),
    );
  }
}

class _TorchButton extends StatelessWidget {
  final bool on;
  final VoidCallback onTap;

  const _TorchButton({super.key, required this.on, required this.onTap});

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      onTap: onTap,
      child: Container(
        width: 36,
        height: 36,
        decoration: BoxDecoration(
          shape: BoxShape.circle,
          color: on ? Colors.white : Colors.black.withValues(alpha: 0.45),
        ),
        child: Icon(
          on ? LucideIcons.zap : LucideIcons.zapOff,
          size: 18,
          color: on ? context.myazaColors.primary : Colors.white,
        ),
      ),
    );
  }
}

/// A round translucent control for the in-frame top row (back, and anything
/// else the hidden chrome used to carry).
class _CircleButton extends StatelessWidget {
  final IconData icon;
  final VoidCallback onTap;

  const _CircleButton({required this.icon, required this.onTap});

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      onTap: onTap,
      child: Container(
        width: 36,
        height: 36,
        decoration: BoxDecoration(
          shape: BoxShape.circle,
          color: Colors.black.withValues(alpha: 0.45),
        ),
        child: Icon(icon, size: 18, color: Colors.white),
      ),
    );
  }
}
