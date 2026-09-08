import 'dart:typed_data';

import 'package:flutter/material.dart';
import 'package:lucide_icons_flutter/lucide_icons.dart';

import '../config/theme.dart';
import '../widgets/country_flag.dart';

// ─── Proof of Address — the uploaded state ────────────────────────────────────
//
// Split out of proof_of_address_parts.dart (200-line rule), which re-exports
// this file so importers see one module: the drop zone lives there, the
// uploaded row and its thumbnail live here.

/// The uploaded state — thumbnail, file name, document kind, and a remove (X).
class PoaUploadedRow extends StatelessWidget {
  final String fileName;
  final String typeLabel;
  final Uint8List? previewBytes;
  final bool isPdf;

  /// The country the document is for — the flag before the kind, so the
  /// preview still says which market the paper is being read against.
  final String? country;

  final VoidCallback? onRemove;

  const PoaUploadedRow({
    super.key,
    required this.fileName,
    required this.typeLabel,
    required this.previewBytes,
    required this.isPdf,
    this.country,
    this.onRemove,
  });

  @override
  Widget build(BuildContext context) {
    final colors = context.myazaColors;
    final text = context.myazaText;

    return Container(
      padding: const EdgeInsets.all(MyazaSpacing.md),
      decoration: BoxDecoration(
        color: colors.backgroundSecondary,
        border: Border.all(color: colors.border),
        borderRadius: BorderRadius.circular(MyazaRadius.md),
      ),
      child: Row(
        children: [
          PoaThumb(bytes: previewBytes, isPdf: isPdf),
          const SizedBox(width: MyazaSpacing.md),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              mainAxisSize: MainAxisSize.min,
              children: [
                Text(
                  fileName,
                  style: text.label,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                ),
                const SizedBox(height: 2),
                Row(
                  children: [
                    if (country != null) ...[
                      MyazaCountryFlag(country: country, size: 14),
                      const SizedBox(width: MyazaSpacing.xs),
                    ],
                    Flexible(
                      child: Text(
                        typeLabel,
                        style: text.bodySmall
                            .copyWith(color: colors.textSecondary),
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                      ),
                    ),
                  ],
                ),
              ],
            ),
          ),
          if (onRemove != null)
            IconButton(
              onPressed: onRemove,
              visualDensity: VisualDensity.compact,
              tooltip: 'Remove document',
              icon: Icon(LucideIcons.x, size: 18, color: colors.textSecondary),
            ),
        ],
      ),
    );
  }
}

/// 48×48 preview of the picked file — the image itself, or a document tile for
/// a PDF (and for an image that fails to decode, so a corrupt pick still
/// renders a row rather than a broken box).
class PoaThumb extends StatelessWidget {
  final Uint8List? bytes;
  final bool isPdf;

  const PoaThumb({super.key, required this.bytes, required this.isPdf});

  @override
  Widget build(BuildContext context) {
    final colors = context.myazaColors;
    final data = bytes;

    if (isPdf || data == null) {
      return Container(
        width: 48,
        height: 48,
        alignment: Alignment.center,
        decoration: BoxDecoration(
          color: colors.background,
          border: Border.all(color: colors.border),
          borderRadius: BorderRadius.circular(MyazaRadius.xs),
        ),
        child: Icon(LucideIcons.fileText, size: 22, color: colors.primary),
      );
    }

    return ClipRRect(
      borderRadius: BorderRadius.circular(MyazaRadius.xs),
      child: Image.memory(
        data,
        width: 48,
        height: 48,
        fit: BoxFit.cover,
        gaplessPlayback: true,
        errorBuilder: (context, _, __) =>
            const PoaThumb(bytes: null, isPdf: true),
      ),
    );
  }
}

