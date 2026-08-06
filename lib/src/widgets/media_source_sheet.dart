import 'package:flutter/material.dart';
import 'package:lucide_icons_flutter/lucide_icons.dart';

import '../config/theme.dart';
import 'themed_sheet.dart';

// ─── Media source sheet ───────────────────────────────────────────────────────
//
// Asks where a document should come from. The web SDK gets this for free from
// `<input type="file" accept="image/*,application/pdf">` — mobile browsers show
// a Photo Library / Take Photo / Choose File sheet. Native pickers don't: the
// file picker opens the Files app ONLY, so a user with the document in their
// camera roll has no way through. This restores the same three choices.

enum MediaSource { photoLibrary, camera, files }

/// Presents the source choices and resolves to the pick, or null if dismissed.
/// [allowFiles] hides the Files row for image-only flows.
Future<MediaSource?> showMediaSourceSheet(
  BuildContext context, {
  bool allowFiles = true,
  String filesLabel = 'Choose a file',
  String filesSubtitle = 'PDF or image from Files',
}) {
  // Via showMyazaSheet so the sheet's own route carries the SDK palette —
  // otherwise it renders light over a dark flow.
  return showMyazaSheet<MediaSource>(
    context,
    builder: (sheetContext) => SafeArea(
      top: false,
      child: Padding(
        padding: const EdgeInsets.symmetric(vertical: MyazaSpacing.sm),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            _SourceTile(
              icon: LucideIcons.image,
              title: 'Photo Library',
              subtitle: 'Pick an existing photo',
              onTap: () =>
                  Navigator.of(sheetContext).pop(MediaSource.photoLibrary),
            ),
            _SourceTile(
              icon: LucideIcons.camera,
              title: 'Take Photo',
              subtitle: 'Use the camera',
              onTap: () => Navigator.of(sheetContext).pop(MediaSource.camera),
            ),
            if (allowFiles)
              _SourceTile(
                icon: LucideIcons.fileText,
                title: filesLabel,
                subtitle: filesSubtitle,
                onTap: () => Navigator.of(sheetContext).pop(MediaSource.files),
              ),
          ],
        ),
      ),
    ),
  );
}

class _SourceTile extends StatelessWidget {
  final IconData icon;
  final String title;
  final String subtitle;
  final VoidCallback onTap;

  const _SourceTile({
    required this.icon,
    required this.title,
    required this.subtitle,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    final colors = context.myazaColors;
    final text = context.myazaText;

    return InkWell(
      onTap: onTap,
      child: Padding(
        padding: const EdgeInsets.symmetric(
          horizontal: MyazaSpacing.md,
          vertical: MyazaSpacing.md,
        ),
        child: Row(
          children: [
            Container(
              width: 40,
              height: 40,
              alignment: Alignment.center,
              decoration: BoxDecoration(
                color: colors.primary50,
                borderRadius: BorderRadius.circular(MyazaRadius.sm),
              ),
              child: Icon(icon, size: 20, color: colors.primary),
            ),
            const SizedBox(width: MyazaSpacing.md),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(title,
                      style:
                          text.label.copyWith(fontWeight: FontWeight.w600)),
                  Text(subtitle,
                      style: text.bodySmall
                          .copyWith(color: colors.textSecondary)),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }
}
