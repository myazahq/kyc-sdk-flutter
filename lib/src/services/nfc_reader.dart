// ─── NFC chip reader (interface + types) ──────────────────────────────────────
//
// Pure interface + data types for reading an eMRTD chip — NO native dependency
// here, so the config/step/UI/payload code (and tests) depend only on this. The
// real reader (our own ICAO 9303 BAC/PACE stack from lib/src/nfc/, driven over
// flutter_nfc_kit) lives in nfc_reader_emrtd.dart; tests inject a fake via
// [nfcChipReaderOverride].

/// The MRZ-derived Basic Access Control key needed to open a BAC chip session:
/// document number + date of birth + date of expiry (from the document's MRZ).
class NfcMrzKey {
  final String documentNumber;
  final DateTime dateOfBirth;
  final DateTime dateOfExpiry;

  const NfcMrzKey({
    required this.documentNumber,
    required this.dateOfBirth,
    required this.dateOfExpiry,
  });
}

/// What the SDK submits (base64). `chipAuth` is the client-reported session type
/// (`bac`/`pace`/`none`) — informational only; the server does the real passive
/// authentication and never trusts this flag.
class NfcChipData {
  final String dg1Base64;
  final String? sodBase64;

  /// Base64 DG2 — the chip's PORTRAIT — when it could be read. Best-effort like
  /// the SOD: it's the largest data group (a face image, kilobytes), so it's
  /// the most likely to drop if the document is lifted. The server authenticates
  /// it against the SOD's DG2 hash — a passive-auth-verified portrait is bound
  /// to the genuine chip, so (unlike a printed photo) it can be trusted for a
  /// face match. null ⇒ the chip check runs without it, exactly as before.
  final String? dg2Base64;

  final String chipAuth;

  /// Why the session ended up on [chipAuth] — `used`, `notOffered`,
  /// `unsupportedVariant`, `failed` or `notAttempted`. Diagnostic: a chip
  /// reading over BAC because it offers no PACE is fine, one reading over BAC
  /// because our PACE broke is a bug, and the protocol alone cannot tell them
  /// apart.
  final String? paceOutcome;

  /// Free text for [paceOutcome] — the negotiated protocol, or the error.
  final String? paceDetail;

  /// Why EF.SOD couldn't be read, when it couldn't. Diagnostic only — never
  /// submitted. Without the SOD the server has nothing to run passive
  /// authentication against, so the result can only ever be `inconclusive`;
  /// keeping the reason lets the UI say so instead of silently downgrading.
  final String? sodError;

  const NfcChipData({
    required this.dg1Base64,
    this.sodBase64,
    this.dg2Base64,
    this.chipAuth = 'bac',
    this.sodError,
    this.paceOutcome,
    this.paceDetail,
  });

  /// True when the chip opened but its signed security object didn't come back.
  bool get missingSod => sodBase64 == null;
}

/// Typed chip-read failure. [code] is one of `unavailable` | `auth_failed`
/// (wrong MRZ key / BAC failed) | `tag_lost` | `read_failed` | `cancelled`.
class NfcReadException implements Exception {
  final String code;
  final String message;
  const NfcReadException(this.code, this.message);

  @override
  String toString() => 'NfcReadException($code): $message';
}

/// Where a chip read has got to.
///
/// iOS narrates these in the system NFC sheet (`setIosAlertMessage`), which is
/// why an iPhone shows the read progressing all the way down to the photo.
/// Android has NO system NFC UI at all — the OS shows nothing — so without
/// these the user watches a spinner with no idea whether the chip has even been
/// detected. Reporting the stages lets the SDK draw the same narration itself.
enum NfcReadStage {
  /// Session open, waiting for the user to actually present the chip. On
  /// Android this is where a read sits until the document touches the phone.
  waiting,

  /// Chip detected; opening the BAC session with the MRZ key.
  authenticating,

  /// Reading DG1 — the document's printed details.
  readingData,

  /// Reading EF.SOD — the signed security object. Kilobytes, so this is the
  /// long one, and the step users tend to abandon by lifting the document.
  readingSecurity,

  /// Reading DG2 — the chip's portrait.
  readingPhoto,

  /// Everything that could be read has been.
  done,
}

extension NfcReadStageLabel on NfcReadStage {
  /// Short label for the step list. Deliberately the same wording the iOS sheet
  /// uses, so the two platforms narrate the read identically.
  String get label => switch (this) {
        NfcReadStage.waiting => 'Waiting for the chip',
        NfcReadStage.authenticating => 'Unlocking the chip',
        NfcReadStage.readingData => 'Reading document details',
        NfcReadStage.readingSecurity => 'Reading security data',
        NfcReadStage.readingPhoto => 'Reading photo',
        NfcReadStage.done => 'Chip read complete',
      };

  /// One line on what the phone is actually doing. A chip read is invisible —
  /// no shutter, no preview — so the detail is what stops a pause reading as a
  /// failure and prompting the user to lift the document.
  String get detail => switch (this) {
        NfcReadStage.waiting =>
          'Hold the top edge of your document flat against the back of your '
              'phone.',
        NfcReadStage.authenticating =>
          'Opening a secure session using the code printed on your photo page.',
        NfcReadStage.readingData =>
          'Copying the details stored on the chip.',
        NfcReadStage.readingSecurity =>
          'Downloading the chip’s digital signature. This is the largest part '
              'and takes the longest — keep holding.',
        NfcReadStage.readingPhoto =>
          'Copying the photo stored on the chip.',
        NfcReadStage.done => 'Everything was read successfully.',
      };

  /// Position in the read, 0..1 — drives the sheet's progress bar.
  double get progress => switch (this) {
        NfcReadStage.waiting => 0,
        NfcReadStage.authenticating => 0.15,
        NfcReadStage.readingData => 0.35,
        NfcReadStage.readingSecurity => 0.6,
        NfcReadStage.readingPhoto => 0.85,
        NfcReadStage.done => 1,
      };
}

abstract class NfcChipReader {
  /// Whether the device has an enabled NFC radio. False ⇒ the step auto-skips.
  Future<bool> isAvailable();

  /// Opens a BAC session with [key] and reads DG1 (+ EF.SOD when present).
  /// Throws [NfcReadException] on failure.
  ///
  /// [onStage] reports progress as the read moves through the chip's data
  /// groups — the SDK's own substitute for the system sheet Android doesn't
  /// have. Called on the calling isolate; safe to drive setState from.
  Future<NfcChipData> read(
    NfcMrzKey key, {
    String iosAlertMessage,
    void Function(NfcReadStage stage)? onStage,
  });
}

/// Test/override hook — when set, `createNfcChipReader()` (in
/// nfc_reader_emrtd.dart) returns this instead of the real chip reader. Lets
/// unit tests exercise the step without an NFC radio.
NfcChipReader? nfcChipReaderOverride;
