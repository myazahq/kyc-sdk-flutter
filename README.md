# myaza_kyc_sdk_flutter

Flutter SDK for Myaza KYC — identity verification (ID capture, document scan, and on-device liveness) that talks to the Myaza KYC API.

## Installation

Add the dependency to your `pubspec.yaml`:

```yaml
dependencies:
  myaza_kyc_sdk_flutter: ^1.0.0
```

Then run `flutter pub get`.

## Usage

`MyazaKYC.show()` opens the full modal flow as a bottom sheet.

```dart
import 'package:flutter/material.dart';
import 'package:myaza_kyc_sdk_flutter/myaza_kyc_sdk_flutter.dart';

void startKYC(BuildContext context) {
  MyazaKYC.show(
    context: context,
    config: MyazaKYCConfig(
      apiKey: 'pk_live_xxx',
      country: Country.NG,
      environment: KYCEnvironment.production,
      idTypes: const [IdType.passport, IdType.bvn, IdType.nin, IdType.pvc],
      userData: const UserData(firstName: 'Jane', lastName: 'Doe'),
      enableSelfie: true,
      enableDocumentCapture: true,
      enableLiveness: true,
      appearance: const MyazaKYCAppearance(
        primaryColor: Color(0xFF5645F5),
        companyName: 'Myaza',
        logo: 'default',
        theme: MyazaThemeMode.dark,
      ),
      consent: const KYCConsentContent(
        title: 'Welcome, {firstName}',
        description: "A quick check to confirm it's really you.",
      ),
      metadata: const {'userId': 'test_user_123'},
    ),
    onSubmit: (submission) {
      // Fires as soon as the server accepts the request.
      // submission.status is always 'pending' — the result arrives later via
      // webhook to your backend (or poll GET /api/kyc/status/:id).
      debugPrint('Submitted: ${submission.verificationId}');
    },
    onError: (error) {
      // Technical errors only (network / 401 / 402 / upload).
      debugPrint('Error: ${error.code} — ${error.message}');
    },
    onClose: () => debugPrint('KYC closed'),
  );
}
```

## Config (`MyazaKYCConfig`)

| Field                   | Type                    | Default               | Description                                                                                                     |
| ----------------------- | ----------------------- | --------------------- | --------------------------------------------------------------------------------------------------------------- |
| `apiKey`                | `String`                | —                     | **Required.** Sent as `Authorization: Bearer`. `pk_test_*` = sandbox.                                           |
| `country`               | `Country`               | —                     | **Required.** Country whose ID types are offered.                                                               |
| `environment`           | `KYCEnvironment`        | `production`          | Backend the SDK talks to: `staging` or `production`. Base URL is resolved on mount.                             |
| `idTypes`               | `List<IdType>?`         | all for country       | Subset of ID types to offer. `null` shows all for `country`.                                                    |
| `enableSelfie`          | `bool`                  | `true`                | Capture a selfie during liveness.                                                                               |
| `enableDocumentCapture` | `bool`                  | `true`                | Enable the document-scan step for document IDs.                                                                 |
| `enableLiveness`        | `bool`                  | `true`                | Run the liveness challenge step. Server can disable it per ID type.                                             |
| `appearance`            | `MyazaKYCAppearance?`   | brand defaults        | Brand & theme the flow — colors, logo, light/dark. See [Appearance & theming](#appearance--theming).            |
| `consent`               | `KYCConsentContent?`    | built-in copy         | Override the consent/welcome screen `title` and `description`. See [Consent screen copy](#consent-screen-copy). |
| `metadata`              | `Map<String, dynamic>?` | —                     | Forwarded with every verify request.                                                                            |
| `livenessConfig`        | `LivenessConfig?`       | 2 challenges, 8s each | Tune challenge count, pool, timeout, avatar.                                                                    |
| `userData`              | `UserData?`             | —                     | Pre-fills the user's details.                                                                                   |

## Callbacks

Passed to `MyazaKYC.show()` alongside `config`:

| Callback   | Type                           | Description                                                                                                          |
| ---------- | ------------------------------ | -------------------------------------------------------------------------------------------------------------------- |
| `onSubmit` | `void Function(KYCSubmission)` | Called when the server accepts the verification. `status` is always `'pending'`.                                     |
| `onError`  | `void Function(KYCError)`      | Called for **technical** errors only (network, `401`, `402`, upload). Verification outcomes don't come through here. |
| `onClose`  | `void Function()`              | Called when the user closes the flow.                                                                                |

## Appearance & theming

Pass a `MyazaKYCAppearance` to brand the flow. Each override maps onto the SDK's
internal color scheme; unset colors keep the built-in defaults (which differ between
light and dark). Setting `primaryColor` also recolors its derived tints, so the whole
brand family follows.

| Field              | Type             | Description                                                                                 |
| ------------------ | ---------------- | ------------------------------------------------------------------------------------------- |
| `primaryColor`     | `Color?`         | Brand color — buttons, selected states, progress, the shield hero.                          |
| `primaryTextColor` | `Color?`         | Text/icons rendered on top of `primaryColor` (e.g. button labels).                          |
| `accentColor`      | `Color?`         | Subtle fills / selected surfaces.                                                           |
| `backgroundColor`  | `Color?`         | Sheet background.                                                                           |
| `surfaceColor`     | `Color?`         | Cards & panels.                                                                             |
| `borderColor`      | `Color?`         | Borders and input outlines.                                                                 |
| `textColor`        | `Color?`         | Primary text color.                                                                         |
| `companyName`      | `String`         | Shown beside the header logo. Defaults to `'Myaza'`.                                        |
| `logoAsset`        | `String?`        | Local asset path for the logo (`Image.asset`).                                              |
| `logo`             | `String?`        | Network logo URL, or `'default'` to use your org's logo. Takes precedence over `logoAsset`. |
| `theme`            | `MyazaThemeMode` | Initial light/dark mode (defaults to `light`).                                              |

### Logo

The org logo renders as a small circular avatar at the top-left of the sheet,
persistent on every step, alongside `companyName`.

- `logo: 'https://…/logo.png'` — uses that image directly (`Image.network`).
- `logo: 'default'` — pulls your organization's logo configured in the **Myaza dashboard**
  (returned by the server on mount). A broken/absent image simply hides the avatar.
- `logoAsset: 'assets/logo.png'` — uses a bundled asset when no `logo` is given.

```dart
appearance: const MyazaKYCAppearance(
  primaryColor: Color(0xFF0F7B6C),
  primaryTextColor: Color(0xFFFFFFFF),
  surfaceColor: Color(0xFFF4F7F6),
  borderColor: Color(0xFFD7E3E0),
  logo: 'default',
  theme: MyazaThemeMode.light,
),
```

## Consent screen copy

The welcome/consent step shows a heading and a short description. Override either through the `consent` field:

| Field         | Type      | Description                                                                                           |
| ------------- | --------- | ----------------------------------------------------------------------------------------------------- |
| `title`       | `String?` | Heading. Defaults to `Welcome, {firstName}` when a first name is known, else `Identity Verification`. |
| `description` | `String?` | Sub-text under the heading. Defaults to the built-in regulatory copy.                                 |

Both fields support `{firstName}` and `{lastName}` tokens, replaced with the values from `userData` (empty string when absent), so a custom title can still greet the user by name.

```dart
consent: const KYCConsentContent(
  title: 'Welcome, {firstName}',
  description: "We just need to confirm it's really you. This takes about a minute.",
),
```

## Documentation

Full documentation, configuration options, and webhook setup: **[identity.myaza.co/documentation/sdks](https://identity.myaza.co/documentation/sdks)**.
