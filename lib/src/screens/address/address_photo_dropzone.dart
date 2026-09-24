import 'package:flutter/material.dart';

import '../../config/theme.dart';
import '../../widgets/dashed_border.dart';
import 'address_photo_filled.dart';
import '../../widgets/icons/icons.dart';

// ─── The entrance photo, as the hero of its screen ───────────────────────────
//
// The step is about one decision, so the capture owns it: a tall dashed zone
// while empty, and the photo itself at full width once picked, with its
// controls as pills over the image. Mirrors the web and RN SDKs'
// AddressPhotoUpload.

/// Tall enough that the capture owns the screen it is the point of.
const double kAddressPhotoZoneHeight = 300;

class AddressPhotoDropzone extends StatelessWidget {
  final bool required;
  final bool uploaded;
  final bool uploading;

  /// The local path of the picked file. Absent on a RESTORED session, which
  /// holds the uploaded mediaId but not the bytes.
  final String? previewPath;

  final VoidCallback onPick;
  final VoidCallback onRemove;

  const AddressPhotoDropzone({
    super.key,
    required this.required,
    required this.uploaded,
    required this.uploading,
    required this.previewPath,
    required this.onPick,
    required this.onRemove,
  });

  @override
  Widget build(BuildContext context) {
    if (uploaded && !uploading) return AddressPhotoFilled(this);
    return _Empty(this);
  }
}

class _Empty extends StatelessWidget {
  final AddressPhotoDropzone parent;
  const _Empty(this.parent);

  @override
  Widget build(BuildContext context) {
    final colors = context.myazaColors;
    final text = context.myazaText;
    final uploading = parent.uploading;
    return Semantics(
      button: true,
      child: InkWell(
        onTap: uploading ? null : parent.onPick,
        borderRadius: BorderRadius.circular(MyazaRadius.md),
        child: CustomPaint(
          // Web's rounded-2xl (16) is `md` here; the RN zone wears the same.
          painter: DashedRoundedBorder(
              color: colors.border, radius: MyazaRadius.md, strokeWidth: 2),
          child: Container(
            height: kAddressPhotoZoneHeight,
            alignment: Alignment.center,
            padding: const EdgeInsets.symmetric(
                horizontal: MyazaSpacing.lg, vertical: MyazaSpacing.lg),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                Container(
                  width: 56,
                  height: 56,
                  alignment: Alignment.center,
                  decoration: BoxDecoration(
                    color: colors.primary.withValues(alpha: 0.1),
                    borderRadius: BorderRadius.circular(MyazaRadius.md),
                    border: Border.all(
                        color: colors.primary.withValues(alpha: 0.2)),
                  ),
                  child: uploading
                      ? SizedBox(
                          width: 22,
                          height: 22,
                          child: CircularProgressIndicator(
                              strokeWidth: 2, color: colors.primary),
                        )
                      : MyazaIcon(MyazaIcons.camera,
                          size: 24, color: colors.primary),
                ),
                const SizedBox(height: MyazaSpacing.md),
                Text(
                  uploading ? 'Uploading photo…' : 'Take or upload a photo',
                  style: text.body.copyWith(fontWeight: FontWeight.w600),
                  textAlign: TextAlign.center,
                ),
                if (!uploading) ...[
                  const SizedBox(height: MyazaSpacing.xs),
                  Text(
                    parent.required
                        ? 'The gate, front door or the building itself.'
                        : 'The gate, front door or the building itself. Optional.',
                    style: text.bodyMedium
                        .copyWith(color: colors.textSecondary),
                    textAlign: TextAlign.center,
                  ),
                  const SizedBox(height: MyazaSpacing.md),
                  Container(
                    padding: const EdgeInsets.symmetric(
                        horizontal: 10, vertical: 4),
                    decoration: BoxDecoration(
                      color: colors.backgroundSecondary,
                      borderRadius: BorderRadius.circular(MyazaRadius.full),
                    ),
                    child: Text('JPEG · PNG · WebP',
                        style: text.bodySmall.copyWith(
                            fontSize: 11,
                            fontWeight: FontWeight.w500,
                            color: colors.textSecondary)),
                  ),
                ],
              ],
            ),
          ),
        ),
      ),
    );
  }
}
