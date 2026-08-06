import 'package:country_flags/country_flags.dart';
import 'package:flutter/material.dart';

// ─── Country flag ─────────────────────────────────────────────────────────────
//
// Small circular country flag — the Flutter mirror of the web SDK's
// `CountryFlag` component (which uses `country-flag-icons`). Renders nothing for
// an unknown/null country.

class MyazaCountryFlag extends StatelessWidget {
  /// ISO-3166 alpha-2 code of the country whose flag to show (e.g. `'NG'`).
  final String? country;

  /// Diameter of the circular flag in logical pixels.
  final double size;

  const MyazaCountryFlag({
    super.key,
    required this.country,
    this.size = 20,
  });

  @override
  Widget build(BuildContext context) {
    final code = country?.toUpperCase();
    if (code == null || code.isEmpty) return const SizedBox.shrink();

    return CountryFlag.fromCountryCode(
      code,
      height: size,
      width: size,
      shape: const Circle(),
    );
  }
}
