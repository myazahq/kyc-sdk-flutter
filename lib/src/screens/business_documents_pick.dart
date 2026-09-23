part of 'business_documents_screen.dart';

// ─── Business documents — picking the file ───────────────────────────────────
//
// The picking itself is shared (document_pick.dart) so every screen that asks
// for a document offers the same three sources. What stays here is the part
// that reads this screen's own state — `mounted`, `_upload`, `_fail` — which
// is why it is a `part` rather than a helper.

extension _BusinessDocumentPickOps on _BusinessDocumentsScreenState {
  Future<void> _pick(String key) async {
    _rebuild(() => _errors.remove(key));
    final result = await pickDocument(context, slotKey: key);
    if (!mounted) return;
    if (result.error != null) {
      _fail(key, result.error!);
      return;
    }
    final file = result.file;
    if (file == null) return; // cancelled
    await _upload(key, file.bytes, file.mimeType, file.fileName,
        previewPath: file.previewPath);
  }
}
