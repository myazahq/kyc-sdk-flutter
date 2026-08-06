import 'package:flutter/material.dart';

import '../config/kyc_config.dart';
import '../config/theme.dart';
import '../config/workflow_merge.dart';
import '../providers/kyc_state.dart';
import '../services/api_service.dart';
import '../utils/resolve_url.dart';
import 'myaza_pulse_loader.dart';

// ─── Workflow gate ────────────────────────────────────────────────────────────
//
// Resolve-before-mount: when a config carries a `workflowId`, the SDK resolves
// the published flow (GET /api/kyc/workflows/:id) BEFORE the flow mounts, merges
// it over the consumer's props (flow wins), and hands back an effective config
// plus a preloaded server config (idTypes + branding) so /config is skipped.
// This mirrors the web SDK's WorkflowGate and keeps `MyazaKYCConfig.country`
// non-null by mount time (the flow supplies it when the consumer omits it).

/// The merged effective config + the preloaded server config to inject.
class WorkflowGateResult {
  final MyazaKYCConfig config;
  final ServerSdkConfig serverConfig;

  const WorkflowGateResult({required this.config, required this.serverConfig});
}

/// Resolves the workflow and returns the merged result. Throws [KYCError] on
/// failure (mapped so 401 → `invalid_api_key`, everything else →
/// `invalid_workflow`). Core used by both entry points below.
Future<WorkflowGateResult> resolveWorkflowResult(MyazaKYCConfig config) async {
  final api = KYCApiService(
    baseUrl: resolveBaseUrl(config.apiKey, devUrl: config.devUrl),
    apiKey: config.apiKey,
  );
  try {
    final res = await api.workflow(config.workflowId!);
    return WorkflowGateResult(
      config: mergeWorkflowIntoConfig(config, res.config),
      serverConfig: ServerSdkConfig(
        status: ServerConfigStatus.ready,
        idTypes: res.idTypes,
        environment: res.environment,
        branding: res.branding,
      ),
    );
  } on KYCApiException catch (e) {
    throw KYCError(
      code: e.statusCode == 401 ? 'invalid_api_key' : 'invalid_workflow',
      message: e.message ??
          'This verification workflow could not be loaded. Please contact support.',
    );
  } catch (_) {
    throw const KYCError(
      code: 'invalid_workflow',
      message: 'This verification workflow could not be loaded.',
    );
  }
}

/// Shows a modal loading barrier while resolving, then returns the merged
/// result — or null when resolution failed (the error is reported to [onError]
/// and a blocking error dialog is shown). Used by `MyazaKYC.show`.
Future<WorkflowGateResult?> resolveWorkflowBeforeMount(
  BuildContext context,
  MyazaKYCConfig config,
  void Function(KYCError)? onError,
) async {
  final outcome = await showDialog<_GateOutcome>(
    context: context,
    barrierDismissible: false,
    builder: (_) => _WorkflowResolveDialog(config: config),
  );
  if (outcome == null) return null;
  if (outcome.error != null) {
    onError?.call(outcome.error!);
    if (context.mounted) {
      await showDialog<void>(
        context: context,
        builder: (_) => _WorkflowErrorDialog(error: outcome.error!),
      );
    }
    return null;
  }
  return outcome.result;
}

// ─── Internals ────────────────────────────────────────────────────────────────

class _GateOutcome {
  final WorkflowGateResult? result;
  final KYCError? error;
  const _GateOutcome({this.result, this.error});
}

class _WorkflowResolveDialog extends StatefulWidget {
  final MyazaKYCConfig config;
  const _WorkflowResolveDialog({required this.config});

  @override
  State<_WorkflowResolveDialog> createState() => _WorkflowResolveDialogState();
}

class _WorkflowResolveDialogState extends State<_WorkflowResolveDialog> {
  @override
  void initState() {
    super.initState();
    _resolve();
  }

  Future<void> _resolve() async {
    try {
      final result = await resolveWorkflowResult(widget.config);
      if (mounted) Navigator.of(context).pop(_GateOutcome(result: result));
    } on KYCError catch (e) {
      if (mounted) Navigator.of(context).pop(_GateOutcome(error: e));
    }
  }

  @override
  Widget build(BuildContext context) {
    return const Center(
      child: Card(
        color: Colors.transparent,
        elevation: 0,
        child: Padding(
          padding: EdgeInsets.all(MyazaSpacing.xl),
          child: MyazaPulseLoader(),
        ),
      ),
    );
  }
}

class _WorkflowErrorDialog extends StatelessWidget {
  final KYCError error;
  const _WorkflowErrorDialog({required this.error});

  @override
  Widget build(BuildContext context) {
    return AlertDialog(
      title: const Text('Verification unavailable'),
      content: Text(error.message),
      actions: [
        TextButton(
          onPressed: () => Navigator.of(context).pop(),
          child: const Text('Close'),
        ),
      ],
    );
  }
}
