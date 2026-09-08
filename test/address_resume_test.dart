import 'package:flutter_test/flutter_test.dart';
import 'package:myaza_kyc_sdk_flutter/myaza_kyc_sdk_flutter.dart';
import 'package:myaza_kyc_sdk_flutter/src/config/address_flow.dart';
import 'package:myaza_kyc_sdk_flutter/src/providers/address_step_order.dart';
import 'package:myaza_kyc_sdk_flutter/src/providers/kyc_state.dart';
import 'package:myaza_kyc_sdk_flutter/src/providers/session_restore.dart';
import 'package:myaza_kyc_sdk_flutter/src/providers/step_order.dart';

// ─── Resuming onto an address step ───────────────────────────────────────────
//
// A snapshot records where the applicant WAS, and the flow they come back to
// need not still offer that screen. Landing on one the order does not contain
// is a dead end: next and back both index into the order, so both become
// no-ops, the bar cannot place them, and the entrance step renders nothing
// once its photo slot is off. Split from address_wiring_test.dart (200-line
// rule), which keeps the step-order seams.

MyazaKYCConfig _individual({String? photo}) => MyazaKYCConfig(
      apiKey: 'pk_test_aaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaa',
      country: 'NG',
      addressCollection: AddressCollectionConfig(enabled: true, photo: photo),
    );

KYCState _withSearch() => const KYCState(
      serverConfig: ServerSdkConfig(
        status: ServerConfigStatus.ready,
        addressSearch: true,
        addressSearchMode: 'basic',
      ),
    );

void main() {
  group('resuming onto an address step', () {
    test('a step the flow still offers is left alone', () {
      expect(
        resumeAddressStep(KYCStep.addressEntrance, kAddressFlowOrder),
        KYCStep.addressEntrance,
      );
    });

    test('a step the flow dropped resumes FORWARD, never back', () {
      // The workflow was republished with its photo slot off, so there is no
      // entrance step any more. A dropped step is a capture the flow is no
      // longer asking for, so the applicant carries on to the review rather
      // than being sent back to re-confirm a pin they already placed. The RN
      // port decided this rule first; the two mirrors must agree.
      final offered = addressStepsFor(_individual(photo: 'off'), _withSearch());
      expect(offered.contains(KYCStep.addressEntrance), isFalse);
      expect(resumeAddressStep(KYCStep.addressEntrance, offered),
          KYCStep.addressReview);
    });

    test('a dropped FIRST step falls forward to the pin', () {
      // Nothing sits before the search, and the pin is where its own "place a
      // pin on the map instead" was taking them anyway.
      final offered = addressStepsFor(_individual(), const KYCState());
      expect(offered.contains(KYCStep.addressSearch), isFalse);
      expect(resumeAddressStep(KYCStep.addressSearch, offered),
          KYCStep.addressCollection);
    });

    test('a flow with no address steps at all reports nothing', () {
      expect(resumeAddressStep(KYCStep.addressReview, const []), isNull);
    });

    test('a step outside the address flow is never clamped onto one', () {
      // The clamp ranks the saved step against the address order. A step that
      // is not in it ranks nowhere, and answering "the pin" would teleport an
      // applicant out of whatever screen they were actually on.
      expect(
        resumeAddressStep(KYCStep.consent, const [KYCStep.addressCollection]),
        KYCStep.consent,
      );
    });

    test('the restore lands somewhere the order can place', () {
      // The defect this closes: restored onto address-entrance with the photo
      // slot off, the applicant met a blank screen whose Continue was a no-op,
      // a dead back arrow and no progress bar.
      final config = _individual(photo: 'off');
      final state = restoredState(
        const KYCState(),
        {
          'step': 'address-entrance',
          'mediaIds': const {},
          'data': {
            'address': {'lat': 6.4281, 'lng': 3.4219},
          },
        },
        offeredAddressSteps: addressStepsFor(config, const KYCState()),
      );

      // Forward rule: the dropped entrance resumes onto the review, and the
      // review is a step the real order contains.
      expect(state.currentStep, KYCStep.addressReview);
      expect(buildStepOrder(config, state).indexOf(state.currentStep),
          greaterThan(-1));
      expect(state.address?.lat, 6.4281,
          reason: 'the placed pin is work done and survives the resume');
    });

    test('a caller that cannot say what is offered changes nothing', () {
      // An empty list means "unknown", not "none". Treating the two alike
      // would move an applicant off a perfectly good step.
      final state = restoredState(const KYCState(), {
        'step': 'address-review',
        'mediaIds': const {},
        'data': {
          'address': {'lat': 6.4281, 'lng': 3.4219},
        },
      });
      expect(state.currentStep, KYCStep.addressReview);
    });

    test('non-address steps are untouched by the clamp', () {
      final state = restoredState(
        const KYCState(),
        {'step': 'consent', 'mediaIds': const {}, 'data': const {}},
        offeredAddressSteps: const [KYCStep.addressCollection],
      );
      expect(state.currentStep, KYCStep.consent);
    });
  });
}
