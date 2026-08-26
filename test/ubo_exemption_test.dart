import 'package:flutter_test/flutter_test.dart';
import 'package:myaza_kyc_sdk_flutter/src/services/api_service.dart';

// The FATF fallback, attested. Some companies genuinely have no natural person
// who qualifies as a UBO; without a way to say so the applicant's only moves
// were to stall or to invent one. The flag has to REACH the server, because
// `keyPeople.uboUnidentifiable` is what a decision graph branches on.
void main() {
  Map<String, dynamic> businessJson({required bool ubo}) =>
      VerifyBusiness(
        registrationNumber: 'RC123456',
        uboUnidentifiable: ubo,
      ).toJson();

  test('carries the attestation when the applicant made it', () {
    expect(businessJson(ubo: true)['uboUnidentifiable'], true);
  });

  test('omits the key entirely when they did not', () {
    // Absent, not `false`: an unasserted claim is not the same as a denial, and
    // the server treats a missing key as "nothing was attested".
    expect(businessJson(ubo: false).containsKey('uboUnidentifiable'), false);
  });
}
