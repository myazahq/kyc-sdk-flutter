import 'package:flutter_test/flutter_test.dart';
import 'package:myaza_kyc_sdk_flutter/src/config/kyc_config.dart';
import 'package:myaza_kyc_sdk_flutter/src/config/workflow_merge.dart';
import 'package:myaza_kyc_sdk_flutter/src/i18n/customisable_texts.dart';
import 'package:myaza_kyc_sdk_flutter/src/i18n/text_scope.dart';
import 'package:myaza_kyc_sdk_flutter/src/i18n/translate.dart';
import 'package:myaza_kyc_sdk_flutter/src/services/api_service.dart';

// ─── The text resolver ────────────────────────────────────────────────────────
//
// A port of the web SDK's translate.test.ts: the same order (own language,
// then the older config field, then English, then this SDK's default), blank
// as unset, placeholders filled, and workflow copy only for customisable keys.

void main() {
  group('resolveText', () {
    test('falls back from the language, to English, to the default', () {
      const texts = {
        'en': {'common.continue': 'Next'},
        'fr': {'common.continue': 'Continuer'},
      };
      expect(resolveText('common.continue', texts: texts, language: 'fr'), 'Continuer');
      expect(resolveText('common.continue', texts: texts, language: 'pt'), 'Next');
      expect(resolveText('common.continue'), 'Continue');
    });

    test('treats a blank override as unset, so clearing a field restores the default', () {
      expect(
        resolveText('common.continue', texts: const {'en': {'common.continue': '   '}}),
        'Continue',
      );
    });

    test('fills placeholders and drops missing values without leaving braces', () {
      expect(fillPlaceholders('{done} of {total}', const {'done': 2, 'total': 5}), '2 of 5');
      final t = createTextFn(null, 'en', const {'firstName': null});
      expect(t('x.greeting', legacy: 'Welcome, {firstName}'), 'Welcome,');
    });

    test('leaves an unknown placeholder visible rather than guessing', () {
      expect(fillPlaceholders('Hello {nobody}'), 'Hello {nobody}');
    });

    test('lets an older dedicated field win in English, but not over another language', () {
      const texts = {
        'en': {'common.continue': 'Next'},
        'fr': {'common.continue': 'Continuer'},
      };
      expect(resolveText('common.continue', texts: texts, legacy: 'Go on'), 'Go on');
      expect(
        resolveText('common.continue', texts: texts, language: 'fr', legacy: 'Go on'),
        'Continuer',
      );
      expect(resolveText('common.continue', legacy: '  '), 'Continue');
    });

    test('returns the key itself for an unknown key, so a gap is visible', () {
      expect(resolveText('nope.missing'), 'nope.missing');
    });

    test('reads workflow copy only for customisable keys', () {
      // A variant this SDK keeps as written: the workflow cannot reword it,
      // but the older field still wins, as it always did.
      const texts = {'en': {'welcome.title.variant': 'Hijacked'}};
      expect(
        resolveText('welcome.title.variant', texts: texts, fallback: 'Face Check'),
        'Face Check',
      );
      expect(
        resolveText('welcome.title.variant',
            texts: texts, legacy: 'Mine', fallback: 'Face Check'),
        'Mine',
      );
    });

    test('collapses runs of spaces and trims', () {
      expect(
        resolveText('welcome.title',
            texts: const {'en': {'welcome.title': '  Hi   {firstName}  there '}},
            vars: const {'firstName': null}),
        'Hi there',
      );
    });

    test('every wired key resolves to this SDK default with no workflow copy', () {
      kDefaultTexts.forEach((key, value) {
        expect(resolveText(key), fillPlaceholders(value).replaceAll(RegExp(r'[ \t]{2,}'), ' ').trim());
      });
    });
  });

  group('the flow text function', () {
    const base = MyazaKYCConfig(
      apiKey: 'pk_test_aaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaa',
      country: 'NG',
      userData: UserData(firstName: 'Ada', lastName: 'Obi', businessName: 'Acme'),
    );

    test('fills the applicant names on every text', () {
      final t = textFnFor(base.copyWith(texts: const {
        'en': {'welcome.title': 'Hello {firstName} {lastName} of {businessName}'},
      }));
      expect(t('welcome.title'), 'Hello Ada Obi of Acme');
    });

    test('shows the texts in the configured language', () {
      final config = MyazaKYCConfig(
        apiKey: base.apiKey,
        country: 'NG',
        texts: const {
          'en': {'common.continue': 'Next'},
          'fr': {'common.continue': 'Continuer'},
        },
        language: 'fr',
      );
      expect(textFnFor(config)('common.continue'), 'Continuer');
    });

    test('a workflow carries its texts through the merge, replacing the prop', () {
      final flow = WorkflowResolution.fromJson({
        'flow': {'id': 'wf_x', 'name': 'x', 'version': 1},
        'config': {
          'country': 'NG',
          'texts': {
            'en': {'common.continue': 'Next', 'junk': 3},
            'bad': 'not a map',
          },
        },
        'environment': 'SANDBOX',
        'idTypes': <dynamic>[],
      });
      final merged = mergeWorkflowIntoConfig(
        base.copyWith(texts: const {'en': {'common.done': 'Finish'}}),
        flow.config,
      );
      expect(merged.texts, {
        'en': {'common.continue': 'Next'},
      });
      expect(textFnFor(merged)('common.continue'), 'Next');
    });

    test('a flow without texts keeps the consumer prop and the language', () {
      final flow = WorkflowResolution.fromJson({
        'flow': {'id': 'wf_y', 'name': 'y', 'version': 1},
        'config': {'country': 'NG'},
        'environment': 'SANDBOX',
        'idTypes': <dynamic>[],
      });
      final merged = mergeWorkflowIntoConfig(
        MyazaKYCConfig(
          apiKey: base.apiKey,
          country: 'NG',
          texts: const {'fr': {'common.done': 'Terminé'}},
          language: 'fr',
        ),
        flow.config,
      );
      expect(textFnFor(merged)('common.done'), 'Terminé');
    });
  });

  test('parseWorkflowTexts drops anything that is not text', () {
    expect(parseWorkflowTexts(null), isNull);
    expect(parseWorkflowTexts('x'), isNull);
    expect(parseWorkflowTexts({'en': {'a': 'b', 'c': 1}, 3: {}, 'fr': []}), {
      'en': {'a': 'b'},
    });
  });
}
