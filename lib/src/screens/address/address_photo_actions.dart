import 'package:flutter/foundation.dart';

import '../../providers/kyc_provider.dart';
import '../../services/api_service.dart';

// ─── The entrance photo ──────────────────────────────────────────────────────
//
// Upload a picked entrance photo and remember its local path so the review
// step can show it. Split from address_flow_controller.dart (200-line rule).

mixin AddressPhotoActions on ChangeNotifier {
  // ── Provided by the controller ─────────────────────────────────────────────
  KYCApiService get api;
  KYCNotifier get notifier;
  bool get alive;
  void setError(String? message);

  bool _uploading = false;
  bool get uploading => _uploading;

  /// The path is a display artefact and never serialised.
  Future<void> uploadPhoto(
    Uint8List bytes,
    String mimeType,
    String previewPath,
  ) async {
    setError(null);
    _uploading = true;
    notifyListeners();
    try {
      final mediaId = await api.upload(bytes, mimeType, MediaType.addressPhoto);
      if (!alive) return;
      notifier.setAddressPhoto(mediaId);
      notifier.setAddressPhotoPreview(previewPath);
    } catch (_) {
      if (!alive) return;
      setError('Upload failed. Please check your connection and try again.');
    } finally {
      if (alive) {
        _uploading = false;
        notifyListeners();
      }
    }
  }

  void removePhoto() {
    notifier.clearAddressPhoto();
    notifier.setAddressPhotoPreview(null);
  }
}
