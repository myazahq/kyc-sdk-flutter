import 'package:flutter_test/flutter_test.dart';
import 'package:myaza_kyc_sdk_flutter/src/providers/kyc_state.dart';
import 'package:myaza_kyc_sdk_flutter/src/providers/session_progress.dart';
import 'package:myaza_kyc_sdk_flutter/src/providers/session_restore.dart';

// ─── Restoring a smart address from a session snapshot ───────────────────
//
// The snapshot was written by WHATEVER build saved it, so every field is
// coerced rather than trusted, and a pin that cannot be read is dropped whole
// instead of half-restored. Split from session_restore_test.dart (200-line
// rule), which keeps the generic step and ID-type guards; the step CLAMP lives
// in address_resume_test.dart.

void main() {
  test('round-trips the smart address (JSON ints included) and door photo', () {
    // JSON decodes 6 as int and 6.4281 as double — restore must take both.
    final s = restoredState(const KYCState(), {
      'step': 'address-collection',
      'mediaIds': {'addressPhoto': 'med_9'},
      'data': {
        'selectedCountry': 'NG',
        'address': {
          'lat': 6,
          'lng': 3.4219,
          'directions': 'black gate',
          'label': '11 Bassey Street, Idim Ita, Calabar',
          'parts': {'street': 'Bassey Street', 'city': 'Calabar'},
          'pickedAt': {'lat': 6, 'lng': 3.4219},
          'labelKept': true,
          'deviceLat': 6.4283,
          'deviceLng': 3.4217,
          'capturedAt': '2026-08-25T00:00:00.000Z',
        },
      },
    });
    expect(s.currentStep, KYCStep.addressCollection);
    expect(s.mediaIds.addressPhoto, 'med_9');
    expect(s.address?.lat, 6.0);
    expect(s.address?.lng, 3.4219);
    expect(s.address?.directions, 'black gate');
    // The picked address and the applicant's answer about it survive: losing
    // them would make somebody redo a search they had already finished.
    expect(s.address?.label, '11 Bassey Street, Idim Ita, Calabar');
    expect(s.address?.parts?.city, 'Calabar');
    expect(s.address?.pickedAt?.lng, 3.4219);
    expect(s.address?.labelKept, isTrue);
    // The device fix is deliberately NOT restored. It is evidence of standing
    // somewhere at a MOMENT, so it is taken fresh when the applicant confirms
    // rather than resurrected from a session they left days ago.
    expect(s.address?.deviceLat, isNull);
    expect(s.address?.capturedAt, isNull);

    final snapshot = progressFromState(s);
    final replayed = restoredState(const KYCState(), snapshot);
    expect(replayed.address?.lat, 6.0);
    expect(replayed.address?.directions, 'black gate');
    expect(replayed.address?.label, '11 Bassey Street, Idim Ita, Calabar');
    expect(replayed.address?.labelKept, isTrue);
    expect(replayed.mediaIds.addressPhoto, 'med_9');
  });

  test('a wrong-typed address field is dropped, never crashed on', () {
    // The snapshot was written by WHATEVER build saved it, so a field that
    // arrives as the wrong shape degrades to restoring less.
    final s = restoredState(const KYCState(), {
      'step': 'address-collection',
      'mediaIds': const <String, String>{},
      'data': {
        'address': {
          'lat': 6.4281,
          'lng': 3.4219,
          'directions': 42,
          'label': false,
          'parts': 'Calabar',
          'pickedAt': {'lat': 6.4281},
          'labelKept': 'yes',
          // Three of four values point the camera nowhere.
          'streetView': {'panoId': 'p1', 'heading': 10, 'pitch': 0},
        },
      },
    });
    expect(s.address?.lat, 6.4281);
    expect(s.address?.directions, '');
    expect(s.address?.label, isNull);
    expect(s.address?.parts, isNull);
    expect(s.address?.pickedAt, isNull);
    expect(s.address?.labelKept, isFalse);
    expect(s.address?.streetView, isNull);
  });

  test('a snapshot with an unreadable pin is ignored, never half-restored', () {
    final s = restoredState(const KYCState(), {
      'step': 'consent',
      'mediaIds': const <String, String>{},
      'data': {
        'address': {'lat': 6.4281},
      },
    });
    expect(s.address, isNull);
  });
}
