import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:myaza_kyc_sdk_flutter/myaza_kyc_sdk_flutter.dart';
import 'package:myaza_kyc_sdk_flutter/src/config/theme.dart';
import 'package:myaza_kyc_sdk_flutter/src/providers/kyc_provider.dart';
import 'package:myaza_kyc_sdk_flutter/src/services/api_service.dart';
import 'package:myaza_kyc_sdk_flutter/src/providers/kyc_state.dart'
    show ServerConfigStatus, ServerSdkConfig;
import 'package:myaza_kyc_sdk_flutter/src/screens/applicant_role_screen.dart';
import 'package:myaza_kyc_sdk_flutter/src/screens/business_details_screen.dart';
import 'package:myaza_kyc_sdk_flutter/src/screens/business_documents_screen.dart';
import 'package:myaza_kyc_sdk_flutter/src/screens/business_key_people_screen.dart';

// ─── KYB screens ──────────────────────────────────────────────────────────────
//
// The gating logic has its own unit tests; this pins the part those can't reach
// — that each screen actually BUILDS, and that the Continue button's enabled
// state tracks the workflow's requirements. A disabled-forever Continue (or a
// screen that throws in build) is the failure mode that only shows up on a
// device, which is exactly what these are here to catch.

/// A network that never happens: the notifier now also mints an attempt
/// session at launch, and a live dio request in a widget test is a pending
/// timer at teardown. The stub answers instantly, from the same seam a real
/// mount builds its client behind.
class _StubApi extends KYCApiService {
  _StubApi() : super(baseUrl: 'http://stub', apiKey: 'pk_test_stub');

  @override
  Future<SessionStartResponse> startSession({
    String? externalUserId,
    String? workflowId,
    String? deviceRef,
  }) async =>
      const SessionStartResponse(sessionId: 'hs_test', resumed: false);

  @override
  Future<void> saveProgress(String sessionId, Map<String, dynamic> progress) async {}

  @override
  Future<BusinessSelectResponse> businessSelect({
    required String sessionId,
    required String country,
    required String registrationNumber,
    String? subdivisionCode,
    String? registrationName,
    String? product,
  }) async =>
      const BusinessSelectResponse(checked: false, found: false);

  @override
  Future<BusinessSearchResponse> businessSearch({
    required String country,
    required String query,
    String? subdivisionCode,
    int? limit,
  }) async =>
      const BusinessSearchResponse(results: []);

  @override
  Future<BusinessRegionsResponse> businessRegions(String country) async =>
      const BusinessRegionsResponse();
}

Widget host(MyazaKYCConfig config, Widget child) => ProviderScope(
      overrides: [
        kycConfigProvider.overrideWithValue(config),
        kycApiServiceProvider.overrideWithValue(_StubApi()),
        // Preloading the server config is what a real workflow mount does, and
        // it skips the /api/kyc/config fetch — without it the notifier fires a
        // live dio request and the test ends with a pending timer.
        preloadedServerConfigProvider.overrideWithValue(
          const ServerSdkConfig(status: ServerConfigStatus.ready),
        ),
      ],
      child: MaterialApp(
        theme: ThemeData(extensions: const [MyazaColorScheme.light]),
        home: Scaffold(
          body: SingleChildScrollView(
            child: SizedBox(width: 390, child: child),
          ),
        ),
      ),
    );

MyazaKYCConfig config(Map<String, dynamic> businessJson) => MyazaKYCConfig(
      apiKey: 'pk_test_aaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaa',
      country: 'NG',
      workflowId: 'wf_test',
      subjectType: 'business',
      business:
          WorkflowBusinessConfig.fromJson({'country': 'NG', ...businessJson}),
    );

/// The screen's primary action (always the last MyazaButton on these screens).
bool continueEnabled(WidgetTester tester) => buttonEnabled(tester, 'Continue');

/// The details phase's primary action — the button renames once the register
/// has been asked, so "continue" means confirming what it said.
bool continueEnabled2(WidgetTester tester) =>
    buttonEnabled(tester, 'Confirm details & continue');

/// Whether the last MyazaButton with [label] currently has an onPressed.
bool buttonEnabled(WidgetTester tester, String label) {
  final buttons = tester
      .widgetList<MyazaButton>(find.byType(MyazaButton))
      .where((b) => b.label == label);
  return buttons.last.onPressed != null;
}

void main() {
  group('BusinessDetailsScreen', () {
    testWidgets('renders and gates Continue on the registration number',
        (tester) async {
      await tester.pumpWidget(host(config({}), const BusinessDetailsScreen()));
      await tester.pump();

      // The pick phase opens on the search; nothing is chosen yet.
      expect(find.widgetWithText(TextField, 'Search by company name'),
          findsOneWidget);
      expect(continueEnabled(tester), isFalse);

      // Manual entry is the escape hatch to the details phase, where the
      // number is typed rather than searched for.
      await tester.tap(find.text('Enter the details myself'));
      await tester.pumpAndSettle();
      expect(continueEnabled2(tester), isFalse);

      await tester.enterText(
          find.widgetWithText(TextField, 'e.g. RC0000000'),
          'RC0000001');
      await tester.pump();
      expect(continueEnabled2(tester), isTrue);
    });

    testWidgets('a required company field blocks Continue until filled',
        (tester) async {
      await tester.pumpWidget(host(
        config({
          'companyInfo': {'address': 'required'},
        }),
        const BusinessDetailsScreen(),
      ));
      await tester.pump();

      // Company fields live on the DETAILS phase; manual entry gets there.
      await tester.tap(find.text('Enter the details myself'));
      await tester.pumpAndSettle();

      // Labels are Text.rich (name + a " *" / " (optional)" suffix span), so
      // match on the substring rather than the exact node text.
      expect(find.textContaining('Registered address'), findsOneWidget);
      await tester.enterText(
          find.widgetWithText(TextField, 'e.g. RC0000000'),
          'RC0000001');
      await tester.pump();
      // The number alone isn't enough — the required address still blocks.
      expect(continueEnabled2(tester), isFalse);

      await tester.enterText(
          find.widgetWithText(TextField, 'e.g. 12 Marina Road, Lagos'),
          '12 Marina Road, Lagos');
      await tester.pump();
      expect(continueEnabled2(tester), isTrue);
    });

    testWidgets('collectCompanyInfo: false hides the whole section',
        (tester) async {
      await tester.pumpWidget(host(
        config({'collectCompanyInfo': false}),
        const BusinessDetailsScreen(),
      ));
      await tester.pump();
      // Even on the details phase, where the section would live.
      await tester.tap(find.text('Enter the details myself'));
      await tester.pumpAndSettle();
      expect(find.text('Company information'), findsNothing);
      expect(find.textContaining('Registered address'), findsNothing);
    });

    testWidgets('a malformed company email blocks Continue', (tester) async {
      await tester.pumpWidget(host(config({}), const BusinessDetailsScreen()));
      await tester.pump();

      await tester.tap(find.text('Enter the details myself'));
      await tester.pumpAndSettle();
      await tester.enterText(
          find.widgetWithText(TextField, 'e.g. RC0000000'),
          'RC0000001');
      await tester.enterText(
          find.widgetWithText(TextField, 'hello@company.com'), 'not-an-email');
      await tester.pump();
      expect(continueEnabled2(tester), isFalse);
      expect(find.text('Enter a valid email address.'), findsOneWidget);
    });
  });

  group('BusinessKeyPeopleScreen', () {
    final collect = {
      'keyPeople': {'enabled': true, 'collect': true, 'minEntries': 1},
    };

    testWidgets('minEntries blocks Continue until a valid person is added',
        (tester) async {
      await tester
          .pumpWidget(host(config(collect), const BusinessKeyPeopleScreen()));
      await tester.pump();

      expect(find.text('List at least 1 person to continue.'), findsOneWidget);
      expect(continueEnabled(tester), isFalse);

      // The step is SECTIONED now, so the add tile belongs to a section
      // rather than the list as a whole. A person added here starts wearing
      // that section's hat. The FIRST section on purpose: their card then
      // renders above the quick-add chips the later sections offer for them,
      // so `.first` is unambiguously the card.
      await tester.ensureVisible(find.text('Add a beneficial owner'));
      await tester.pumpAndSettle();
      await tester.pumpAndSettle();
      await tester.tap(find.text('Add a beneficial owner'));
      await tester.pumpAndSettle();
      expect(buttonEnabled(tester, 'Add person'), isFalse);

      await tester.enterText(
          find.widgetWithText(TextField, 'e.g. Bola Owner'), 'Bola Owner');
      await tester.pump();
      expect(buttonEnabled(tester, 'Add person'), isTrue);

      await tester.tap(find.text('Add person'));
      await tester.pumpAndSettle();

      // The saved person renders as a summary card in the section they were
      // added to, and is offered as a quick-add chip in the others: sections
      // are VIEWS over one list, so a named person appears wherever they could
      // also belong. Hence findsWidgets, not findsOneWidget.
      expect(find.text('Bola Owner'), findsWidgets);
      expect(continueEnabled(tester), isTrue);
    });

    testWidgets('with no minimum the step is skippable', (tester) async {
      await tester.pumpWidget(host(
        config({
          'keyPeople': {'enabled': true, 'collect': true},
        }),
        const BusinessKeyPeopleScreen(),
      ));
      await tester.pump();
      expect(continueEnabled(tester), isTrue);
    });

    testWidgets('removing a person from the edit sheet drops their card',
        (tester) async {
      await tester
          .pumpWidget(host(config(collect), const BusinessKeyPeopleScreen()));
      await tester.pump();

      await tester.ensureVisible(find.text('Add a beneficial owner'));
      await tester.pumpAndSettle();
      await tester.tap(find.text('Add a beneficial owner'));
      await tester.pumpAndSettle();
      await tester.enterText(
          find.widgetWithText(TextField, 'e.g. Bola Owner'), 'Bola Owner');
      await tester.pump();
      await tester.tap(find.text('Add person'));
      await tester.pumpAndSettle();
      // Their card, plus quick-add chips in the sections they could also join.
      expect(find.text('Bola Owner'), findsWidgets);
      expect(continueEnabled(tester), isTrue);

      // Tapping the card opens the edit sheet; removal lives INSIDE it —
      // never a one-tap delete on the list. `.first` is the card because they
      // were added to the first section; a chip would have granted them a role
      // instead of opening anything.
      await tester.ensureVisible(find.text('Bola Owner').first);
      await tester.pumpAndSettle();
      await tester.tap(find.text('Bola Owner').first);
      await tester.pumpAndSettle();
      await tester.tap(find.text('Remove this person'));
      await tester.pumpAndSettle();

      expect(find.text('Bola Owner'), findsNothing);
      expect(continueEnabled(tester), isFalse);
    });
  });

  group('BusinessDocumentsScreen', () {
    testWidgets('renders one slot per configured type, required marked',
        (tester) async {
      await tester.pumpWidget(host(
        config({
          'documents': {
            'enabled': true,
            'types': [
              {'key': 'incorporation_certificate', 'required': true},
              {'key': 'memart', 'required': true},
              {'key': 'proof_of_address', 'required': true},
            ],
          },
        }),
        const BusinessDocumentsScreen(),
      ));
      await tester.pump();

      // A required slot's label is Text.rich (label + a red " *" span), so the
      // node's text is "<label> *" — match the substring.
      expect(find.textContaining('Certificate of incorporation'),
          findsOneWidget);
      expect(find.textContaining('MEMART / articles of association'),
          findsOneWidget);
      expect(find.textContaining('Proof of business address'), findsOneWidget);
      // Nothing uploaded yet, so all three required slots block Continue.
      expect(continueEnabled(tester), isFalse);
    });

    testWidgets('optional-only slots leave Continue enabled', (tester) async {
      await tester.pumpWidget(host(
        config({
          'documents': {
            'enabled': true,
            'types': [
              {'key': 'tax_document'},
            ],
          },
        }),
        const BusinessDocumentsScreen(),
      ));
      await tester.pump();
      expect(find.text('Tax document'), findsOneWidget);
      expect(continueEnabled(tester), isTrue);
    });
  });

  group('ApplicantRoleScreen', () {
    testWidgets('Continue needs a declared role', (tester) async {
      await tester.pumpWidget(host(
        config({'applicant': {'verification': true}}),
        const ApplicantRoleScreen(),
      ));
      await tester.pump();

      expect(continueEnabled(tester), isFalse);
      expect(find.text('Your role at the business'), findsOneWidget);
    });
  });
}
