import 'package:flutter_test/flutter_test.dart';
import 'package:myaza_kyc_sdk_flutter/src/config/kyc_config.dart';
import 'package:myaza_kyc_sdk_flutter/src/providers/kyc_provider.dart';

/// The submit used to read `state.userData` alone. `setUserData` is called from the
/// ID-input screen and nowhere else, and that screen appears only for number-only ids
/// (BVN/NIN) — so on every DOCUMENT id the integrator's `userData` was dropped before
/// it reached the wire. The server then had nothing to compare the document against
/// and returned `dataMatch: null`, with nothing anywhere to explain why.
///
/// The first test is the regression: it fails against the old behaviour.
void main() {
  group('resolveVerifyUserData', () {
    test('sends the consumer prop when nothing was typed in-flow', () {
      // THE BUG. A passport or PVC has no ID-input screen, so `fromState` is always
      // null there — the prop is the only source and must survive.
      final result = resolveVerifyUserData(
        const UserData(firstName: 'Emmanuel', lastName: 'Ingwe'),
        null,
      );
      expect(result, isNotNull);
      expect(result!.firstName, 'Emmanuel');
      expect(result.lastName, 'Ingwe');
    });

    test('lets the prop win per field, with typed values filling the gaps', () {
      final result = resolveVerifyUserData(
        const UserData(firstName: 'Prop'),
        const UserData(firstName: 'Typed', lastName: 'FromInput', dateOfBirth: '1999-07-25'),
      );
      expect(result!.firstName, 'Prop'); //        integrator's value wins
      expect(result.lastName, 'FromInput'); //     prop omitted it, typed fills in
      expect(result.dateOfBirth, '1999-07-25');
    });

    test('treats empty strings as absent, not as a submitted value', () {
      // Submitting `firstName: ''` would ask the server to compare the document
      // against nothing. Example apps commonly pass `firstName.trim()` from a blank
      // input, so this is the realistic case, not a contrived one.
      expect(resolveVerifyUserData(const UserData(firstName: '', lastName: ''), null), isNull);
      final partial = resolveVerifyUserData(const UserData(firstName: 'Emmanuel', lastName: ''), null);
      expect(partial!.firstName, 'Emmanuel');
      expect(partial.lastName, isNull);
    });

    test('returns null when there is nothing at all to compare', () {
      expect(resolveVerifyUserData(null, null), isNull);
      expect(resolveVerifyUserData(const UserData(), const UserData()), isNull);
    });

    test('still sends what the user typed for number-only ids', () {
      // The path that always worked — BVN/NIN, where the ID-input screen collects
      // the name. It must keep working.
      final result = resolveVerifyUserData(null, const UserData(firstName: 'Ada', lastName: 'Okafor'));
      expect(result!.firstName, 'Ada');
      expect(result.lastName, 'Okafor');
    });
  });
}
