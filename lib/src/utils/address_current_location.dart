import '../config/address_flow.dart';
import '../services/api_service.dart';
import '../services/location_service.dart';

// ─── The shared current-location fix ─────────────────────────────────────────
//
// The device's current location, fetched ONCE per flow and shared by every
// address step. Module-level on purpose: the steps mount and unmount as the
// applicant walks the flow, and re-prompting or re-fixing on every screen is
// exactly the hesitation this exists to remove.
//
// The GPS warm-up runs while the person is still reading the search screen, so
// by the pin step the fix and its reverse-geocoded line are usually already in
// hand: the map lands right first time instead of showing a default view and
// then jumping.
//
// Mirrors the web SDK's steps/address/current-location.ts and the RN SDK's
// lib/address-current-location.ts.

/// A resolved fix plus whatever the reverse geocoder could say about it.
class CurrentFix {
  final double lat;
  final double lng;
  final double? accuracy;

  /// The reverse-geocoded line, when known. Showing it on the location row is
  /// the point: the applicant sees where it will take them BEFORE tapping.
  final String? label;
  final AddressParts? parts;

  const CurrentFix({
    required this.lat,
    required this.lng,
    this.accuracy,
    this.label,
    this.parts,
  });
}

CurrentFix? _resolved;
Future<CurrentFix?>? _inflight;
bool _failed = false;
LocationFailure? _failure;
bool _autoLocateAttempted = false;

/// The fix, when one has already resolved this flow.
CurrentFix? currentFix() => _resolved;

/// Why the last attempt failed, so the message can say something true
/// ([locationFailureMessage]). Null once a fix resolves or the flow resets.
LocationFailure? currentFixFailure() => _failure;

/// Whether an attempt is still running.
bool locatingCurrentFix() => _inflight != null && _resolved == null;

/// Claims the ONE automatic locate the pin step is allowed, returning false
/// once it has been spent.
///
/// The pin step opens on the applicant's own location rather than a
/// city-centre default, but only the first time: a dismissed or denied prompt
/// must not re-fire every time they pass back through the step. Module-level
/// like the fix beside it, and reset with it — a browser's "page session" is a
/// FLOW here, not the app process, so a second run of the SDK is a fresh
/// attempt by (possibly) a different person in a different place.
bool claimAutoLocate() {
  if (_autoLocateAttempted) return false;
  _autoLocateAttempted = true;
  return true;
}

/// Forgets the fix. Called when a flow starts, because a second run of the SDK
/// in the same app process is a new attempt by (possibly) a different person in
/// a different place.
void resetCurrentFix() {
  _resolved = null;
  _inflight = null;
  _failed = false;
  _failure = null;
  _autoLocateAttempted = false;
}

/// Start, or join, the one location attempt.
///
/// Safe to call from every address step's mount: the OS permission prompt fires
/// at most once and concurrent callers share a single attempt.
///
/// A FAILED attempt is never retried automatically. Every step mount calls
/// this, and re-arming on failure made the location row spin forever while the
/// permission prompt re-fired on every screen. An explicit tap passes
/// [retry] and gets a fresh attempt, because the applicant may have granted
/// permission since; a silent path never does.
/// [stubbed] is the SANDBOX treatment: the canned pin stands in for the
/// hardware (so a test key never triggers a permission prompt) and the sample
/// line stands in for the geocoder. See [addressVendorsStubbed].
Future<CurrentFix?> prefetchCurrentFix(
  KYCApiService api, {
  bool preview = false,
  bool retry = false,
  bool stubbed = false,
}) {
  final resolved = _resolved;
  if (resolved != null) return Future.value(resolved);
  if (_failed && _inflight == null && !retry) return Future.value(null);
  return _inflight ??= _attempt(api, preview || stubbed, stubbed);
}

Future<CurrentFix?> _attempt(
  KYCApiService api,
  bool canned,
  bool stubbed,
) async {
  final read = await resolveMyLocation(preview: canned);
  final fix = read.fix;
  if (fix == null) {
    // Cleared so an explicit later tap may retry.
    _inflight = null;
    _failed = true;
    _failure = read.failure ?? LocationFailure.unsupported;
    return null;
  }
  _failure = null;
  String? label;
  AddressParts? parts;
  if (stubbed) {
    label = kSampleAddressLine;
  } else {
    try {
      final reverse = await api.addressReverse(fix.lat, fix.lng);
      label = reverse.line;
      parts = reverse.parts;
    } catch (_) {
      // The coordinates alone are still a fix — the line is a convenience.
    }
  }
  final result = CurrentFix(
    lat: fix.lat,
    lng: fix.lng,
    accuracy: fix.accuracy,
    label: label,
    parts: parts,
  );
  _resolved = result;
  _failed = false;
  return result;
}
