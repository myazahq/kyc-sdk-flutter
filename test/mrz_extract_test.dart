import 'package:flutter_test/flutter_test.dart';
import 'package:myaza_kyc_sdk_flutter/src/services/mrz_extract.dart';

// ─── MRZ extraction from recognizer lines ────────────────────────────────────
//
// On a high-resolution still, Android's recognizer can return one printed MRZ
// line as two text lines: a passport's two-line band came back as three lines
// and no candidate had the right width (2026-09-15). These pin that split lines
// are joined back, and that a join still has to pass the check digits.

// ICAO 9303 specimen, the same one the parser tests use.
const _line1 = 'P<UTOERIKSSON<<ANNA<MARIA<<<<<<<<<<<<<<<<<<<';
const _line2 = 'L898902C36UTO7408122F1204159ZE184226B<<<<<10';
final _now = DateTime(2026);

void main() {
  test('reads two whole lines', () {
    expect(extractMrz([_line1, _line2], now: _now)?.documentNumber, 'L898902C3');
  });

  test('reads fillers the recognizer returned as guillemets', () {
    // '«' for '<<' and '‹' for '<', the way Android's recognizer returns them.
    const line1 = 'P‹UTOERIKSSON«ANNA‹MARIA«««««««««‹';
    expect(extractMrz([line1, _line2], now: _now)?.documentNumber, 'L898902C3');
  });

  test('trims a trailing filler run the recognizer over-counted', () {
    // Every '<' of the name padding read as '«', so the run maps to twice its
    // printed length and the line comes back 63 wide.
    final line1 = 'P<UTOERIKSSON<<ANNA<MARIA${'«' * 19}';
    expect(extractMrz([line1, _line2], now: _now)?.documentNumber, 'L898902C3');
  });

  test('pads a trailing filler run the recognizer under-counted', () {
    final line1 = 'P<UTOERIKSSON<<ANNA<MARIA${'<' * 6}';
    expect(extractMrz([line1, _line2], now: _now)?.documentNumber, 'L898902C3');
  });

  test('joins a first line the recognizer split in two', () {
    final lines = [
      'PASSPORT',
      'P<UTOERIKSSON<<ANNA<MARIA',
      '<<<<<<<<<<<<<<<<<<<',
      _line2,
    ];
    expect(extractMrz(lines, now: _now)?.documentNumber, 'L898902C3');
  });

  test('joins a second line split mid-field', () {
    final lines = [_line1, 'L898902C36UTO7408122F12', '04159ZE184226B<<<<<10'];
    expect(extractMrz(lines, now: _now)?.documentNumber, 'L898902C3');
  });

  test('joins both lines split, with page text around them', () {
    final lines = [
      'Date of Expiry',
      'P<UTOERIKSSON<<',
      'ANNA<MARIA<<<<<<<<<<<<<<<<<<<',
      'L898902C36UTO7408122F',
      '1204159ZE184226B<<<<<10',
      'Holder signature',
    ];
    expect(extractMrz(lines, now: _now)?.documentNumber, 'L898902C3');
  });

  test('a join that fails its check digits is not accepted', () {
    final lines = [_line1, 'L898902C36UTO7408122F12', '04159ZE184226B<<<<<11'];
    expect(extractMrz(lines, now: _now), isNull);
  });

  test('page text alone yields nothing', () {
    expect(
      extractMrz(['FEDERAL REPUBLIC', 'PASSPORT', 'Date of Birth'], now: _now),
      isNull,
    );
  });
}
