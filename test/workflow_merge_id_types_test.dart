import 'package:flutter_test/flutter_test.dart';
import 'package:myaza_kyc_sdk_flutter/myaza_kyc_sdk_flutter.dart';
import 'package:myaza_kyc_sdk_flutter/src/config/country_id_types.dart';
import 'package:myaza_kyc_sdk_flutter/src/config/workflow_merge.dart';
import 'package:myaza_kyc_sdk_flutter/src/services/api_service.dart';

// A multi-region flow declares its ID offering inside countries[], where a
// country pinning nothing already means "every granted ID for that country",
// and leaves the top-level list unset. The consumer's prop must not survive
// there: the picker falls back to the top-level list for a country that pins
// none of its own, so a hardcoded list silently narrows every country the flow
// offers.
void main() {
  const base = MyazaKYCConfig(
    apiKey: 'pk_test_aaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaa',
    country: 'NG',
    idTypes: ['bvn', 'nin', 'passport'],
  );

  test('a multi-region flow drops the consumer prop', () {
    final flow = WorkflowFlowConfig.fromJson({
      'countries': [
        {'country': 'NG'},
        {'country': 'GH'},
      ],
    });
    final merged = mergeWorkflowIntoConfig(base, flow);

    expect(merged.idTypes, isNull, reason: 'the prop must not narrow the flow');
    // End to end: the picker now offers every granted ID for the country.
    expect(pinnedIdTypesFor(merged, 'NG'), isNull);
    expect(pinnedIdTypesFor(merged, 'GH'), isNull);
  });

  test("a country's own pinned list still wins", () {
    final flow = WorkflowFlowConfig.fromJson({
      'countries': [
        {'country': 'NG', 'idTypes': ['nin']},
        {'country': 'GH'},
      ],
    });
    final merged = mergeWorkflowIntoConfig(base, flow);

    expect(pinnedIdTypesFor(merged, 'NG'), ['nin']);
    expect(pinnedIdTypesFor(merged, 'GH'), isNull);
  });

  test("a flow's own top-level list still wins over the prop", () {
    final flow = WorkflowFlowConfig.fromJson({
      'countries': [
        {'country': 'NG'},
      ],
      'idTypes': ['passport'],
    });
    final merged = mergeWorkflowIntoConfig(base, flow);

    expect(merged.idTypes, ['passport']);
  });

  test('a single-country flow keeps the prop, as before', () {
    final flow = WorkflowFlowConfig.fromJson({'country': 'NG'});
    final merged = mergeWorkflowIntoConfig(base, flow);

    expect(merged.idTypes, ['bvn', 'nin', 'passport']);
    expect(pinnedIdTypesFor(merged, 'NG'), ['bvn', 'nin', 'passport']);
  });
}
