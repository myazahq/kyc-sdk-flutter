# myaza_kyc_sdk_flutter

Flutter SDK for Myaza KYC — identity verification (ID capture, document scan, and on-device liveness) that talks to the Myaza KYC API.

## Installation

Add the dependency to your `pubspec.yaml`:

```yaml
dependencies:
  myaza_kyc_sdk_flutter: ^2.0.0
```

Then run `flutter pub get`.

## Requirements

The SDK runs face detection **on-device** (Apple Vision on iOS, Google ML Kit on
Android) and uses the camera, so it has native platform minimums:

| Requirement | Minimum |
| --- | --- |
| **Flutter** | **3.27** (Dart **3.6**) |
| **iOS** deployment target | **13.0** |
| **Android** `minSdkVersion` | **21** (Android 5.0) · `compileSdk` 34 |

> ML Kit is pulled **Android-only** (native Gradle) — there is no cross-platform
> ML Kit iOS pod, so the SDK builds and runs on Apple-Silicon iOS simulators.

### Platform setup

The SDK needs **camera** permission on both platforms (there is **no** microphone
permission — voice guidance is text-to-speech output only).

- **iOS** — add to `ios/Runner/Info.plist`:
  ```xml
  <key>NSCameraUsageDescription</key>
  <string>We use the camera to photograph your ID and capture a live selfie.</string>
  ```
  Set the iOS deployment target to **13.0+** (`ios/Podfile`: `platform :ios, '13.0'`).

- **Android** — add to `android/app/src/main/AndroidManifest.xml`:
  ```xml
  <uses-permission android:name="android.permission.CAMERA" />
  <uses-permission android:name="android.permission.INTERNET" />
  ```
  Ensure `minSdkVersion` is **21** or higher in `android/app/build.gradle`.

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
      success: const KYCSuccessContent(
        title: "You're all set, {firstName}!",
        description: "We'll email you once your verification is reviewed.",
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
| `apiKey`                | `String`                | —                     | **Required.** Sent as `Authorization: Bearer`. The **environment is derived from the key prefix** (`pk_test_…` → sandbox, `pk_live_…` → production); an unrecognized prefix throws. |
| `country`               | `Country`               | —                     | **Required.** Country whose ID types are offered.                                                               |
| `idTypes`               | `List<IdType>?`         | all for country       | Subset of ID types to offer. `null` shows all for `country`.                                                    |
| `enableSelfie`          | `bool`                  | `true`                | Capture a selfie during liveness.                                                                               |
| `enableDocumentCapture` | `bool`                  | `true`                | Enable the document-scan step for document IDs.                                                                 |
| `allowDocumentUpload`   | `bool`                  | `true`                | Allow picking a document photo from the device gallery as an alternative to the camera. `false` hides the "upload instead" option (still offered on the camera-permission-denied screen as an escape hatch). |
| `enableLiveness`        | `bool`                  | `true`                | Run the liveness challenge step. Server can disable it per ID type.                                             |
| `voiceGuidance`         | `VoiceGuidanceConfig`   | enabled (`en-US`)     | Spoken liveness instructions (accessibility, TTS **output** — no microphone). `VoiceGuidanceConfig.off` mutes it; `VoiceGuidanceConfig(language: 'fr-FR')` sets the voice. See [Robustness & error handling](#robustness--error-handling). |
| `appearance`            | `MyazaKYCAppearance?`   | brand defaults        | Brand & theme the flow — colors, logo, light/dark. See [Appearance & theming](#appearance--theming).            |
| `consent`               | `KYCConsentContent?`    | built-in copy         | Override the consent/welcome screen `title` and `description`. See [Consent screen copy](#consent-screen-copy). |
| `success`               | `KYCSuccessContent?`    | built-in copy         | Override the success/submitted screen `title` and `description`. See [Success screen copy](#success-screen-copy). |
| `metadata`              | `Map<String, dynamic>?` | —                     | Forwarded with every verify request.                                                                            |
| `livenessConfig`        | `LivenessConfig?`       | 2 challenges, 8s each | Tune challenge count, pool, timeout, avatar.                                                                    |
| `userData`              | `UserData?`             | —                     | Pre-fills the user's details.                                                                                   |

## Environment

There is **no `environment` field** — the SDK derives the environment (and the
base URL) from the API key prefix, the single source of truth:

| Key prefix | Environment | Base URL |
|---|---|---|
| `pk_test_…` / `sk_test_…` | sandbox | `https://trust.myaza.app` |
| `pk_live_…` / `sk_live_…` | production | `https://trust.myaza.app` |

An unrecognized or malformed key throws an `ArgumentError` from `MyazaKYC.show()`
(it never silently defaults).

## Callbacks

Passed to `MyazaKYC.show()` alongside `config`:

| Callback   | Type                           | Description                                                                                                          |
| ---------- | ------------------------------ | -------------------------------------------------------------------------------------------------------------------- |
| `onSubmit` | `void Function(KYCSubmission)` | Called when the server accepts the verification. `status` is always `'pending'`.                                     |
| `onError`  | `void Function(KYCError)`      | Called for **technical** errors only — receives a typed [`KYCError`](#robustness--error-handling) (`code` + `message`). Verification outcomes don't come through here. |
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

## Success screen copy

After the user submits, the final screen shows a confirmation heading and description. Override either through the `success` field:

| Field         | Type      | Description                                                                |
| ------------- | --------- | ------------------------------------------------------------------------- |
| `title`       | `String?` | Heading. Defaults to `Verification Submitted!`.                           |
| `description` | `String?` | Sub-text under the heading. Defaults to the built-in "submitted for review" copy. |

Both fields support the same `{firstName}` / `{lastName}` tokens as `consent`, replaced with the values from `userData` (empty string when absent).

```dart
success: const KYCSuccessContent(
  title: "You're all set, {firstName}!",
  description: "We'll email you once your verification is reviewed.",
),
```

## Robustness & error handling

The SDK is resilient to flaky networks, denied permissions, and poor capture
conditions, and reports technical failures through `onError` with a typed `code`.

### Typed errors (`onError`)

`onError` receives a `KYCError` with a `code`, a human-readable `message`, and
optional `details`. The codes are **identical to the React SDK**:

```dart
onError: (KYCError error) {
  switch (error.code) {
    case 'camera_permission_denied': /* ask the user to allow the camera */ break;
    case 'insufficient_credits':     /* error.details = { required, balance, currency } */ break;
    case 'network_error':
    case 'upload_failed':            /* shown only after automatic retries */ break;
  }
},
```

| `code`                     | When it fires                                                        |
| -------------------------- | ------------------------------------------------------------------- |
| `network_error`            | Connection failure / timeout, **after retries are exhausted**.      |
| `invalid_api_key`          | Server returned `401`.                                              |
| `insufficient_credits`     | Server returned `402`. `details = { required, balance, currency }`. |
| `upload_failed`            | A media upload failed, **after retries are exhausted**.            |
| `camera_permission_denied` | The user denied (or the OS blocks) camera access.                  |
| `feature_disabled`         | Server returned `403` (ID type / feature not enabled for the org). |
| `unknown`                  | Anything else.                                                      |

> Voice guidance is TTS **output** — it never records audio, so there is **no
> microphone permission** and no microphone error code.

### Network resilience

Media uploads and the verify submission are wrapped in exponential-backoff retry
(with jitter), retrying only *transient* failures (network / timeout / `5xx`);
terminal `4xx` surface immediately. The UI shows "Reconnecting… / retrying
(n/3)…" between attempts, and `onError` fires **only after retries are
exhausted** (`upload_failed` for uploads, `network_error` for connectivity).

### Camera permission

If the user denies camera access, the SDK shows a clear "camera access needed"
screen with an **Open Settings** action instead of hanging, and reports
`camera_permission_denied` to `onError`. The document step always keeps a
gallery-upload fallback on that screen as an escape hatch.

### Liveness quality guards

- **Multiple faces** — when more than one face is in frame (reported by Apple
  Vision on iOS / Google ML Kit on Android), the challenge pauses ("Make sure
  only your face is visible") and resumes automatically when only one face
  remains. Guards capture quality and a class of spoofing.
- **Lighting** — too-dark *and* too-bright (glare) conditions are detected live
  during liveness; the SDK shows guidance and discourages auto-capture until
  lighting is acceptable.

## Documentation

Full documentation, configuration options, and webhook setup: **[trust.myaza.co/documentation/sdks](https://trust.myaza.co/documentation/sdks)**.
