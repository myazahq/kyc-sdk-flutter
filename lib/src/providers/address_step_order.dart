import '../config/address_collection.dart';
import '../config/address_flow.dart';
import '../config/kyc_config.dart';
import 'kyc_state.dart';

// ─── Resolving the address flow against this mount ───────────────────────────
//
// The pure model lives in config/address_flow.dart; this is the one place that
// feeds it the config and server facts. Split from step_order.dart so both
// files stay inside the 200-line rule.

/// The address flow's options for [config] + [state].
///
/// `hasGoogleKey` and `previewMode` are hard-false: the Google key describes
/// an in-document BROWSER surface and the builder preview is a dashboard
/// surface, and a native mount is neither. Street View reaches a phone the way
/// the framed map does, through the hosted /embed/street-view page in a
/// WebView on the app grant, which is what `hasStreetViewFrame` says: the
/// server minted a maps frame URL for this mount.
AddressFlowOptions addressFlowOptionsFor(
  MyazaKYCConfig config,
  KYCState state,
) =>
    addressFlowOptions(
      photo: addressPhotoMode(config.addressCollection),
      streetView: config.addressCollection?.streetView,
      // A STUBBED mount calls no vendor, so the search screen would offer a
      // box nothing can answer: drop the step, exactly as the RN wrapper does.
      serverSearch: state.serverConfig.addressSearch &&
          !addressVendorsStubbed(environment: state.serverConfig.environment),
      previewMode: false,
      hasGoogleKey: false,
      hasStreetViewFrame: state.serverConfig.mapsFrameUrl != null,
    );

/// The address steps this mount offers, in order.
///
/// KYB collapses to the single premises step: its pin and directions ARE the
/// capture there, and the business flow has its own section rhythm.
List<KYCStep> addressStepsFor(MyazaKYCConfig config, KYCState state) {
  // The real step order gates the whole address block on `enabled`; this list
  // must agree, or a resume can be "clamped" onto a step the order does not
  // contain and both Continue and Back become no-ops (the stranded dead end
  // resumeAddressStep exists to prevent).
  if (config.addressCollection?.enabled != true) return const [];
  return config.subjectType == 'business'
      ? const [KYCStep.addressCollection]
      : addressFlowSteps(addressFlowOptionsFor(config, state));
}

/// Where a resumed session should land when its saved step was an address one.
///
/// A snapshot records where the applicant WAS, and the flow they come back to
/// need not still offer that screen: the workflow's photo slot was turned off,
/// or the platform stopped serving address search. Landing on a step the order
/// does not contain is a dead end, not a rough edge — `nextStep` and
/// `previousStep` both index into the order, so both become no-ops, the step
/// counter cannot place the applicant, and the entrance step in particular
/// renders nothing at all once its photo slot is off. A blank screen, a dead
/// back arrow, and no way forward.
///
/// The rule is FORWARD, mirrored from the RN port after the two drifted in
/// opposite directions: a step the flow no longer has is a capture it is no
/// longer asking for, so the applicant carries on to the next offered screen
/// rather than being sent back to redo work they had already finished. A
/// session saved on the entrance step whose photo slot was since switched off
/// resumes on the review, not back on a pin they already placed.
///
/// Returns null when the flow offers no address steps at all, leaving the
/// caller to route the applicant out of the address flow entirely.
KYCStep? resumeAddressStep(KYCStep saved, List<KYCStep> offered) {
  if (offered.contains(saved)) return saved;
  if (offered.isEmpty) return null;
  final savedRank = kAddressFlowOrder.indexOf(saved);
  // A step outside the address flow has no rank to walk from, and the
  // fallback below would answer with an address screen. Nothing about a
  // consent or liveness step says the applicant belongs in the address flow,
  // so say so here rather than relying on every caller to check first.
  if (savedRank < 0) return saved;
  for (var i = savedRank + 1; i < kAddressFlowOrder.length; i += 1) {
    final step = kAddressFlowOrder[i];
    if (offered.contains(step)) return step;
  }
  // Nothing after it either: the last screen the flow does have (a KYB resume
  // onto a review it never renders belongs on its premises pin).
  return offered.last;
}

/// Whether the presence primer is standing in front of [step].
///
/// Read twice — by the step's body and by the sheet header that would
/// otherwise title the primer with the step's own heading — so it is ONE
/// function rather than two conditions that can drift apart.
bool addressIntroGateShowing(
  MyazaKYCConfig config,
  KYCState state,
  KYCStep step,
) =>
    config.addressCollection?.presenceEnabled == true &&
    !state.addressIntroSeen &&
    step == addressStepsFor(config, state).first;
