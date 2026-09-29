import 'package:flutter_test/flutter_test.dart';
import 'package:myaza_kyc_sdk_flutter/src/services/api_service.dart';

// A 400 invalid_media refusal names the capture it refused. The mapping kept
// details only for 402/403/422, so Go back never reached the right step.
void main() {
  test('a refused upload keeps the capture it names', () {
    expect(errorDetailsFrom(400, {'error': 'invalid_media', 'mediaKey': 'selfie'}), {'mediaKey': 'selfie'});
  });

  test('the other refusals keep what they carried before', () {
    expect(errorDetailsFrom(402, {'required': 1, 'balance': 0, 'currency': 'USD'}),
        {'required': 1, 'balance': 0, 'currency': 'USD'});
    expect(errorDetailsFrom(422, {'missing': ['email']}), {'missing': ['email']});
    expect(errorDetailsFrom(403, {'feature': 'gov_db_check'}), {'feature': 'gov_db_check'});
    expect(errorDetailsFrom(403, {'error': 'business_not_approved'}), isNull);
    expect(errorDetailsFrom(400, {'error': 'invalid_input'}), isNull);
  });
}
