import 'package:flutter/material.dart';

import '../config/trust_attribution.dart';

/// The footer when the workflow carries the organisation's own attribution:
/// "Protected by", then the org's logo, with no Myaza mark and no link. A port
/// of the web SDK's custom branch of `TrustAttributionMark`.
///
/// The logo sits on the surface as uploaded (no plate, no filter, no tint),
/// sized like the Myaza wordmark it replaces (24 tall, width to fit, at most
/// 144 wide) so switching modes does not make the footer jump. A logo that
/// fails to load falls back to the org's NAME, never to Myaza: our mark on a
/// flow the org asked to carry their own would be the one wrong answer.
class CustomTrustMark extends StatelessWidget {
  const CustomTrustMark({
    super.key,
    required this.resolved,
    required this.markColor,
  });

  final ResolvedTrustAttribution resolved;

  /// The footer's one neutral tone, picked against the surface behind it.
  final Color markColor;

  /// Matches the Myaza wordmark's rendered height.
  static const double logoHeight = 24;
  static const double logoMaxWidth = 144;

  /// Not customisable: it matches the dashboard's Workflow Settings wording.
  static const String label = 'Protected by';

  @override
  Widget build(BuildContext context) {
    final logo = resolved.logo;
    final name = resolved.companyName;
    final fallback = name == null
        ? const SizedBox.shrink()
        : Text(
            name,
            key: const ValueKey('custom-trust-name'),
            overflow: TextOverflow.ellipsis,
            style: TextStyle(
              fontSize: 14,
              fontWeight: FontWeight.w600,
              color: markColor,
            ),
          );

    return Row(
      mainAxisAlignment: MainAxisAlignment.center,
      crossAxisAlignment: CrossAxisAlignment.center,
      children: [
        // Small and muted: the label is connective tissue, the logo carries
        // the weight.
        Opacity(
          opacity: 0.9,
          child: Text(
            label,
            style: TextStyle(fontSize: 12, height: 1.2, color: markColor),
          ),
        ),
        const SizedBox(width: 10),
        ConstrainedBox(
          constraints: const BoxConstraints(
            minHeight: 32,
            maxWidth: logoMaxWidth + 16,
          ),
          child: Center(
            widthFactor: 1,
            child: logo == null
                ? fallback
                : ConstrainedBox(
                    constraints: const BoxConstraints(
                      maxWidth: logoMaxWidth,
                      maxHeight: logoHeight,
                    ),
                    child: Image.network(
                      logo,
                      key: ValueKey('custom-trust-logo:$logo'),
                      height: logoHeight,
                      fit: BoxFit.contain,
                      semanticLabel:
                          name == null ? 'Organisation logo' : '$name logo',
                      errorBuilder: (_, __, ___) => fallback,
                    ),
                  ),
          ),
        ),
      ],
    );
  }
}
