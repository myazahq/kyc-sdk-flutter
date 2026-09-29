import 'package:flutter_test/flutter_test.dart';
import 'package:myaza_kyc_sdk_flutter/src/providers/awaiting_people.dart';
import 'package:myaza_kyc_sdk_flutter/src/services/api_service.dart';

// ─── The KYB success screen waits for the settled people list ────────────────
//
// The success screen is held on a loader until `finished`. Shown earlier, Done
// sat beside a list still loading, and an applicant could close the sheet
// without ever seeing the people they have to chase (2026-09-29).

class _Api extends KYCApiService {
  _Api(this.answers) : super(baseUrl: 'http://stub', apiKey: 'pk_test_stub');

  final List<SessionSummaryResponse> answers;
  int calls = 0;

  @override
  Future<SessionSummaryResponse> sessionSummary(String sessionId) async {
    final answer = answers[calls < answers.length ? calls : answers.length - 1];
    calls++;
    return answer;
  }
}

const _unsettled = SessionSummaryResponse(keyPeopleSettled: false, keyPeople: []);
const _settled = SessionSummaryResponse(keyPeopleSettled: true, keyPeople: []);

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  test('is not finished while the server is still reconciling', () async {
    final c = AwaitingPeopleController(api: _Api([_unsettled, _settled]), sessionId: 'sess_1');
    addTearDown(c.dispose);
    await Future<void>.delayed(const Duration(milliseconds: 50));
    expect(c.finished, isFalse);
    expect(c.people, isNull);

    // The retry lands the settled answer.
    await Future<void>.delayed(const Duration(milliseconds: 1600));
    expect(c.finished, isTrue);
    expect(c.people, isEmpty);
  });

  test('is finished at once when there is no session to wait on', () {
    final c = AwaitingPeopleController(api: _Api([_settled]), sessionId: null);
    addTearDown(c.dispose);
    expect(c.finished, isTrue);
  });
}
