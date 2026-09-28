import '../config/document_capture_methods.dart';
import '../config/id_types.dart';
import '../config/kyc_config.dart';
import '../config/proof_of_address.dart';
import '../config/supporting_documents.dart';
import '../i18n/translate.dart';
import '../providers/address_step_order.dart';
import '../providers/kyc_state.dart';
import '../providers/step_order.dart';
import '../screens/contact_verification_channel.dart' show kChannelLabels;
import '../config/address_flow.dart' show kAddressFlowOrder;

// The sheet header's title and description for each step, split from
// myaza_kyc_widget.dart (200-line rule). The customisable ones are catalogue
// texts; the rest (a filled-in value, a count) keep this SDK's wording.

class StepMeta {
  final String title;
  final String? description;
  const StepMeta(this.title, [this.description]);
}

StepMeta _base(KYCStep step, TextFn t, bool business, MyazaKYCConfig c) =>
    switch (step) {
      // Consent and submitted have no header title: the screen owns it.
      KYCStep.consent || KYCStep.submitted => const StepMeta(''),
      KYCStep.idType => StepMeta(t('selectDocument.idType.title'),
          t('selectDocument.idType.description')),
      KYCStep.documentCapture => const StepMeta('Capture Document'),
      KYCStep.idInput => StepMeta(
          'Enter your ID number', t('selectDocument.idInput.description')),
      KYCStep.liveness =>
        StepMeta(t('presence.title'), t('presence.camera.description')),
      KYCStep.contactEmail =>
        StepMeta(t('contact.email.title'), t('contact.email.intro')),
      KYCStep.contactPhone => StepMeta(t('contact.phone.title'),
          "We'll send a one-time code to confirm this number belongs to you."),
      KYCStep.countrySelect => StepMeta(t('selectDocument.country.title'),
          t('selectDocument.country.description')),
      KYCStep.nfc => StepMeta(t('nfc.title'), t('nfc.description')),
      KYCStep.proofOfAddress => StepMeta(t('proofOfAddress.title')),
      KYCStep.addressSearch => StepMeta(
          t('address.search.title'), t('address.search.description')),
      // A KYB flow's pin is the BUSINESS PREMISES.
      KYCStep.addressCollection => StepMeta(
          t(business ? 'address.pin.title.business' : 'address.pin.title'),
          t('address.pin.description')),
      KYCStep.addressEntrance => StepMeta(t('address.entrance.title'),
          t('address.entrance.description.photo')),
      KYCStep.addressReview => StepMeta(
          t(business
              ? 'address.review.title.business'
              : 'address.review.title'),
          t('address.review.description')),
      KYCStep.supportingDocuments => StepMeta(t('supportingDocuments.title')),
      // The questionnaire's own title/description are the older fields.
      KYCStep.questionnaire => StepMeta(
          t('questionnaire.title', legacy: c.questionnaire?.title),
          t('questionnaire.description', legacy: c.questionnaire?.description)),
      KYCStep.businessDetails => StepMeta(t('business.details.title'),
          t('business.details.description')),
      KYCStep.businessKeyPeople =>
        StepMeta(t('keyPeople.title'), t('keyPeople.description')),
      KYCStep.businessDocuments => StepMeta(t('business.documents.title'),
          t('business.documents.description')),
      KYCStep.applicantRole => StepMeta(t('business.applicant.title'),
          t('business.applicant.description')),
    };

/// The header for [step] in the flow's current [state].
StepMeta flowStepMeta(
  KYCStep step, {
  required MyazaKYCConfig config,
  required KYCState state,
  required TextFn t,
  required bool selfieComplete,
}) {
  final isBusiness = config.subjectType == 'business';
  var meta = _base(step, t, isBusiness, config);

  // The entrance step framing street imagery describes THAT, not a camera.
  if (step == KYCStep.addressEntrance && state.addressEntranceFraming) {
    meta = StepMeta(meta.title, t('address.entrance.description.framing'));
  }
  // The ID input step names the ID it wants.
  if (step == KYCStep.idInput && state.selectedIdType != null) {
    meta = StepMeta('Enter your ${state.selectedIdType!.label}', meta.description);
  }
  // The line follows the COUNTS, resolved the way the screen resolves its
  // slots, or the header could name a number the body does not show.
  if (step == KYCStep.supportingDocuments) {
    meta = StepMeta(
      meta.title,
      supportingDocumentsIntro(
        resolveSupportingDocuments(
            config.supportingDocuments, verifiedIdComposites(config, state)),
        t,
      ),
    );
  }
  // The presence primer carries its own heading: blanked like consent's.
  if (kAddressFlowOrder.contains(step) &&
      addressIntroGateShowing(config, state, step)) {
    meta = const StepMeta('');
  }
  // Proof of address states its own recency window, and asks for the name
  // only where the workflow's name rule wants it for the picked kind.
  if (step == KYCStep.proofOfAddress) {
    final poa = config.proofOfAddress;
    final days = poa?.maxAgeDays ?? 90;
    final kind = state.poaDocumentType == null
        ? null
        : PoaDocumentType.tryFromKey(state.poaDocumentType!);
    final nameNeeded = poa == null ||
        poa.namePolicyFor(state.selectedCountry ?? config.country, kind) !=
            PoaNameRule.off;
    meta = StepMeta(
      meta.title,
      'Upload a document that shows your '
      '${nameNeeded ? 'name and home address' : 'home address'}, issued '
      'within the last $days days.',
    );
  }
  if (step == KYCStep.contactEmail || step == KYCStep.contactPhone) {
    meta = _contactMeta(step, meta, config, state);
  }
  if (step == KYCStep.documentCapture) {
    meta = _documentMeta(config, state, t);
  }
  if (step == KYCStep.liveness && selfieComplete) {
    meta = StepMeta(t('presence.review.title'), t('presence.review.description'));
  }
  return meta;
}

/// The contact steps turn their promise ("we'll send a code") into an
/// instruction once a code is out, naming the channel the user picked. Only
/// state raised by THIS step counts: both contact steps are the same screen.
StepMeta _contactMeta(
    KYCStep step, StepMeta meta, MyazaKYCConfig config, KYCState state) {
  final isPhone = step == KYCStep.contactPhone;
  final live = state.contactChannel == (isPhone ? 'phone' : 'email');
  final by = isPhone && live && state.contactVia.isNotEmpty
      ? ' by ${kChannelLabels[state.contactVia] ?? state.contactVia}'
      : '';
  if (live && state.contactDestination.isNotEmpty) {
    final length = (isPhone
            ? config.phoneVerification?.codeLength
            : config.emailVerification?.codeLength) ??
        6;
    return StepMeta(meta.title,
        'Enter the $length-digit code we sent to ${state.contactDestination}$by.');
  }
  if (isPhone) {
    return StepMeta(meta.title,
        "We'll send a one-time code$by to confirm this number belongs to you.");
  }
  return meta;
}

/// Each phase of the document step is its own catalogue text, chosen the way
/// the web SDK chooses (front of a two-sided ID, a single side, the preview,
/// the back, the review), so a workflow can reword each whole.
StepMeta _documentMeta(MyazaKYCConfig config, KYCState state, TextFn t) {
  final doc = {'document': state.selectedIdType?.label ?? 'Document'};
  final twoSided = state.selectedIdType?.scanSides == ScanSides.frontAndBack;
  final up = documentCaptureMethodsFor(config).uploadOnly;
  final (title, description) = switch (state.docReviewPhase) {
    'front_preview' => up
        ? ('frontAdded', 'frontAdded')
        : ('frontCaptured', 'frontCaptured'),
    'camera_back' => up ? ('uploadBack', 'uploadBack') : ('scanBack', 'scanBack'),
    'review' => (
        'review',
        twoSided ? (up ? 'reviewBothAdded' : 'reviewBoth') : 'review'
      ),
    _ => twoSided
        ? (up ? ('uploadFront', 'uploadFront') : ('scanFront', 'scanFront'))
        : (up ? ('upload', 'upload') : ('capture', 'capture')),
  };
  return StepMeta(t('uploadDocument.title.$title', vars: doc),
      t('uploadDocument.description.$description', vars: doc));
}
