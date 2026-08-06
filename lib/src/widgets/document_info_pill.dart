import 'package:flutter/material.dart';

import '../config/id_types.dart' show IdTypeConfig;
import '../config/theme.dart';
import 'country_flag.dart';

// ─── Document info pill ───────────────────────────────────────────────────────
//
// Says WHICH document is expected, in frame.
//
// Going full-screen took away the sheet header and the "Required: …" pill that
// used to carry this, and the camera is precisely where it matters: it is the
// last point before the shutter where someone can notice they have picked up
// the wrong document, or the right document from the wrong country.

/// The document's name, short enough to sit in a pill.
///
/// The catalogue label is written for a picker, where "International Passport"
/// disambiguates. Beside a flag it is redundant twice over — the country is
/// already shown, and nobody is choosing anything at this point. Keyed off the
/// ID type rather than trimmed from the string, so it holds for every country's
/// passport whatever its catalogue label says.
String shortDocumentLabel(IdTypeConfig idType) =>
    idType.key == 'passport' ? 'Passport' : idType.label;

class DocumentInfoPill extends StatelessWidget {
  final IdTypeConfig idType;

  /// ISO-3166 alpha-2 of the document's country (the effective one in a
  /// multi-region flow).
  final String? country;

  const DocumentInfoPill({super.key, required this.idType, this.country});

  @override
  Widget build(BuildContext context) {
    final code = country;
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 7),
      decoration: BoxDecoration(
        color: Colors.black.withValues(alpha: 0.55),
        borderRadius: BorderRadius.circular(MyazaRadius.full),
        border: Border.all(color: Colors.white.withValues(alpha: 0.18)),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          // The flag carries the country on its own — a name beside it is the
          // same fact twice, and the flag reads faster at a glance than text.
          if (code != null && code.isNotEmpty) ...[
            MyazaCountryFlag(country: code, size: 26),
            const SizedBox(width: 9),
          ],
          Flexible(
            child: Text(
              shortDocumentLabel(idType),
              overflow: TextOverflow.ellipsis,
              style: const TextStyle(
                color: Colors.white,
                fontSize: 14,
                fontWeight: FontWeight.w700,
              ),
            ),
          ),
        ],
      ),
    );
  }
}
