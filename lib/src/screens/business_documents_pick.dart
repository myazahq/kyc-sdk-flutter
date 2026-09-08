part of 'business_documents_screen.dart';

// ─── Business documents — picking the file ───────────────────────────────────
//
// The three native sources (photo library, camera, Files) reduced to one
// upload call, split out of the screen (200-line rule). A part rather than a
// helper because every pick reads the screen's own state (`mounted`, `_upload`,
// `_fail`) — the shape of proof_of_address_upload.dart.

const _kAllowedExtensions = ['jpg', 'jpeg', 'png', 'webp', 'pdf'];

extension _BusinessDocumentPickOps on _BusinessDocumentsScreenState {
  String _mimeFor(String? ext) => switch (ext?.toLowerCase()) {
        'png' => 'image/png',
        'webp' => 'image/webp',
        'pdf' => 'application/pdf',
        _ => 'image/jpeg',
      };

  Future<void> _pick(String key) async {
    _rebuild(() => _errors.remove(key));
    final source = await showMediaSourceSheet(context);
    if (source == null || !mounted) return;
    switch (source) {
      case MediaSource.photoLibrary:
        await _pickImage(key, ImageSource.gallery);
      case MediaSource.camera:
        await _pickImage(key, ImageSource.camera);
      case MediaSource.files:
        await _pickFile(key);
    }
  }

  Future<void> _pickImage(String key, ImageSource source) async {
    try {
      final picked =
          await ImagePicker().pickImage(source: source, imageQuality: 90);
      if (picked == null || !mounted) return;
      final bytes = await picked.readAsBytes();
      if (!mounted) return;
      // A FRIENDLY name, not the picker's temp junk: iOS's image_picker names
      // its copy `image_picker_<UUID>.png` (the photo library does not expose
      // the original), which reads as noise on the uploaded card. The slot key
      // says what the file IS — `incorporation_certificate.jpg`.
      final ext = picked.name.split('.').lastOrNull ?? 'jpg';
      await _upload(key, bytes, _mimeFor(ext), '$key.${ext.toLowerCase()}',
          previewPath: picked.path);
    } catch (_) {
      _fail(key, 'Could not read that photo. Please try another.');
    }
  }

  /// Files — the only source that can supply a PDF.
  Future<void> _pickFile(String key) async {
    try {
      final result = await FilePicker.platform.pickFiles(
        type: FileType.custom,
        allowedExtensions: _kAllowedExtensions,
        withData: true,
      );
      final file = result?.files.firstOrNull;
      final bytes = file?.bytes;
      if (file == null || bytes == null || !mounted) return; // cancelled
      await _upload(key, bytes, _mimeFor(file.extension), file.name);
    } catch (_) {
      _fail(key, 'Could not read that file. Please try another.');
    }
  }
}
