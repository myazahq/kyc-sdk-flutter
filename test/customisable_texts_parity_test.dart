import 'dart:convert';
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:myaza_kyc_sdk_flutter/src/i18n/customisable_texts.dart';

// ─── The customisable texts against the shared contract ──────────────────────
//
// test/customisable_texts_vectors.json is written by the web SDK and read by
// every SDK: the keys a workflow may change. The KEY is the contract (a
// workflow stores `texts[language][key]`, and it must mean the same spot on
// every SDK); the wording of each default is this SDK's own. Every key is
// either wired here (it has a default) or listed as not shown, with a reason.

Map<String, dynamic> _vectors() => jsonDecode(
      File('test/customisable_texts_vectors.json').readAsStringSync(),
    ) as Map<String, dynamic>;

final _placeholder = RegExp(r'\{([a-zA-Z][a-zA-Z0-9]*)\}');

void main() {
  final data = _vectors();
  final vectors = (data['texts'] as List).cast<Map<String, dynamic>>();
  final vectorKeys = {for (final v in vectors) v['key'] as String};

  test('the base language is English', () {
    expect(data['baseLanguage'], 'en');
  });

  test('the customisable key set is exactly the shared one', () {
    expect(kCustomisableTextKeys, vectorKeys);
    expect(kCustomisableTextKeys.length, vectors.length);
  });

  test('every key is wired or not shown, never both', () {
    final wired = kDefaultTexts.keys.toSet();
    final notShown = kNotShownTexts.keys.toSet();
    expect(wired.intersection(notShown), isEmpty);
    expect(wired.union(notShown), vectorKeys);
    expect(wired.difference(vectorKeys), isEmpty, reason: 'a default for a key nobody shares');
    expect(notShown.difference(vectorKeys), isEmpty, reason: 'a reason for a key nobody shares');
  });

  test('every not-shown key says why', () {
    kNotShownTexts.forEach((key, reason) {
      expect(reason.trim(), isNotEmpty, reason: key);
    });
  });

  test('a default uses only the placeholders its key offers', () {
    // The applicant's names are filled on every text, on every SDK.
    const always = {'firstName', 'lastName', 'businessName'};
    for (final v in vectors) {
      final key = v['key'] as String;
      final value = kDefaultTexts[key];
      if (value == null) continue;
      final offered = {...always, ...((v['placeholders'] as List?) ?? const []).cast<String>()};
      final used = _placeholder.allMatches(value).map((m) => m.group(1)!).toSet();
      expect(used.difference(offered), isEmpty, reason: key);
    }
  });

  test('no default carries an em dash', () {
    kDefaultTexts.forEach((key, value) {
      expect(value.contains('—'), isFalse, reason: key);
      expect(value.trim(), isNotEmpty, reason: key);
    });
  });

  test('every wired key with an older config field takes it as its legacy value', () {
    // The older fields this SDK passes as legacy values, as the web SDK does.
    const legacyWired = {
      'welcome.title': ['consent', 'title'],
      'welcome.description': ['consent', 'description'],
      'questionnaire.title': ['questionnaire', 'title'],
      'questionnaire.description': ['questionnaire', 'description'],
      'result.success.title': ['success', 'title'],
      'result.success.description.individual': ['success', 'description'],
      'result.success.description.business': ['success', 'description'],
      'proofOfAddress.kind.other': ['proofOfAddress', 'otherLabel'],
      'result.faceCheck.checking.title': ['biometric', 'copy', 'waiting', 'title'],
      'result.faceCheck.checking.description': ['biometric', 'copy', 'waiting', 'description'],
      'result.faceCheck.sending.title': ['biometric', 'copy', 'waiting', 'title'],
      'result.faceCheck.sending.description': ['biometric', 'copy', 'waiting', 'description'],
      'result.faceEnrolment.saving.title': ['biometric', 'copy', 'waiting', 'title'],
      'result.faceEnrolment.saving.description': ['biometric', 'copy', 'waiting', 'description'],
      'result.faceCheck.verified.title': ['biometric', 'copy', 'verified', 'title'],
      'result.faceCheck.verified.description': ['biometric', 'copy', 'verified', 'description'],
      'result.faceCheck.declined.title': ['biometric', 'copy', 'declined', 'title'],
      'result.faceCheck.declined.description': ['biometric', 'copy', 'declined', 'description'],
    };
    for (final v in vectors) {
      final key = v['key'] as String;
      final path = (v['configPath'] as List?)?.cast<String>();
      // Every wired key with an older field takes it as its legacy value.
      if (path != null && kDefaultTexts.containsKey(key)) {
        expect(legacyWired[key], path, reason: key);
      }
      if (legacyWired.containsKey(key)) expect(path, legacyWired[key], reason: key);
    }
  });
}
