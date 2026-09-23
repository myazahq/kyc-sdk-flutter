import 'package:flutter_test/flutter_test.dart';
import 'package:myaza_kyc_sdk_flutter/src/config/supporting_documents.dart';

// MIRROR of the web SDK's supporting-documents-intro test. An applicant on iOS
// must read the same words as one on the web.
ResolvedSupportingDocument _slot({required bool required}) => ResolvedSupportingDocument(
      key: 'k',
      label: 'L',
      description: null,
      required: required,
    );

List<ResolvedSupportingDocument> _req(int n) =>
    List.generate(n, (_) => _slot(required: true));
List<ResolvedSupportingDocument> _opt(int n) =>
    List.generate(n, (_) => _slot(required: false));

void main() {
  test('says what is needed when everything is', () {
    expect(supportingDocumentsIntro(_req(1)),
        'We need this document to continue. Upload it below.');
    expect(supportingDocumentsIntro(_req(3)),
        'We need all 3 of these documents to continue. Upload one for each item below.');
  });

  test('says the step can be skipped when nothing is compulsory', () {
    expect(supportingDocumentsIntro(_opt(1)), contains('You can skip it.'));
    expect(supportingDocumentsIntro(_opt(2)), contains('You can skip the rest.'));
  });

  test('counts the required ones when the list is mixed', () {
    expect(
      supportingDocumentsIntro([..._req(1), ..._opt(2)]),
      'We need 1 of these 3 documents to continue, marked with *. '
      'Upload the others if you have them.',
    );
  });

  test('never explains the asterisk where it marks everything or nothing', () {
    expect(supportingDocumentsIntro(_req(2)), isNot(contains('*')));
    expect(supportingDocumentsIntro(_opt(2)), isNot(contains('*')));
  });

  test('never hedges the plural', () {
    for (final slots in [_req(1), _req(2), _opt(1), _opt(3), [..._req(1), ..._opt(1)]]) {
      expect(supportingDocumentsIntro(slots), isNot(contains('(s)')));
    }
  });
}
