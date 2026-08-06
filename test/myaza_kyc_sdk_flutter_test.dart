import 'dart:math';

import 'package:flutter/material.dart' show Color;
import 'package:flutter_test/flutter_test.dart';
import 'package:myaza_kyc_sdk_flutter/myaza_kyc_sdk_flutter.dart';
// KYCEnvironment is internal (not exported from the barrel) — import the source
// for the detection tests.
import 'package:myaza_kyc_sdk_flutter/src/config/kyc_config.dart'
    show KYCEnvironment, parseHexColor;
// Workflow merge machinery is internal — imported from source for its tests.
import 'package:myaza_kyc_sdk_flutter/src/config/workflow_merge.dart';
import 'package:myaza_kyc_sdk_flutter/src/providers/step_order.dart';
import 'package:myaza_kyc_sdk_flutter/src/liveness/flash_detector.dart';
import 'package:myaza_kyc_sdk_flutter/src/liveness/flash_liveness_runner.dart';
import 'package:myaza_kyc_sdk_flutter/src/services/api_service.dart'
    show WorkflowFlowConfig;
import 'package:myaza_kyc_sdk_flutter/src/utils/resolve_url.dart';

void main() {
  // ── Validator smoke tests ────────────────────────────────────────────────────

  group('ID number validators', () {
    test('BVN accepts 11 digits', () {
      final result = validateIdNumber('12345678901', 'NG', 'bvn');
      expect(result.isValid, isTrue);
    });

    test('BVN rejects short input', () {
      final result = validateIdNumber('1234', 'NG', 'bvn');
      expect(result.isValid, isFalse);
      expect(result.errorMessage, isNotNull);
    });

    test('NIN accepts 11 digits', () {
      final result = validateIdNumber('12345678901', 'NG', 'nin');
      expect(result.isValid, isTrue);
    });

    test('NG passport accepts A + 8 digits', () {
      final result = validateIdNumber('A12345678', 'NG', 'passport');
      expect(result.isValid, isTrue);
    });

    test('NG passport rejects wrong format', () {
      final result = validateIdNumber('123456789', 'NG', 'passport');
      expect(result.isValid, isFalse);
    });

    test('Ghana Card accepts GHA-XXXXXXXXX-Y', () {
      final result = validateIdNumber('GHA-123456789-0', 'GH', 'ghana-card');
      expect(result.isValid, isTrue);
    });

    test('SA National ID accepts 13 digits with valid DOB', () {
      final result = validateIdNumber('9001015009087', 'ZA', 'national-id');
      expect(result.isValid, isTrue);
    });

    test('SA National ID rejects invalid date of birth', () {
      // Month 13 is invalid
      final result = validateIdNumber('9013015009087', 'ZA', 'national-id');
      expect(result.isValid, isFalse);
    });

    test('non-curated (Global Document) pair requires only a non-empty value', () {
      expect(validateIdNumber('X999', 'FR', 'national-id').isValid, isTrue);
      expect(validateIdNumber('', 'FR', 'national-id').isValid, isFalse);
    });
  });

  // ── ID type resolution (curated + synthesized) ───────────────────────────────

  group('resolveIdTypeDefinition', () {
    test('curated pair wins and carries its truths', () {
      final def = resolveIdTypeDefinition('NG', 'passport');
      expect(def.label, 'International Passport');
      expect(def.requiresDocumentCapture, isTrue);
      expect(def.supportsNfc, isTrue); // eMRTD passport
    });

    test('synthesizes an unknown document ID from the server row', () {
      final def = resolveIdTypeDefinition(
        'FR',
        'residence-permit',
        label: 'Residence Permit',
        requiresDocumentCapture: true,
        scanSides: 'front_and_back',
        supportsNfc: true,
      );
      expect(def.label, 'Residence Permit');
      expect(def.scanSides, ScanSides.frontAndBack);
      expect(def.supportsNfc, isTrue);
    });

    test('humanizes the label when the server omits one', () {
      final def = resolveIdTypeDefinition('FR', 'national-id');
      expect(def.label, 'National Id');
      expect(def.requiresDocumentCapture, isTrue); // safe default
    });
  });

  // ── ID masking ───────────────────────────────────────────────────────────────

  group('maskIdNumber', () {
    test('masks middle digits of an 11-digit ID', () {
      expect(maskIdNumber('12345678901'), '1234****901');
    });

    test('masks a short ID fully', () {
      expect(maskIdNumber('123'), '***');
    });
  });

  // ── Config defaults ──────────────────────────────────────────────────────────

  group('MyazaKYCConfig defaults', () {
    test('enableSelfie defaults to true', () {
      const config = MyazaKYCConfig(
        apiKey: 'key',
        country: 'NG',
      );
      expect(config.enableSelfie, isTrue);
      expect(config.enableLiveness, isTrue);
      expect(config.enableDocumentCapture, isTrue);
    });
  });

  // ── Workflow merge (flow wins, props fill gaps) ──────────────────────────────

  group('mergeWorkflowIntoConfig', () {
    const base = MyazaKYCConfig(
      apiKey: 'pk_test_x',
      country: 'NG',
      idTypes: ['bvn'],
      enableLiveness: true,
      appearance: MyazaKYCAppearance(companyName: 'Acme', logo: 'default'),
      userId: 'usr_1',
    );

    test('flow wins on defined keys; props fill the gaps', () {
      final merged = mergeWorkflowIntoConfig(
        base,
        const WorkflowFlowConfig(
          country: 'GH',
          idTypes: ['ghana-card', 'passport'],
          enableLiveness: false,
        ),
      );
      expect(merged.country, 'GH'); // flow wins
      expect(merged.idTypes, ['ghana-card', 'passport']); // flow wins
      expect(merged.enableLiveness, isFalse); // flow wins
      expect(merged.enableSelfie, isTrue); // prop default kept (flow undefined)
      expect(merged.userId, 'usr_1'); // runtime data never flow-controlled
    });

    test('undefined flow keys keep the consumer prop', () {
      final merged =
          mergeWorkflowIntoConfig(base, const WorkflowFlowConfig());
      expect(merged.country, 'NG');
      expect(merged.idTypes, ['bvn']);
      expect(merged.enableLiveness, isTrue);
    });

    test('appearance merges shallowly — flow color wins, prop logo kept', () {
      final merged = mergeWorkflowIntoConfig(
        base,
        const WorkflowFlowConfig(appearance: {'primaryColor': '#5645F5'}),
      );
      expect(merged.appearance?.primaryColor, const Color(0xFF5645F5));
      expect(merged.appearance?.logo, 'default'); // not wiped by the flow
      expect(merged.appearance?.companyName, 'Acme');
    });

    test('business workflow with no top-level country falls back to registry',
        () {
      final merged = mergeWorkflowIntoConfig(
        base,
        const WorkflowFlowConfig(
          subjectType: 'business',
          raw: {
            'subjectType': 'business',
            'business': {'country': 'KE'},
          },
        ),
      );
      expect(merged.country, 'KE');
    });

    test('voiceGuidance from a bare bool disables spoken guidance', () {
      final merged = mergeWorkflowIntoConfig(
        base,
        const WorkflowFlowConfig(voiceGuidance: false),
      );
      expect(merged.voiceGuidance.enabled, isFalse);
    });

    test('deviceIntelligence: default on; a flow can turn it off', () {
      expect(base.deviceIntelligence, isTrue); // default
      final off = mergeWorkflowIntoConfig(
        base,
        const WorkflowFlowConfig(raw: {'deviceIntelligence': false}),
      );
      expect(off.deviceIntelligence, isFalse);
      // A flow that doesn't mention it keeps the prop value.
      final kept =
          mergeWorkflowIntoConfig(base, const WorkflowFlowConfig(raw: {}));
      expect(kept.deviceIntelligence, isTrue);
    });

    test('livenessMode: default gestures; a flow can set flash', () {
      expect(base.livenessMode, 'gestures');
      final flash = mergeWorkflowIntoConfig(
        base,
        const WorkflowFlowConfig(raw: {'livenessMode': 'flash'}),
      );
      expect(flash.livenessMode, 'flash');
    });

    test('multi-region countries[] is parsed from the flow raw payload', () {
      final merged = mergeWorkflowIntoConfig(
        base,
        const WorkflowFlowConfig(raw: {
          'countries': [
            {'country': 'NG', 'idTypes': ['bvn', 'nin']},
            {'country': 'GH'},
          ],
        }),
      );
      expect(merged.countries?.length, 2);
      expect(merged.countries?[0].country, 'NG');
      expect(merged.countries?[0].idTypes, ['bvn', 'nin']);
      expect(merged.countries?[1].idTypes, isNull);
    });
  });

  // ── Step order (single source of truth for navigation + progress) ────────────

  group('buildStepOrder', () {
    const config = MyazaKYCConfig(apiKey: 'pk_test_x', country: 'NG');

    test('number-only ID → id-input path (no document-capture)', () {
      final state =
          const KYCState().copyWith(selectedIdType: curatedIdType('NG', 'bvn'));
      expect(buildStepOrder(config, state), [
        KYCStep.consent,
        KYCStep.idType,
        KYCStep.idInput,
        KYCStep.liveness,
        KYCStep.submitted,
      ]);
    });

    test('document ID → document-capture path (no id-input)', () {
      final state = const KYCState()
          .copyWith(selectedIdType: curatedIdType('NG', 'passport'));
      expect(buildStepOrder(config, state), [
        KYCStep.consent,
        KYCStep.idType,
        KYCStep.documentCapture,
        KYCStep.liveness,
        KYCStep.submitted,
      ]);
    });

    test('liveness disabled → liveness step omitted', () {
      const noLive = MyazaKYCConfig(
        apiKey: 'pk_test_x',
        country: 'NG',
        enableLiveness: false,
      );
      final state =
          const KYCState().copyWith(selectedIdType: curatedIdType('NG', 'bvn'));
      expect(buildStepOrder(noLive, state).contains(KYCStep.liveness), isFalse);
    });

    test('before an ID is picked, defaults to the document-capture path', () {
      final order = buildStepOrder(config, const KYCState());
      expect(order.contains(KYCStep.documentCapture), isTrue);
      expect(order.contains(KYCStep.idInput), isFalse);
    });

    test('multi-region config inserts a country-select step before id-type', () {
      const multi = MyazaKYCConfig(
        apiKey: 'pk_test_x',
        country: 'NG',
        countries: [
          WorkflowCountryOption(country: 'NG'),
          WorkflowCountryOption(country: 'GH'),
        ],
      );
      final state =
          const KYCState().copyWith(selectedIdType: curatedIdType('NG', 'bvn'));
      final order = buildStepOrder(multi, state);
      expect(order.contains(KYCStep.countrySelect), isTrue);
      expect(order.indexOf(KYCStep.countrySelect),
          lessThan(order.indexOf(KYCStep.idType)));
    });

    test('single-country config has no country-select step', () {
      final state =
          const KYCState().copyWith(selectedIdType: curatedIdType('NG', 'bvn'));
      expect(buildStepOrder(config, state).contains(KYCStep.countrySelect),
          isFalse);
    });

    test('a picked country overrides the config country (effectiveCountry)', () {
      const multi = MyazaKYCConfig(
        apiKey: 'pk_test_x',
        country: 'NG',
        countries: [
          WorkflowCountryOption(country: 'NG'),
          WorkflowCountryOption(country: 'GH'),
        ],
      );
      expect(effectiveCountry(multi, const KYCState()), 'NG'); // default
      expect(
        effectiveCountry(multi, const KYCState().copyWith(selectedCountry: 'GH')),
        'GH',
      );
    });
  });

  // ── Questionnaire ─────────────────────────────────────────────────────────────

  group('QuestionnaireConfig', () {
    test('parses field types, options, and money currencies', () {
      final cfg = QuestionnaireConfig.fromJson(const {
        'enabled': true,
        'fields': [
          {'key': 'source_of_funds', 'label': 'Source of funds', 'type': 'select',
           'required': true, 'options': [
             {'value': 'salary', 'label': 'Salary'},
             {'value': 'business', 'label': 'Business'},
           ]},
          {'key': 'monthly_volume', 'label': 'Monthly volume', 'type': 'money',
           'currencies': ['NGN', 'USD']},
        ],
      });
      expect(cfg.fields.length, 2);
      expect(cfg.fields[0].type, QuestionnaireFieldType.select);
      expect(cfg.fields[0].required, isTrue);
      expect(cfg.fields[0].options.map((o) => o.value), ['salary', 'business']);
      expect(cfg.fields[1].type, QuestionnaireFieldType.money);
      expect(cfg.fields[1].currencies, ['NGN', 'USD']);
    });

    test('isActive only when enabled AND has fields', () {
      expect(const QuestionnaireConfig(enabled: true, fields: []).isActive, isFalse);
      expect(
        const QuestionnaireConfig(enabled: false, fields: [
          QuestionnaireField(key: 'x', label: 'X', type: QuestionnaireFieldType.text),
        ]).isActive,
        isFalse,
      );
      expect(
        const QuestionnaireConfig(fields: [
          QuestionnaireField(key: 'x', label: 'X', type: QuestionnaireFieldType.text),
        ]).isActive,
        isTrue,
      );
    });

    test('an active questionnaire inserts a step after liveness', () {
      const cfg = MyazaKYCConfig(
        apiKey: 'pk_test_x',
        country: 'NG',
        questionnaire: QuestionnaireConfig(fields: [
          QuestionnaireField(key: 'q', label: 'Q', type: QuestionnaireFieldType.text),
        ]),
      );
      final state =
          const KYCState().copyWith(selectedIdType: curatedIdType('NG', 'bvn'));
      final order = buildStepOrder(cfg, state);
      expect(order.contains(KYCStep.questionnaire), isTrue);
      expect(order.indexOf(KYCStep.questionnaire),
          greaterThan(order.indexOf(KYCStep.liveness)));
      expect(order.indexOf(KYCStep.questionnaire),
          lessThan(order.indexOf(KYCStep.submitted)));
    });
  });

  // ── Proof of Address ──────────────────────────────────────────────────────────

  group('ProofOfAddressConfig', () {
    test('parses documentTypes + maxAgeDays; offeredTypes defaults to all', () {
      final cfg = ProofOfAddressConfig.fromJson(const {
        'enabled': true,
        'documentTypes': ['utility_bill', 'bank_statement'],
        'maxAgeDays': 60,
      });
      expect(cfg.enabled, isTrue);
      expect(cfg.maxAgeDays, 60);
      expect(cfg.offeredTypes,
          [PoaDocumentType.utilityBill, PoaDocumentType.bankStatement]);

      final all = ProofOfAddressConfig.fromJson(const {'enabled': true});
      expect(all.offeredTypes.length, PoaDocumentType.values.length);
    });

    test('enabled config inserts a PoA step between liveness and submitted', () {
      const cfg = MyazaKYCConfig(
        apiKey: 'pk_test_x',
        country: 'NG',
        proofOfAddress: ProofOfAddressConfig(enabled: true),
      );
      final state =
          const KYCState().copyWith(selectedIdType: curatedIdType('NG', 'bvn'));
      final order = buildStepOrder(cfg, state);
      expect(order.contains(KYCStep.proofOfAddress), isTrue);
      expect(order.indexOf(KYCStep.proofOfAddress),
          greaterThan(order.indexOf(KYCStep.liveness)));
      expect(order.indexOf(KYCStep.proofOfAddress),
          lessThan(order.indexOf(KYCStep.submitted)));
    });

    test('document-type keys are the stable contract', () {
      expect(PoaDocumentType.utilityBill.key, 'utility_bill');
      expect(PoaDocumentType.bankStatement.key, 'bank_statement');
      expect(PoaDocumentType.tenancyAgreement.key, 'tenancy_agreement');
      expect(PoaDocumentType.fromKey('bank_statement'),
          PoaDocumentType.bankStatement);
    });
  });

  // ── Contact verification (email / phone OTP) ──────────────────────────────────

  group('Contact verification', () {
    test('email config clamps codeLength to 4–8 and defaults required=true', () {
      final tooBig =
          EmailVerificationConfig.fromJson(const {'enabled': true, 'codeLength': 12});
      expect(tooBig.codeLength, 8);
      final tooSmall =
          EmailVerificationConfig.fromJson(const {'enabled': true, 'codeLength': 2});
      expect(tooSmall.codeLength, 4);
      expect(tooBig.required, isTrue);
    });

    test('phone config parses channels + via + defaultCountry', () {
      final cfg = PhoneVerificationConfig.fromJson(const {
        'enabled': true,
        'channels': ['whatsapp', 'sms'],
        'defaultCountry': 'GH',
        'required': false,
      });
      expect(cfg.via, 'whatsapp'); // first offered channel
      expect(cfg.defaultCountry, 'GH');
      expect(cfg.required, isFalse);
    });

    test('email + phone steps sit after consent, email before phone', () {
      const cfg = MyazaKYCConfig(
        apiKey: 'pk_test_x',
        country: 'NG',
        emailVerification: EmailVerificationConfig(enabled: true),
        phoneVerification: PhoneVerificationConfig(enabled: true),
      );
      final state =
          const KYCState().copyWith(selectedIdType: curatedIdType('NG', 'bvn'));
      final order = buildStepOrder(cfg, state);
      expect(order.indexOf(KYCStep.contactEmail),
          greaterThan(order.indexOf(KYCStep.consent)));
      expect(order.indexOf(KYCStep.contactEmail),
          lessThan(order.indexOf(KYCStep.contactPhone)));
      expect(order.indexOf(KYCStep.contactPhone),
          lessThan(order.indexOf(KYCStep.idType)));
    });

    test('only the enabled contact channel adds a step', () {
      const emailOnly = MyazaKYCConfig(
        apiKey: 'pk_test_x',
        country: 'NG',
        emailVerification: EmailVerificationConfig(enabled: true),
      );
      final state =
          const KYCState().copyWith(selectedIdType: curatedIdType('NG', 'bvn'));
      final order = buildStepOrder(emailOnly, state);
      expect(order.contains(KYCStep.contactEmail), isTrue);
      expect(order.contains(KYCStep.contactPhone), isFalse);
    });
  });

  // ── NFC chip verification ─────────────────────────────────────────────────────

  group('NFC', () {
    test('NfcConfig.selects: empty = all chip-capable; composite key narrows', () {
      const all = NfcConfig(enabled: true);
      expect(all.selects('NG', 'passport'), isTrue);

      const narrow = NfcConfig(enabled: true, idTypes: ['NG/passport']);
      expect(narrow.selects('NG', 'passport'), isTrue);
      expect(narrow.selects('GH', 'ghana-card'), isFalse);
      expect(narrow.selects('ng', 'passport'), isTrue); // case-insensitive
    });

    test('NfcConfig.fromJson parses idTypes + allowSkip', () {
      final cfg = NfcConfig.fromJson(const {
        'enabled': true,
        'idTypes': ['NG/passport'],
        'allowSkip': true,
      });
      expect(cfg.enabled, isTrue);
      expect(cfg.idTypes, ['NG/passport']);
      expect(cfg.allowSkip, isTrue);
    });

    test('step order inserts nfc after document-capture for a chip-capable ID', () {
      const cfg = MyazaKYCConfig(
        apiKey: 'pk_test_x',
        country: 'NG',
        nfc: NfcConfig(enabled: true),
      );
      final state = const KYCState()
          .copyWith(selectedIdType: curatedIdType('NG', 'passport'));
      final order = buildStepOrder(cfg, state);
      expect(order.contains(KYCStep.nfc), isTrue);
      expect(order.indexOf(KYCStep.nfc),
          greaterThan(order.indexOf(KYCStep.documentCapture)));
      expect(order.indexOf(KYCStep.nfc),
          lessThan(order.indexOf(KYCStep.liveness)));
    });

    test('no nfc step for a non-chip-capable ID even when enabled', () {
      const cfg = MyazaKYCConfig(
        apiKey: 'pk_test_x',
        country: 'NG',
        nfc: NfcConfig(enabled: true),
      );
      final state =
          const KYCState().copyWith(selectedIdType: curatedIdType('NG', 'bvn'));
      expect(buildStepOrder(cfg, state).contains(KYCStep.nfc), isFalse);
    });

    test('workflow idTypes selection excludes an unselected chip ID', () {
      const cfg = MyazaKYCConfig(
        apiKey: 'pk_test_x',
        country: 'NG',
        nfc: NfcConfig(enabled: true, idTypes: ['GH/ghana-card']),
      );
      final state = const KYCState()
          .copyWith(selectedIdType: curatedIdType('NG', 'passport'));
      expect(buildStepOrder(cfg, state).contains(KYCStep.nfc), isFalse);
    });
  });

  // ── Business (KYB) workflows ──────────────────────────────────────────────────

  group('Business (KYB)', () {
    test('WorkflowBusinessConfig offered-country/product defaults', () {
      const single = WorkflowBusinessConfig(country: 'NG');
      expect(single.offeredCountries, ['NG']);
      expect(single.offeredProducts, ['business']);

      const multi = WorkflowBusinessConfig(
        country: 'NG',
        countries: ['NG', 'GH'],
        products: ['business', 'business-tin'],
      );
      expect(multi.offeredCountries, ['NG', 'GH']);
      expect(multi.offeredProducts, ['business', 'business-tin']);
    });

    test('products catalog carries labels + input types', () {
      expect(businessProduct('business').input,
          BusinessProductInput.registration);
      expect(businessProduct('business-tin').input, BusinessProductInput.tin);
      expect(businessProduct('business-tin').label, 'TIN');
    });

    test('merge sets subjectType=business, parses block, falls back country', () {
      const base = MyazaKYCConfig(apiKey: 'pk_test_x', country: 'ZZ');
      final merged = mergeWorkflowIntoConfig(
        base,
        const WorkflowFlowConfig(subjectType: 'business', raw: {
          'subjectType': 'business',
          'business': {
            'country': 'NG',
            'products': ['business', 'business-tin'],
            'requireRegistrationName': true,
          },
        }),
      );
      expect(merged.subjectType, 'business');
      expect(merged.business?.country, 'NG');
      expect(merged.business?.requireRegistrationName, isTrue);
      expect(merged.country, 'NG'); // falls back to business.country
    });

    test('business step order: consent → business-details → submitted', () {
      const cfg = MyazaKYCConfig(
        apiKey: 'pk_test_x',
        country: 'NG',
        subjectType: 'business',
        business: WorkflowBusinessConfig(country: 'NG'),
      );
      expect(buildStepOrder(cfg, const KYCState()),
          [KYCStep.consent, KYCStep.businessDetails, KYCStep.submitted]);
    });

    test('business flow inserts questionnaire when active', () {
      const cfg = MyazaKYCConfig(
        apiKey: 'pk_test_x',
        country: 'NG',
        subjectType: 'business',
        business: WorkflowBusinessConfig(country: 'NG'),
        questionnaire: QuestionnaireConfig(fields: [
          QuestionnaireField(
              key: 'q', label: 'Q', type: QuestionnaireFieldType.text),
        ]),
      );
      expect(buildStepOrder(cfg, const KYCState()), [
        KYCStep.consent,
        KYCStep.businessDetails,
        KYCStep.questionnaire,
        KYCStep.submitted,
      ]);
    });
  });

  // ── Flash liveness (screen-reflection) ────────────────────────────────────────

  group('flash detector', () {
    test('generateFlashSequence returns N distinct colors', () {
      final seq = generateFlashSequence(3, rng: Random(42));
      expect(seq.length, 3);
      expect(seq.map((c) => c.name).toSet().length, 3); // distinct
    });

    test('correlateFlash: a boost-aligned shift matches', () {
      final s = correlateFlash([100, 100, 100], [150, 100, 100], [1, 0, 0]);
      expect(s.inconclusive, isFalse);
      expect(s.matched, isTrue); // shift is all-red, boost is red
    });

    test('correlateFlash: a tiny shift is inconclusive (too-bright ambient)', () {
      final s = correlateFlash([100, 100, 100], [101, 100, 100], [1, 0, 0]);
      expect(s.inconclusive, isTrue);
      expect(s.matched, isFalse);
    });

    test('correlateFlash: an off-axis shift does not match', () {
      final s = correlateFlash([100, 100, 100], [100, 150, 100], [1, 0, 0]);
      expect(s.matched, isFalse); // shifted green, boost was red
    });

    test('evaluateFlashSequence: all-inconclusive soft-passes; majority rules', () {
      final seq = generateFlashSequence(3, rng: Random(1));
      const inconclusive = FlashSample(inconclusive: true, matched: false, score: 0);
      const matched = FlashSample(inconclusive: false, matched: true, score: 1);
      const missed = FlashSample(inconclusive: false, matched: false, score: 0);

      expect(evaluateFlashSequence(seq, [inconclusive, inconclusive, inconclusive]).passed, isTrue);
      expect(evaluateFlashSequence(seq, [matched, matched, matched]).passed, isTrue);
      expect(evaluateFlashSequence(seq, [matched, missed, missed]).passed, isFalse);
    });

    test('FlashSequenceRunner drives paint→sample→correlate to a pass', () async {
      final painted = <String>[];
      // Scripted face samples: neutral baseline, then a strongly-lit sample that
      // matches each flash's boost. 2 flashes → 4 samples.
      final seq = [kFlashPalette[0], kFlashPalette[1]]; // red, green
      final scripted = <List<double>>[
        [100, 100, 100], [180, 100, 100], // red flash: baseline, lit
        [100, 100, 100], [100, 180, 100], // green flash: baseline, lit
      ];
      var i = 0;
      final runner = FlashSequenceRunner(
        timings: FlashTimings.instant,
        paint: (c) => painted.add(c == null ? 'neutral' : 'color'),
        // The window is handed to the sampler (matching the web's averaging
        // windows) rather than being dead time around a one-shot read.
        sampleFace: (_) async => scripted[i++],
      );
      final result = await runner.run(seq);
      expect(result.matched, 2);
      expect(result.total, 2);
      expect(result.passed, isTrue);
      expect(result.sequence, ['red', 'green']);
      expect(painted.contains('color'), isTrue);
    });
  });

  // ── Hex color parsing ────────────────────────────────────────────────────────

  group('parseHexColor', () {
    test('parses #RRGGBB, bare RRGGBB, and #AARRGGBB', () {
      expect(parseHexColor('#5645F5'), const Color(0xFF5645F5));
      expect(parseHexColor('5645F5'), const Color(0xFF5645F5));
      expect(parseHexColor('#805645F5'), const Color(0x805645F5));
    });

    test('returns null for null / blank / malformed input', () {
      expect(parseHexColor(null), isNull);
      expect(parseHexColor('   '), isNull);
      expect(parseHexColor('#ZZZ'), isNull);
      expect(parseHexColor(42), isNull);
    });
  });

  // ── Environment detection + base URL resolution ──────────────────────────────

  group('environment detection', () {
    test('derives the environment from the key prefix (pk_ and sk_)', () {
      expect(detectEnvironment('pk_dev_abc'), KYCEnvironment.development);
      expect(detectEnvironment('sk_dev_abc'), KYCEnvironment.development);
      expect(detectEnvironment('pk_test_abc'), KYCEnvironment.sandbox);
      expect(detectEnvironment('sk_test_abc'), KYCEnvironment.sandbox);
      expect(detectEnvironment('pk_live_abc'), KYCEnvironment.production);
      expect(detectEnvironment('sk_live_abc'), KYCEnvironment.production);
    });

    test('throws on an unrecognized / malformed key prefix', () {
      expect(() => detectEnvironment('nope_123'), throwsArgumentError);
      expect(() => detectEnvironment('pk_prod_123'), throwsArgumentError);
      expect(() => detectEnvironment('pklive_123'), throwsArgumentError);
      expect(() => detectEnvironment(''), throwsArgumentError);
    });
  });

  group('resolveBaseUrl', () {
    test('sandbox / production resolve to the canonical URLs', () {
      expect(resolveBaseUrl('pk_test_abc'), 'https://trust.myaza.app');
      expect(resolveBaseUrl('pk_live_abc'), 'https://trust.myaza.app');
    });

    test('devUrl is ignored for sandbox/production keys', () {
      expect(
        resolveBaseUrl('pk_live_abc', devUrl: 'http://localhost:9'),
        'https://trust.myaza.app',
      );
    });

    test('development keys honour devUrl when provided', () {
      expect(
        resolveBaseUrl('pk_dev_abc', devUrl: 'http://192.168.1.5:3001'),
        'http://192.168.1.5:3001',
      );
    });
  });
}
