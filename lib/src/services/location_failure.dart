// ─── Why a fix could not be taken ────────────────────────────────────────────
//
// A refused permission, a phone that cannot place itself (location switched
// off, no provider), and a fix that took longer than the window are three
// different problems with three different remedies, and one line telling
// everybody to "allow location access" sent people to a permission that was
// already granted. Mirrors the web SDK's LocationFailure and the RN SDK's.

enum LocationFailure { denied, unavailable, timeout, unsupported }

/// The message for [reason]. Placing the pin by hand always works, so every
/// line says so rather than leaving the applicant stuck. Null (a failure the
/// cache never recorded) reads as unsupported.
String locationFailureMessage(LocationFailure? reason) {
  switch (reason) {
    case LocationFailure.denied:
      return "Location access is blocked for this app. Allow it in your phone's Settings, then try again, or place the pin yourself.";
    case LocationFailure.unavailable:
      return 'Your phone could not work out where it is right now. Check that location is switched on, then try again, or place the pin yourself.';
    case LocationFailure.timeout:
      return 'Finding your location took too long. Try again, or place the pin yourself.';
    case LocationFailure.unsupported:
    case null:
      return 'This device cannot share its location. Place the pin yourself.';
  }
}
