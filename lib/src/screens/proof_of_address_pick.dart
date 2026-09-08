import 'dart:typed_data';

import 'package:file_picker/file_picker.dart';
import 'package:image_picker/image_picker.dart';

// ─── Proof of Address — picking the document ──────────────────────────────────
//
// The three native sources (photo library, camera, Files) reduced to one
// shape the screen uploads. Split out of the screen (200-line rule); knows
// nothing about state, uploading or the KYC providers.

/// A picked document: its bytes, the mime the server is told, and the name
/// shown in the uploaded row.
typedef PoaPick = ({Uint8List bytes, String mime, String name});

/// A pick that failed for a reason the user can act on (the message is shown
/// verbatim). A cancelled pick is null, never an exception.
class PoaPickException implements Exception {
  final String message;
  const PoaPickException(this.message);
}

const List<String> _kAllowedExtensions = ['jpg', 'jpeg', 'png', 'webp', 'pdf'];

String poaMimeFor(String? ext) => switch (ext?.toLowerCase()) {
      'png' => 'image/png',
      'webp' => 'image/webp',
      'pdf' => 'application/pdf',
      _ => 'image/jpeg',
    };

/// Camera roll / camera — always an image, so the mime comes from the name.
Future<PoaPick?> pickPoaImage(ImageSource source) async {
  try {
    final picked =
        await ImagePicker().pickImage(source: source, imageQuality: 90);
    if (picked == null) return null;
    final bytes = await picked.readAsBytes();
    final ext = picked.name.split('.').lastOrNull;
    return (bytes: bytes, mime: poaMimeFor(ext), name: picked.name);
  } catch (_) {
    throw const PoaPickException(
      'Could not read that photo. Please try another.',
    );
  }
}

/// Files — the only path that can supply a PDF.
Future<PoaPick?> pickPoaFile() async {
  try {
    final result = await FilePicker.platform.pickFiles(
      type: FileType.custom,
      allowedExtensions: _kAllowedExtensions,
      withData: true,
    );
    final file = result?.files.firstOrNull;
    final bytes = file?.bytes;
    if (file == null || bytes == null) return null; // cancelled
    return (bytes: bytes, mime: poaMimeFor(file.extension), name: file.name);
  } catch (_) {
    throw const PoaPickException(
      'Could not read that file. Please try another.',
    );
  }
}
