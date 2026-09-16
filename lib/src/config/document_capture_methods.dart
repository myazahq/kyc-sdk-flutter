import 'package:flutter/foundation.dart' show immutable;

import 'kyc_config.dart';

// ─── How a document may be captured ───────────────────────────────────────────
//
// Two workflow switches decide it: `allowDocumentScan` (the live camera with
// auto-capture) and `allowDocumentUpload` (a photo picked from the device).
// Both default to on. At least one must stay on: the server refuses to publish
// a workflow with both off, but a stored snapshot or a prop-configured mount
// can still carry that pair, and a document step with no way to provide the
// document is a dead end. So when upload is off, the camera is on, whatever
// `allowDocumentScan` says.
//
// Resolved in ONE place so the capture screen, the step header and anything
// added later can never disagree about which mode the flow is in. Mirrors the
// web and React Native SDKs' resolution.

@immutable
class DocumentCaptureMethods {
  /// The live camera (viewfinder, auto-capture, side clips).
  final bool scan;

  /// Picking a photo of each side from the device.
  final bool upload;

  const DocumentCaptureMethods({required this.scan, required this.upload});

  /// The camera is never used: each side is a picked photo.
  bool get uploadOnly => upload && !scan;

  @override
  bool operator ==(Object other) =>
      other is DocumentCaptureMethods &&
      other.scan == scan &&
      other.upload == upload;

  @override
  int get hashCode => Object.hash(scan, upload);

  @override
  String toString() => 'DocumentCaptureMethods(scan: $scan, upload: $upload)';
}

/// The effective capture methods for a pair of switches.
///
/// upload = [allowDocumentUpload]; scan = [allowDocumentScan], except that a
/// flow with upload off always scans (both off would leave no way through).
DocumentCaptureMethods documentCaptureMethods({
  required bool allowDocumentScan,
  required bool allowDocumentUpload,
}) =>
    DocumentCaptureMethods(
      scan: allowDocumentScan || !allowDocumentUpload,
      upload: allowDocumentUpload,
    );

/// [documentCaptureMethods] over a mounted (workflow-merged) config.
DocumentCaptureMethods documentCaptureMethodsFor(MyazaKYCConfig config) =>
    documentCaptureMethods(
      allowDocumentScan: config.allowDocumentScan,
      allowDocumentUpload: config.allowDocumentUpload,
    );
