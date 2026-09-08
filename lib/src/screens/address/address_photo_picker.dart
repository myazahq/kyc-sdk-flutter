import 'dart:typed_data';

import 'package:flutter/widgets.dart';
import 'package:image_picker/image_picker.dart';

import '../../config/address_collection.dart';
import '../../config/upload_limits.dart';
import '../../widgets/media_source_sheet.dart';

// ─── Getting the entrance photo off the device ───────────────────────────────
//
// Camera or photo library only: the entrance photo is a PICTURE of a place, so
// there is no PDF or Files case. Mirrors the RN SDK's address photo picker.

/// What came back from the picker: the bytes to upload, their type, and the
/// local path the review step renders as a preview.
class PickedAddressPhoto {
  final Uint8List bytes;
  final String mimeType;
  final String path;

  const PickedAddressPhoto(this.bytes, this.mimeType, this.path);
}

/// The result of asking for a photo: one of a pick, a refusal to explain, or
/// nothing at all (the applicant backed out, which is not an error).
class AddressPhotoPickResult {
  final PickedAddressPhoto? photo;
  final String? error;

  const AddressPhotoPickResult({this.photo, this.error});
}

String _mimeFor(String? name) =>
    switch (name?.split('.').last.toLowerCase()) {
      'png' => 'image/png',
      'webp' => 'image/webp',
      _ => 'image/jpeg',
    };

/// Ask for an entrance photo: pick a source, then read and vet the file.
Future<AddressPhotoPickResult> pickAddressPhoto(BuildContext context) async {
  final source = await showMediaSourceSheet(context, allowFiles: false);
  if (source == null) return const AddressPhotoPickResult();
  try {
    final picked = await ImagePicker().pickImage(
      source: source == MediaSource.camera
          ? ImageSource.camera
          : ImageSource.gallery,
      imageQuality: 90,
    );
    if (picked == null) return const AddressPhotoPickResult();
    final bytes = await picked.readAsBytes();
    final mime = picked.mimeType ?? _mimeFor(picked.name);
    // The picker's media filter is advisory on some platforms, so what came
    // back is re-checked rather than trusted.
    if (!isAcceptedAddressPhotoMimeType(mime)) {
      return const AddressPhotoPickResult(
          error: 'Please upload a photo (JPEG, PNG or WebP).');
    }
    if (bytes.length > kImageMaxBytes) {
      return const AddressPhotoPickResult(
          error: 'Photo is too large (max 5 MB).');
    }
    return AddressPhotoPickResult(
        photo: PickedAddressPhoto(bytes, mime, picked.path));
  } catch (_) {
    return const AddressPhotoPickResult(
        error: 'Could not read that photo. Please try another.');
  }
}
