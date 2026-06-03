import 'package:country_flags/country_flags.dart';
import 'package:flutter/material.dart';

import '../config/id_types.dart';

// ─── Country flag ─────────────────────────────────────────────────────────────
//
// Small circular country flag — the Flutter mirror of the web SDK's
// `CountryFlag` component (which uses `country-flag-icons`). Renders nothing for
// an unknown/null country.

class MyazaCountryFlag extends StatelessWidget {
  /// The country whose flag to show.
  final Country? country;

  /// Diameter of the circular flag in logical pixels.
  final double size;

  const MyazaCountryFlag({
    super.key,
    required this.country,
    this.size = 20,
  });

  @override
  Widget build(BuildContext context) {
    final code = country?.name;
    if (code == null) return const SizedBox.shrink();

    return CountryFlag.fromCountryCode(
      code,
      theme: ImageTheme(
        height: size,
        width: size,
        shape: const Circle(),
      ),
    );
  }
}
