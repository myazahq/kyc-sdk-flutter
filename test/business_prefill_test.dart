import 'package:flutter_test/flutter_test.dart';
import 'package:myaza_kyc_sdk_flutter/src/config/business.dart';
import 'package:myaza_kyc_sdk_flutter/src/config/business_application.dart';
import 'package:myaza_kyc_sdk_flutter/src/config/business_prefill.dart';
import 'package:myaza_kyc_sdk_flutter/src/config/website.dart';
import 'package:myaza_kyc_sdk_flutter/src/services/api_business.dart';

// The register-prefill and website rules, pinned. Mirrors the RN SDK's
// business-prefill tests — the three SDKs must agree on what gets filled,
// what gets left alone, and what counts as a date.

void main() {
  group('isoDateOnly', () {
    test('takes the date part of an ISO timestamp', () {
      expect(isoDateOnly('2018-03-12T00:00:00.000Z'), '2018-03-12');
      expect(isoDateOnly('2018-03-12'), '2018-03-12');
    });

    test('refuses ambiguous regional formats rather than guessing the order',
        () {
      expect(isoDateOnly('12/03/2018'), isNull);
      expect(isoDateOnly('March 12, 2018'), isNull);
    });

    test('checks the calendar, so an invalid date never rolls forward', () {
      expect(isoDateOnly('2018-02-31'), isNull);
      expect(isoDateOnly('2018-13-01'), isNull);
    });
  });

  group('registerPrefillPatch', () {
    const company = BusinessCompanyRecord(
      name: 'ACME LTD',
      registrationNumber: 'RC1',
      registrationDate: '2015-06-01T00:00:00Z',
      typeOfEntity: 'Private Limited',
      address: '1 Marina Road',
      city: 'Lagos',
      state: 'Lagos State',
      email: 'ops@acme.com',
    );

    test('fills only EMPTY fields and reports which', () {
      final r = registerPrefillPatch(company, {
        'registrationName': '',
        'address': 'Typed by the applicant',
        'email': '',
      });
      expect(r.patch['registrationName'], 'ACME LTD');
      expect(r.patch['email'], 'ops@acme.com');
      // The applicant typed an address, so the register never overwrites it.
      expect(r.patch.containsKey('address'), isFalse);
      expect(r.patch['dateOfIncorporation'], '2015-06-01');
      expect(r.prefilled, r.patch.keys.toList());
    });

    test('joins the register address parts into the one form box', () {
      final r = registerPrefillPatch(company, {});
      expect(r.patch['address'], '1 Marina Road, Lagos, Lagos State');
    });

    test('no company means no patch', () {
      final r = registerPrefillPatch(null, {'registrationName': ''});
      expect(r.patch, isEmpty);
      expect(r.prefilled, isEmpty);
    });
  });

  group('isValidWebsite', () {
    test('accepts the way people actually write websites', () {
      expect(isValidWebsite('company.com'), isTrue);
      expect(isValidWebsite('https://company.com/about'), isTrue);
      expect(isValidWebsite(''), isTrue); // required-ness is checked elsewhere
    });

    test('rejects non-web schemes and non-hosts', () {
      expect(isValidWebsite('mailto:x@y.com'), isFalse);
      expect(isValidWebsite('company.'), isFalse);
      expect(isValidWebsite('192.168.0.1'), isFalse);
    });
  });

  group('keyPeopleRequireEmail', () {
    WorkflowBusinessConfig cfg(Map<String, dynamic> keyPeople) =>
        WorkflowBusinessConfig.fromJson({'country': 'NG', 'keyPeople': keyPeople});

    test('empty unless the workflow collects AND requires emails', () {
      expect(keyPeopleRequireEmail(null), isEmpty);
      expect(
          keyPeopleRequireEmail(cfg({'enabled': true, 'collect': true})), isEmpty);
    });

    test('defaults to the roles that are sent a verification link', () {
      final roles = keyPeopleRequireEmail(cfg({
        'enabled': true,
        'collect': true,
        'requireEmail': true,
        'level': 'screening_only',
        'perRole': {'beneficial_owner': 'full_kyc'},
      }));
      expect(roles, {KeyPersonRole.beneficialOwner});
    });

    test('an explicit requireEmailRoles list wins', () {
      final roles = keyPeopleRequireEmail(cfg({
        'enabled': true,
        'collect': true,
        'requireEmail': true,
        'requireEmailRoles': ['director'],
      }));
      expect(roles, {KeyPersonRole.director});
    });

    test('a corporate row is always exempt: no inbox, never invited', () {
      const required = {KeyPersonRole.shareholder};
      const person = KeyPersonEntry(
          name: 'Bola Owner', role: KeyPersonRole.shareholder, country: 'NG');
      const company = KeyPersonEntry(
          name: 'Acme Holdings Ltd',
          role: KeyPersonRole.shareholder,
          country: 'NG',
          isCorporate: true);
      expect(rowNeedsEmail(person, required), isTrue);
      expect(rowNeedsEmail(company, required), isFalse);
      // And validity follows: the person is incomplete without the email.
      expect(person.isValidWith(required), isFalse);
      expect(company.isValidWith(required), isTrue);
    });
  });
}
