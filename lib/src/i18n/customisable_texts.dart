import 'defaults_address.dart';
import 'defaults_capture.dart';
import 'defaults_forms.dart';
import 'defaults_result.dart';
import 'defaults_welcome.dart';

// ─── The customisable texts, as this SDK holds them ──────────────────────────
//
// The shared contract is test/customisable_texts_vectors.json (the web SDK
// writes it): every text a workflow may change, by key. A key means the same
// spot on every SDK; the wording of its default is each SDK's own. Every key
// is either WIRED here (it has a default, and a screen reads it) or NOT SHOWN
// (this SDK has no such spot), never both and never neither, which a test
// holds against the shared file.

/// This SDK's default for each customisable text it shows.
const Map<String, String> kDefaultTexts = {
  ...kWelcomeTextDefaults,
  ...kCaptureTextDefaults,
  ...kAddressTextDefaults,
  ...kFormTextDefaults,
  ...kResultTextDefaults,
};

const _hosted = 'Hosted web pages only; the SDK runs inside the host app.';
const _handoff = 'No desktop-to-phone handoff: this SDK already runs on the phone.';
const _completed =
    'No returning-applicant screen: that is a hosted link reopened after submission.';

/// Customisable texts this SDK has no spot for, with the reason. A workflow's
/// copy for these is simply never drawn here.
const Map<String, String> kNotShownTexts = {
  'welcome.process.uploadDocument': 'The consent list names document capture only; no upload-only line.',
  'contact.code.label': 'The code boxes carry no label above them.',
  'uploadDocument.camera.havingTrouble': 'The camera shows its upload link without a lead-in line.',
  'uploadDocument.upload.addFromGallery': 'The upload card is titled with the side being added.',
  'uploadDocument.flipBanner': 'The back is introduced by the step header, not a banner.',
  'presence.intro.description': 'One header description for the step, the camera one.',
  'result.success.redirectLabel': _hosted,
  'result.success.closeTabNote': _hosted,
  'result.completed.approved.title': _completed,
  'result.completed.approved.title.faceEnrolment': _completed,
  'result.completed.approved.description.individual': _completed,
  'result.completed.approved.description.business': _completed,
  'result.completed.approved.description.address': _completed,
  'result.completed.approved.description.faceEnrolment': _completed,
  'result.completed.approved.description.questionnaire': _completed,
  'result.completed.approved.description.contact': _completed,
  'result.completed.declined.title': _completed,
  'result.completed.declined.description.individual': _completed,
  'result.completed.declined.description.business': _completed,
  'result.completed.declined.description.address': _completed,
  'result.completed.declined.description.faceEnrolment': _completed,
  'result.completed.declined.description.questionnaire': _completed,
  'result.completed.declined.description.contact': _completed,
  'result.completed.actionNeeded.title': _completed,
  'result.completed.actionNeeded.description': _completed,
  'handoff.gate.title': _handoff,
  'handoff.gate.description': _handoff,
  'handoff.gate.description.noCamera': _handoff,
  'handoff.gate.description.mobileOnly': _handoff,
  'handoff.codeLabel': _handoff,
  'handoff.copyLink': _handoff,
  'handoff.continueHere': _handoff,
  'handoff.mobileOnly.title': _handoff,
  'handoff.mobileOnly.description': _handoff,
  'handoff.completed.title': _handoff,
  'handoff.completed.description': _handoff,
  'handoff.sheet.trigger': _handoff,
  'handoff.sheet.title': _handoff,
  'handoff.sheet.description': _handoff,
  'handoff.sheet.stayButton': _handoff,
  'common.back': 'Back is an arrow in the header, with no visible label.',
};

/// The keys a workflow may change; this SDK reads custom copy for these only.
final Set<String> kCustomisableTextKeys = {
  ...kDefaultTexts.keys,
  ...kNotShownTexts.keys,
};
