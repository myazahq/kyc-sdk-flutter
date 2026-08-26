// ─── Is this a website address? ───────────────────────────────────────────────
//
// Deliberately not a URL parser. A strict parser rejects "company.com" for
// having no scheme, which is how almost everyone writes a website, and accepts
// "mailto:x@y" and "javascript:alert(1)" for having one. Both answers are the
// wrong way round for a field labelled "Website". Mirrors the web SDK's
// lib/website.ts — keep the two in lockstep.

/// Trim, drop a scheme, drop a trailing path/port. What the checks run on.
String _hostOf(String value) => value
    .trim()
    .replaceFirst(RegExp(r'^https?://', caseSensitive: false), '')
    .replaceFirst(RegExp(r'/.*$'), '')
    .replaceFirst(RegExp(r':\d+$'), '');

final _host = RegExp(
  r'^[a-z0-9](?:[a-z0-9-]*[a-z0-9])?(?:\.[a-z0-9](?:[a-z0-9-]*[a-z0-9])?)+$',
  caseSensitive: false,
);

bool isValidWebsite(String value) {
  final raw = value.trim();
  if (raw.isEmpty) return true; // Emptiness is the required-field check's job.

  // A scheme we do not serve is a mistake worth catching: "mailto:" in a
  // website box is a different thing entirely, not a typo in this one.
  if (RegExp(r'^[a-z][a-z0-9+.-]*:', caseSensitive: false).hasMatch(raw) &&
      !RegExp(r'^https?://', caseSensitive: false).hasMatch(raw)) {
    return false;
  }

  final host = _hostOf(raw);
  if (host.isEmpty || host.length > 253) return false;
  if (!_host.hasMatch(host)) return false;

  // A TLD of at least two letters. Rules out "company." and "192.168.0.1",
  // neither of which is a website somebody meant to type.
  final tld = host.substring(host.lastIndexOf('.') + 1);
  return RegExp(r'^[a-z]{2,}$', caseSensitive: false).hasMatch(tld);
}
