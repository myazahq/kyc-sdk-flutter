import 'package:flutter_test/flutter_test.dart';
import 'package:myaza_kyc_sdk_flutter/myaza_kyc_sdk_flutter.dart';
import 'package:myaza_kyc_sdk_flutter/src/providers/step_order.dart';

// The KYB application section: which steps a business workflow adds, and how
// the rows it collects are validated and shaped for the wire. These are the
// parts the server rejects a submission over (422 missing_documents /
// key_people_required), so they get direct coverage rather than being inferred
// from a rendered screen.

WorkflowBusinessConfig businessFromJson(Map<String, dynamic> json) =>
    WorkflowBusinessConfig.fromJson({'country': 'NG', ...json});

MyazaKYCConfig businessConfig(WorkflowBusinessConfig business) =>
    MyazaKYCConfig(
      apiKey: 'pk_test_aaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaa',
      country: business.country,
      workflowId: 'wf_test',
      subjectType: 'business',
      business: business,
    );

void main() {
  group('workflow business config parsing', () {
    test('parses the full application section off a resolved workflow', () {
      // Shaped exactly like a published KYB workflow's `config.business`.
      final business = businessFromJson({
        'country': 'CI',
        'countries': ['CI', 'KE', 'NG', 'ZA'],
        'documents': {
          'enabled': true,
          'types': [
            {'key': 'incorporation_certificate', 'required': true},
            {'key': 'memart', 'required': true},
            {'key': 'proof_of_address', 'required': false},
          ],
        },
        'keyPeople': {
          'enabled': true,
          'collect': true,
          'minEntries': 1,
          'perRole': {'director': 'screening_only', 'beneficial_owner': 'full_kyc'},
          'invite': {'channel': 'email'},
        },
        'applicant': {'verification': true},
      });

      expect(business.offeredCountries, ['CI', 'KE', 'NG', 'ZA']);
      expect(hasBusinessDocumentsStep(business), isTrue);
      expect(hasKeyPeopleCollection(business), isTrue);
      expect(hasApplicantVerification(business), isTrue);
      expect(keyPeopleMinEntries(business), 1);
      expect(
        business.keyPeople!.levelFor(KeyPersonRole.beneficialOwner),
        KeyPeopleLevel.fullKyc,
      );
      // A full-KYC role + email invites ⇒ collect the contact email.
      expect(business.needsKeyPeopleContactEmail, isTrue);
    });

    test('an absent application section adds no steps', () {
      final business = businessFromJson({});
      expect(hasBusinessDocumentsStep(business), isFalse);
      expect(hasKeyPeopleCollection(business), isFalse);
      expect(hasApplicantVerification(business), isFalse);
      expect(business.needsKeyPeopleContactEmail, isFalse);
    });

    test('keyPeople enabled but not collecting adds no step', () {
      // The server still verifies registry-discovered people — the SDK just
      // doesn't ask the applicant for them.
      final business = businessFromJson({
        'keyPeople': {'enabled': true, 'collect': false},
      });
      expect(hasKeyPeopleCollection(business), isFalse);
    });

    test('the primary country always leads the offered list', () {
      final business = businessFromJson({
        'country': 'NG',
        'countries': ['KE', 'ZA'],
      });
      expect(business.offeredCountries, ['NG', 'KE', 'ZA']);
    });
  });

  group('company profile modes', () {
    test('absent config means every field is optional', () {
      final modes = businessFromJson({}).companyInfoModes;
      expect(modes.values, everyElement(CompanyInfoMode.optional));
      expect(businessFromJson({}).showsCompanyInfo, isTrue);
    });

    test('collectCompanyInfo: false turns every field off', () {
      // Even an explicitly required field — matches the server's resolution.
      final business = businessFromJson({
        'collectCompanyInfo': false,
        'companyInfo': {'address': 'required'},
      });
      expect(business.companyInfoModes.values, everyElement(CompanyInfoMode.off));
      expect(business.showsCompanyInfo, isFalse);
    });

    test('per-field modes are honoured', () {
      final modes = businessFromJson({
        'companyInfo': {'address': 'required', 'website': 'off'},
      }).companyInfoModes;
      expect(modes[CompanyInfoField.address], CompanyInfoMode.required);
      expect(modes[CompanyInfoField.website], CompanyInfoMode.off);
      expect(modes[CompanyInfoField.phone], CompanyInfoMode.optional);
    });
  });

  group('document slots', () {
    test('enabled with no types defaults to a required incorporation cert', () {
      final slots = resolveBusinessDocumentTypes(
          businessFromJson({'documents': {'enabled': true}}));
      expect(slots, hasLength(1));
      expect(slots.single.key, 'incorporation_certificate');
      expect(slots.single.required, isTrue);
    });

    test('an unknown key still renders with a humanized label', () {
      final slots = resolveBusinessDocumentTypes(businessFromJson({
        'documents': {
          'enabled': true,
          'types': [{'key': 'shareholder_register'}],
        },
      }));
      expect(slots.single.label, 'Shareholder Register');
      expect(slots.single.required, isFalse);
    });

    test('a label override wins over the default', () {
      final slots = resolveBusinessDocumentTypes(businessFromJson({
        'documents': {
          'enabled': true,
          'types': [
            {'key': 'memart', 'label': 'Articles of association', 'required': true},
          ],
        },
      }));
      expect(slots.single.label, 'Articles of association');
    });

    test('disabled yields no slots', () {
      expect(resolveBusinessDocumentTypes(businessFromJson({})), isEmpty);
    });
  });

  group('key-person rows', () {
    const valid = KeyPersonEntry(name: 'Bola Owner', country: 'NG');

    test('a name under 2 characters is invalid', () {
      expect(const KeyPersonEntry(name: 'B').isValid, isFalse);
      expect(valid.isValid, isTrue);
    });

    test('email and ownership are validated only when typed', () {
      expect(valid.copyWith(email: '').isValid, isTrue);
      expect(valid.copyWith(email: 'not-an-email').isValid, isFalse);
      expect(valid.copyWith(email: 'a@b.co').isValid, isTrue);
      expect(valid.copyWith(ownershipPct: '').isValid, isTrue);
      expect(valid.copyWith(ownershipPct: '101').isValid, isFalse);
      expect(valid.copyWith(ownershipPct: '-1').isValid, isFalse);
      expect(valid.copyWith(ownershipPct: '25.5').isValid, isTrue);
    });

    test('the payload drops invalid rows and normalizes the rest', () {
      final payload = keyPeoplePayload([
        valid.copyWith(
            role: KeyPersonRole.beneficialOwner,
            ownershipPct: ' 60 ',
            country: 'ng',
            email: ' a@b.co '),
        const KeyPersonEntry(name: 'X'), // too short — dropped
      ]);

      expect(payload, hasLength(1));
      expect(payload.single, {
        'name': 'Bola Owner',
        'role': 'beneficial_owner',
        'email': 'a@b.co',
        'country': 'NG',
        'ownershipPct': 60.0,
      });
    });

    test('blank optional fields are omitted, not sent empty', () {
      // An empty-string email would fail the server's format validation.
      expect(keyPeoplePayload([valid.copyWith(country: '')]).single,
          {'name': 'Bola Owner', 'role': 'director'});
    });

    test('the payload is capped at the server limit', () {
      final rows =
          List.generate(30, (i) => valid.copyWith(name: 'Person $i'));
      expect(keyPeoplePayload(rows), hasLength(20));
    });
  });

  group('step order', () {
    List<KYCStep> orderFor(Map<String, dynamic> businessJson) {
      final business = businessFromJson(businessJson);
      return buildStepOrder(businessConfig(business), const KYCState());
    }

    test('a bare registry lookup is 3 steps', () {
      expect(orderFor({}), [
        KYCStep.consent,
        KYCStep.businessDetails,
        KYCStep.submitted,
      ]);
    });

    test('application sections slot in between details and submission', () {
      expect(
        orderFor({
          'documents': {'enabled': true},
          'keyPeople': {'enabled': true, 'collect': true},
        }),
        [
          KYCStep.consent,
          KYCStep.businessDetails,
          KYCStep.businessDocuments,
          KYCStep.businessKeyPeople,
          KYCStep.submitted,
        ],
      );
    });

    test('applicant verification appends the individual capture leg', () {
      final order = orderFor({'applicant': {'verification': true}});
      expect(order, [
        KYCStep.consent,
        KYCStep.businessDetails,
        KYCStep.applicantRole,
        KYCStep.idType,
        // No ID picked yet, so the order assumes the document path.
        KYCStep.documentCapture,
        KYCStep.liveness,
        KYCStep.submitted,
      ]);
    });

    test('the applicant capture leg ends at submission, never the questionnaire',
        () {
      // The web SDK once routed post-capture to the questionnaire, which in a
      // business flow LOOPED (questionnaire → key people → applicant capture →
      // questionnaire). Flutter walks this one list in both directions, so the
      // leak cannot happen — this pins the shape so a refactor cannot
      // reintroduce it: questionnaire with the COMPANY section, capture leg
      // straight into submitted.
      final config = MyazaKYCConfig(
        apiKey: 'pk_test_aaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaa',
        country: 'NG',
        workflowId: 'wf_test',
        subjectType: 'business',
        business: WorkflowBusinessConfig.fromJson({
          'country': 'NG',
          'keyPeople': {'enabled': true, 'collect': true},
          'applicant': {'verification': true},
        }),
        questionnaire: const QuestionnaireConfig(fields: [
          QuestionnaireField(
            key: 'source_of_funds',
            type: QuestionnaireFieldType.text,
            label: 'Source of funds',
          ),
        ]),
      );
      expect(buildStepOrder(config, const KYCState()), [
        KYCStep.consent,
        KYCStep.businessDetails,
        KYCStep.questionnaire,
        KYCStep.businessKeyPeople,
        KYCStep.applicantRole,
        KYCStep.idType,
        KYCStep.documentCapture,
        KYCStep.liveness,
        KYCStep.submitted,
      ]);
    });

    test('a business flow never gets country-select or proof-of-address', () {
      // Those are individual-only: KYB's country comes from the business block
      // and a registry lookup has no address document.
      final order = orderFor({
        'documents': {'enabled': true},
        'keyPeople': {'enabled': true, 'collect': true},
        'applicant': {'verification': true},
      });
      expect(order, isNot(contains(KYCStep.countrySelect)));
      expect(order, isNot(contains(KYCStep.proofOfAddress)));
    });
  });

  group('a real published KYB workflow', () {
    // Verbatim `config.business` from the "KYB + AML screening" workflow, as
    // returned by GET /api/kyc/workflows/:id. Guards the parse against the
    // shape the server actually sends — note `invite` carries a workflowId but
    // NO channel, and `applicant` is absent.
    final business = WorkflowBusinessConfig.fromJson({
      'country': 'CI',
      'countries': ['CI', 'KE', 'NG', 'ZA'],
      'documents': {
        'types': [
          {'key': 'incorporation_certificate', 'required': true},
          {'key': 'memart', 'required': true},
          {'key': 'proof_of_address', 'required': true},
        ],
        'enabled': true,
      },
      'keyPeople': {
        'invite': {'workflowId': 'wf_i-twn0w2M9Li'},
        'collect': true,
        'enabled': true,
        'perRole': {
          'director': 'screening_only',
          'beneficial_owner': 'full_kyc',
        },
        'minEntries': 1,
      },
    });

    test('drives a 5-step flow with a questionnaire', () {
      final config = MyazaKYCConfig(
        apiKey: 'pk_test_aaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaa',
        country: 'CI',
        workflowId: 'wf_VKjJHaSlS1W0',
        subjectType: 'business',
        business: business,
        questionnaire: const QuestionnaireConfig(fields: [
          QuestionnaireField(
            key: 'expected_monthly_volume',
            type: QuestionnaireFieldType.money,
            label: 'What is your expected monthly transaction volume?',
            required: true,
          ),
        ]),
      );

      // The questionnaire sits BEFORE key people: its questions are about the
      // COMPANY, and naming the directors hands the application over to other
      // people. Mirrors the web and RN SDKs.
      expect(buildStepOrder(config, const KYCState()), [
        KYCStep.consent,
        KYCStep.businessDetails,
        KYCStep.businessDocuments,
        KYCStep.questionnaire,
        KYCStep.businessKeyPeople,
        KYCStep.submitted,
      ]);
    });

    test('all three document slots are required', () {
      final slots = resolveBusinessDocumentTypes(business);
      expect(slots.map((s) => s.key), [
        'incorporation_certificate',
        'memart',
        'proof_of_address',
      ]);
      expect(slots.every((s) => s.required), isTrue);
    });

    test('an invite block without a channel asks for no contact email', () {
      // `invite.channel` is absent, so no email goes out from the SDK's
      // perspective — asking for a contact email would be a dead field.
      expect(business.needsKeyPeopleContactEmail, isFalse);
    });

    test('the company profile defaults to optional-everywhere', () {
      // The workflow omits collectCompanyInfo entirely — the section shows,
      // but nothing in it blocks Continue.
      expect(business.showsCompanyInfo, isTrue);
      expect(business.companyInfoModes.values,
          everyElement(CompanyInfoMode.optional));
    });
  });

  group('product catalogue', () {
    test('tax products are Nigeria-only', () {
      final business = businessFromJson({
        'country': 'NG',
        'countries': ['NG', 'KE'],
        'products': ['business', 'business-tin'],
      });
      expect(business.productsForCountry('NG'), ['business', 'business-tin']);
      // Switching to Kenya must drop TIN — the server would 400 it as
      // product_unsupported.
      expect(business.productsForCountry('KE'), ['business']);
    });

    test('narrowing to nothing falls back to the default product', () {
      final business = businessFromJson({'products': ['business-tin']});
      expect(business.productsForCountry('KE'), [kDefaultBusinessProduct]);
    });

    test('the TIN product asks for a TIN, not a registration number', () {
      expect(businessProduct('business-tin').inputLabel, contains('TIN'));
      expect(businessProduct('business').inputLabel, 'Registration number');
    });
  });

  _corporateTests();
}

void _corporateTests() {
  group('a corporate shareholder', () {
    const corp = KeyPersonEntry(
      name: 'Acme Holdings Ltd',
      role: KeyPersonRole.shareholder,
      ownershipPct: '60',
      isCorporate: true,
      registrationNumber: 'RC123456',
      owners: [
        KeyPersonOwnerEntry(name: 'Jane Doe', ownershipPct: '75', country: 'gb'),
        KeyPersonOwnerEntry(),
      ],
    );

    test('sends the company flag, its number, and its named owners', () {
      final json = keyPeoplePayload([corp]).single;
      expect(json['isCorporate'], isTrue);
      expect(json['registrationNumber'], 'RC123456');
      expect(json['owners'], [
        {'name': 'Jane Doe', 'ownershipPct': 75.0, 'country': 'GB'},
      ]);
    });

    test('never sends the applicant themselves as a company', () {
      // A company cannot be the person filling in the form.
      final json = keyPeoplePayload([corp], applicantIndex: 0).single;
      expect(json['isApplicant'], isTrue);
      expect(json.containsKey('isCorporate'), isFalse);
      expect(json.containsKey('owners'), isFalse);
    });

    test('sends nothing corporate for a person', () {
      final json = keyPeoplePayload([corp.copyWith(isCorporate: false)]).single;
      expect(json.containsKey('isCorporate'), isFalse);
      expect(json.containsKey('registrationNumber'), isFalse);
    });
  });

  group('looksCorporate', () {
    test('recognises a company from a trailing designator', () {
      expect(looksCorporate('Acme Holdings Ltd'), isTrue);
      expect(looksCorporate('ACCESS HOLDINGS  PLC'), isTrue);
    });

    test('leaves a person whose given name reads corporate alone', () {
      // "Trust" and "Grace" are ordinary Nigerian given names, so only a
      // designator at the END of a name counts.
      expect(looksCorporate('Trust Chukwu'), isFalse);
      expect(looksCorporate('Bola Owner'), isFalse);
    });
  });
}
