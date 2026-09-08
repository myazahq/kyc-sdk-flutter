part of 'proof_of_address_screen.dart';

// ─── Proof of Address — uploading, failing, removing ─────────────────────────
//
// The screen's upload lifecycle, split out of the screen (200-line rule). A
// part rather than a helper because every operation reads and writes the
// screen's own private state (`_uploading`, `_fileName`, the preview) and
// reports through its `ref` and `widget`.

extension _PoaUploadOps on _ProofOfAddressScreenState {
  Future<void> _upload(Uint8List bytes, String mime, String name) async {
    final sizeError = uploadSizeError(mime, bytes.length);
    if (sizeError != null) {
      _failUpload(sizeError);
      return;
    }
    final isPdf = mime == 'application/pdf';
    _rebuild(() {
      _uploading = true;
      _fileName = name;
      _previewIsPdf = isPdf;
      // Only images are renderable; a PDF falls back to the document tile.
      _previewBytes = isPdf ? null : bytes;
    });
    try {
      final api = ref.read(kYCNotifierProvider.notifier).api;
      final mediaId = await api.upload(bytes, mime, MediaType.proofOfAddress);
      if (!mounted) return;
      ref
          .read(kYCNotifierProvider.notifier)
          .setProofOfAddress(mediaId, (_type ?? PoaDocumentType.other).key);
      _rebuild(() => _uploading = false);
    } on KYCApiException catch (e) {
      _failUpload(e.message ?? 'Upload failed. Please try again.');
      widget.onError?.call(e);
    } catch (e) {
      _failUpload('Upload failed. Please try again.');
    }
  }

  void _failUpload(String message) {
    if (!mounted) return;
    _rebuild(() {
      _uploading = false;
      _fileName = null;
      _previewBytes = null;
      _previewIsPdf = false;
      _error = message;
    });
  }

  void _remove() {
    ref.read(kYCNotifierProvider.notifier).clearProofOfAddress();
    _rebuild(() {
      _fileName = null;
      _previewBytes = null;
      _previewIsPdf = false;
      _error = null;
    });
  }
}
