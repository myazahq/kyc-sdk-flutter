import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../config/theme.dart';
import '../../providers/kyc_provider.dart';
import '../../providers/kyc_state.dart';
import 'address_flow_controller.dart';
import 'address_intro_gate.dart';

// ─── What every address step shares ──────────────────────────────────────────
//
// One controller per screen (the ADDRESS itself lives in KYCState, so only the
// transient flags are local), the presence primer on the flow's first step,
// and the two affordances every step below the entrance carries: the error
// line and "Skip for now".
//
// The header (title, description, back arrow) is NOT here: it lives outside
// the step in the sheet chrome, driven by the step order, so back navigation
// is ordinary step navigation rather than something each screen re-invents.

mixin AddressFlowScaffold<T extends ConsumerStatefulWidget> on ConsumerState<T> {
  late final AddressFlowController flow = AddressFlowController(ref);

  /// The step this screen IS. Only the flow's first step shows the primer.
  KYCStep get step;

  /// The screen below the primer.
  Widget buildBody(BuildContext context);

  @override
  void dispose() {
    flow.dispose();
    super.dispose();
  }

  /// The flow error, when one is standing.
  Widget buildError(BuildContext context) {
    final message = flow.error;
    if (message == null) return const SizedBox.shrink();
    return Padding(
      padding: const EdgeInsets.only(top: MyazaSpacing.sm),
      child: Text(message,
          style: context.myazaText.bodySmall
              .copyWith(color: MyazaColors.error)),
    );
  }

  /// "Skip for now", offered unless the workflow requires a pin.
  ///
  /// It leaves the WHOLE address flow, not just this step: an applicant who
  /// declines to place a pin has not asked to be shown the next screen about
  /// placing one.
  Widget buildSkip(BuildContext context) {
    if (flow.cfg?.requirePin == true) return const SizedBox.shrink();
    final colors = context.myazaColors;
    // RN's geometry: `md` above, `sm` of tap padding either side of the line,
    // no Material button chrome around it.
    return Padding(
      padding: const EdgeInsets.only(top: MyazaSpacing.md),
      child: Center(
        child: Semantics(
          button: true,
          label: 'Skip for now',
          child: InkWell(
            onTap: flow.exitForward,
            borderRadius: BorderRadius.circular(MyazaRadius.xs),
            child: Padding(
              padding: const EdgeInsets.symmetric(
                  vertical: MyazaSpacing.sm, horizontal: MyazaSpacing.sm),
              child: Text(
                'Skip for now',
                style: context.myazaText.bodyMedium.copyWith(
                  color: colors.textSecondary,
                  decoration: TextDecoration.underline,
                  decorationColor: colors.textSecondary,
                ),
              ),
            ),
          ),
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    // Watched here, once, so the whole screen rebuilds when the collected
    // address changes. Everything below reads through the controller.
    ref.watch(kYCNotifierProvider);
    return ListenableBuilder(
      listenable: flow,
      builder: (context, _) {
        final gated = flow.showIntroGate(step);
        // The steps do their mount work (the silent auto-locate, the
        // restored-pin relabel) in a one-shot initState hook that early-returns
        // while the primer is up. The gate closing is only a rebuild of this
        // SAME State object, so nothing re-runs it: a flow whose first step is
        // the pin (KYB always; any deployment without a search backend)
        // dismissed the primer onto a country-centre map with no pin and no
        // recovered label, permanently. Web re-runs its mount effect when the
        // gate flag flips; this transition hook is the Flutter equivalent.
        if (_wasGated && !gated) {
          WidgetsBinding.instance.addPostFrameCallback((_) {
            if (mounted) onGateCleared();
          });
        }
        _wasGated = gated;
        if (gated) {
          return AddressIntroGate(
            onAcknowledge: flow.notifier.markAddressIntroSeen,
            background: flow.cfg?.presenceBackground == true,
          );
        }
        return buildBody(context);
      },
    );
  }

  bool _wasGated = false;

  /// Called once, a frame after the presence primer is dismissed. Steps whose
  /// mount work was skipped while the gate stood override this to run it.
  @protected
  void onGateCleared() {}
}
