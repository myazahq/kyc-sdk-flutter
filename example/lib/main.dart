import 'package:flutter/material.dart';
import 'package:kyc_sdk_flutter/kyc_sdk_flutter.dart';

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
      config: const MyazaKYCConfig(
        // While integrating, use a sandbox key (pk_test_*) against staging.
        apiKey: 'pk_test_xxxxxxxxxxxxxxxxxxxxxxxx',
        country: Country.NG,
        environment: KYCEnvironment.staging,
        idTypes: [IdType.bvn, IdType.nin, IdType.passport],
        enableSelfie: true,
        enableDocumentCapture: true,
        enableLiveness: true,
        appearance: MyazaKYCAppearance(
          companyName: 'Myaza',
          theme: MyazaThemeMode.light,
        ),
        metadata: {'userId': 'usr_123'},
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
