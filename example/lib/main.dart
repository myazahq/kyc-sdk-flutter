import 'package:flutter/material.dart';
import 'package:myaza_kyc_sdk_flutter/myaza_kyc_sdk_flutter.dart';

// Credentials come from --dart-define so no real key is ever committed here.
// Against a local kyc-core, pass all three:
//
//   flutter run \
//     --dart-define=MYAZA_API_KEY=pk_dev_... \
//     --dart-define=MYAZA_DEV_SERVER=http://$(ipconfig getifaddr en0):3001 \
//     --dart-define=MYAZA_WORKFLOW_ID=wf_...
//
// The key prefix picks the environment, so MYAZA_DEV_SERVER is read only by a
// `pk_dev_*` key. A `pk_test_*` key targets staging and ignores it, which is
// why the placeholder default below cannot reach a machine on your desk.
const String kApiKey = String.fromEnvironment(
  'MYAZA_API_KEY',
  defaultValue: 'pk_test_xxxxxxxxxxxxxxxxxxxxxxxx',
);
const String kDevServer = String.fromEnvironment('MYAZA_DEV_SERVER');
const String kWorkflowId = String.fromEnvironment('MYAZA_WORKFLOW_ID');

void main() => runApp(const ExampleApp());

class ExampleApp extends StatelessWidget {
  const ExampleApp({super.key});

  @override
  Widget build(BuildContext context) {
    return const MaterialApp(
      title: 'Myaza Identity Example',
      debugShowCheckedModeBanner: false,
      home: HomeScreen(),
    );
  }
}

class HomeScreen extends StatelessWidget {
  const HomeScreen({super.key});

  void _startVerification(BuildContext context) {
    // On-device liveness ships inside the SDK and is on by default — no setup
    // needed. The flow uploads media and submits, then returns immediately;
    // the verification result is delivered asynchronously via webhook.
    MyazaKYC.show(
      context: context,
      config: MyazaKYCConfig(
        // The environment is derived from the key prefix — a `pk_test_*` key
        // targets staging automatically (no `environment` parameter).
        apiKey: kApiKey,
        devUrl: kDevServer.isEmpty ? null : kDevServer,
        workflowId: kWorkflowId.isEmpty ? null : kWorkflowId,
        // A workflow declares its own countries and ID types, so these are
        // omitted when one is set. Passing them anyway narrows a multi-region
        // flow to this hardcoded list: such a flow keeps its ID types per
        // country and leaves the top-level list unset, and the merge treats
        // "unset" as "the flow did not define it" and keeps the prop.
        country: kWorkflowId.isEmpty ? 'NG' : null,
        idTypes: kWorkflowId.isEmpty ? const ['bvn', 'nin', 'passport'] : null,
        enableSelfie: true,
        enableDocumentCapture: true,
        enableLiveness: true,
        appearance: const MyazaKYCAppearance(
          companyName: 'Myaza',
          theme: MyazaThemeMode.light,
        ),
        metadata: const {'userId': 'usr_123'},
      ),
      onSubmit: (KYCSubmission submission) {
        // Fires once the server accepts the submission. `status` is always
        // 'pending' here — the final outcome arrives later via webhook (or by
        // polling GET /api/kyc/status/:verificationId).
        debugPrint('Submitted: ${submission.verificationId}');
      },
      onError: (KYCError error) {
        // Technical errors only (network / invalid key / insufficient credits /
        // upload). Verification *failures* never come through here.
        debugPrint('Error (${error.code}): ${error.message}');
      },
      onClose: () => debugPrint('KYC closed'),
    );
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text('Myaza KYC Example')),
      body: Center(
        child: FilledButton(
          onPressed: () => _startVerification(context),
          child: const Text('Verify Identity'),
        ),
      ),
    );
  }
}
