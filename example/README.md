# myaza_kyc_sdk_flutter example

A minimal example showing how to launch the Myaza KYC flow.

```dart
import 'package:myaza_kyc_sdk_flutter/myaza_kyc_sdk_flutter.dart';

MyazaKYC.show(
  context: context,
  config: const MyazaKYCConfig(
    apiKey: 'pk_test_...',                 // sandbox key while integrating
    country: Country.NG,
    idTypes: [IdType.bvn, IdType.nin, IdType.passport],
    enableSelfie: true,
    enableDocumentCapture: true,
    enableLiveness: true,
  ),
  onSubmit: (submission) {
    // status is always 'pending'; the result arrives later via webhook
    // (or poll GET /api/kyc/status/:verificationId).
  },
  onError: (error) {
    // technical errors only (network / 401 / 402 / upload)
  },
  onClose: () {},
);
```

See [`lib/main.dart`](lib/main.dart) for the full runnable sample.
