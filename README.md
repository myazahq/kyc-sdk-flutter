# myaza_kyc_sdk_flutter

Flutter SDK for Myaza KYC — identity verification (ID capture, document scan, and on-device liveness) that talks to the Myaza KYC API.

## Installation

Add the dependency to your `pubspec.yaml`:

```yaml
dependencies:
  myaza_kyc_sdk_flutter: ^2.2.0
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

#### Location (only if your workflow uses Address Intelligence)

Workflows with the **address-collection step** offer "Use my current location"
and can take a one-shot GPS fix at Continue. Both are best-effort — a denied
permission never blocks the flow — but iOS **crashes** on the permission
request if the usage string is missing, so add it whenever your workflow
enables the step:

- **iOS** — `ios/Runner/Info.plist`:
  ```xml
  <key>NSLocationWhenInUseUsageDescription</key>
  <string>Your location helps place the map pin on your address.</string>
  ```
- **Android** — `android/app/src/main/AndroidManifest.xml`:
  ```xml
  <uses-permission android:name="android.permission.ACCESS_COARSE_LOCATION" />
  <uses-permission android:name="android.permission.ACCESS_FINE_LOCATION" />
  ```
  Foreground ("while in use") only — the SDK never tracks in the background.

## Usage

`MyazaKYC.show()` opens the full modal flow as a bottom sheet.

### Recommended — mount a workflow

Build the flow once in the Myaza dashboard as a **workflow**, then mount it by
id. The country, ID types, capture steps, add-ons, branding and copy all come
from the workflow, so changing the flow is a re-publish in the dashboard rather
than an app release and an app-store review.

```dart
import 'package:flutter/material.dart';
import 'package:myaza_kyc_sdk_flutter/myaza_kyc_sdk_flutter.dart';

void startKYC(BuildContext context) {
  MyazaKYC.show(
    context: context,
    config: const MyazaKYCConfig(
      apiKey: 'pk_live_xxx',
      workflowId: 'wf_AbC123dEf456',
      // Runtime data — a workflow is a shared template and cannot carry any of it.
      userId: 'usr_123',
      userData: UserData(firstName: 'Jane', lastName: 'Doe'),
      metadata: {'orderId': 'ord_456'},
    ),
    onSubmit: (submission) => debugPrint('Submitted: ${submission.verificationId}'),
    onError: (error) => debugPrint('Error: ${error.code} — ${error.message}'),
    onClose: () => debugPrint('KYC closed'),
  );
}
```

**`userData` is worth passing.** It is the name you believe the user has, and it
is compared against the name read off their document — that comparison is what
produces `dataMatch` on the verification. It cannot live on the workflow:
`userId`, `userData` and `metadata` are per-user runtime values, and a workflow
is a template shared by every visitor, so these stay in code even when
everything else moves to the dashboard.

### Or configure everything in code

Skip the workflow and pass the flow's shape in `MyazaKYCConfig`. Useful for a
quick start or a single fixed flow; anything you'd change later means an app
release. `country` is any ISO-2 string and `idTypes` are the same kebab-case
keys as the React SDKs — there is no enum.

```dart
import 'package:flutter/material.dart';
import 'package:myaza_kyc_sdk_flutter/myaza_kyc_sdk_flutter.dart';

void startKYC(BuildContext context) {
  MyazaKYC.show(
    context: context,
    config: MyazaKYCConfig(
      apiKey: 'pk_live_xxx',
      country: 'NG',
      idTypes: const ['passport', 'bvn', 'nin', 'pvc'],
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
      userId: 'test_user_123',
      metadata: const {'orderId': 'ord_456'},
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
| `workflowId`            | `String?`               | —                     | **Recommended.** Id of a **published** workflow (`wf_…`) built in the dashboard. Its configuration is resolved on mount and **takes precedence over these fields**; makes `country` optional. Required for [business (KYB)](#business-verification-kyb) verification. |
| `country`               | `String?` (ISO-2)       | —                     | **Required unless `workflowId` is set** (the workflow carries its own country). Any ISO-2 code works (`'NG'`, `'GH'`, …) — the org's grants are enforced server-side. |
| `idTypes`               | `List<String>?`         | all for country       | Subset of ID-type keys to offer (`['bvn', 'passport']` — the same kebab-case keys as the React SDKs). `null` shows all for `country`. |
| `userId`                | `String?`               | —                     | Your own reference for the person or business being verified. Sent with the verification so results correlate back to your record. Not matched against the ID. |
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

## Business verification (KYB)

The SDK can verify a **business** instead of a person — a company-registry
lookup, with no document capture and no liveness.

This is **workflow-driven**: build and publish a business workflow in the Myaza
dashboard, then pass its id as `workflowId`. There is no prop to turn it on — the
SDK reads the subject type from the resolved workflow.

```dart
MyazaKYC.show(
  context: context,
  config: const MyazaKYCConfig(
    apiKey: 'pk_test_xxxxxxxx',
    workflowId: 'wf_xxxxxxxx',    // a PUBLISHED business workflow
    userId: 'usr_123',
    // no `country` — the workflow sets the registry country
  ),
  onSubmit: (submission) => print(submission.verificationId),
  onError: (error) => print('${error.code} — ${error.message}'),
  onClose: () {},
);
```

The steps come from your workflow — you don't configure them here:

| Step | Shown when | What the user does |
| ---- | ---------- | ------------------ |
| Consent | always | Agrees to the business verification |
| Business details | always | Picks the registry country (if the workflow offers several) and the verification product (if it offers several), then enters the registration number — or a TIN, for the TIN product — plus the registered business name and any company details the workflow asks for |
| Directors & owners | workflow collects key people | Lists directors and 25%+ owners (name, role, ownership %, country, email). Each person with an email is sent a link to verify their identity |
| Business documents | workflow requests documents | Uploads each requested document (photo or PDF) — from the photo library, the camera, or Files |
| Verify your identity | workflow requires applicant verification | Declares their role at the business, then verifies their **own** identity with the normal ID + liveness steps |
| Questionnaire | workflow configures one | Answers your custom questions |
| Submitted | always | Sees the confirmation |

Submission works exactly like an individual verification: `onSubmit` fires with a
`verificationId` and `status: 'pending'`, and the outcome arrives later by webhook
or via the status endpoint.

> When the workflow requires applicant verification, the applicant's own identity
> is submitted as a **separate** verification, linked to the business application
> server-side. `onSubmit` reports the **business** `verificationId`.

**Sandbox.** With a `pk_test_…` key only published test registration numbers are
accepted (e.g. `RC0000001`, `RC0000002`); anything else returns a
`Sandbox mode accepts only published test registration numbers` error.

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
| `invalid_workflow`         | The `workflowId` is unknown, unpublished, or misconfigured for this submission. See [Business verification (KYB)](#business-verification-kyb). |
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

## Presence reporting (Address Intelligence)

When a workflow enables presence verification (`addressCollection.presence.enabled`),
the SDK stores the confirmed pin on-device at capture. Call the reporter from your
app on a natural moment (app open works well):

```dart
final result = await MyazaAddressPresence.report(
  apiKey: 'pk_live_…',
  externalUserId: 'user_42', // the same userId the KYC flow ran with
);
// result.reason: reported | noPin | servicesOff | noFix | outsideFence | networkError
```

It never throws and never blocks startup. The geofence is evaluated ON-DEVICE:
only the derived record (calendar day + a night flag) is transmitted, never a
coordinate. A fix outside the fence sends nothing (the server scores presence,
never absence); a mock-location fix is reported flagged. `clearPresencePin`
drops the stored pin (sign-out, or once the watch resolves).

### Background monitoring (native geofencing)

The stronger tier: the OS wakes the SDK on fence crossings around the stored
pin, app closed or not, so dwell and nights accrue with nobody in the loop.
Entries stamp a timestamp; exits fold the dwell span into per-day aggregates
natively (Kotlin on Android, Swift on iOS) and flush them. As with the
foreground tier, only the derived day records ever leave the phone.

```dart
final result = await MyazaBackgroundPresence.enable(
  apiKey: 'pk_live_…',
  externalUserId: 'user_42',
);
// result.reason: started | noPin | permissionDenied | backgroundDenied | unavailable
```

`enable()` walks the two-step permission escalation (while-in-use, then
"allow all the time"); a refusal leaves the foreground tier working exactly
as before. `MyazaBackgroundPresence.disable()` disarms and forgets the
config. On Android the fence survives reboots (a boot receiver re-arms it);
on iOS, region monitoring relaunches the app for crossings by itself.

**Host declarations, required before enable() can succeed.** The SDK
deliberately does not merge these in, because declaring background location
changes an app's store review posture and that decision belongs to you:

Android (`AndroidManifest.xml` — the example app carries a commented copy):

```xml
<uses-permission android:name="android.permission.ACCESS_FINE_LOCATION" />
<uses-permission android:name="android.permission.ACCESS_COARSE_LOCATION" />
<uses-permission android:name="android.permission.ACCESS_BACKGROUND_LOCATION" />
```

iOS (`Info.plist`):

```xml
<key>NSLocationWhenInUseUsageDescription</key>
<string>Used to confirm your address for verification.</string>
<key>NSLocationAlwaysAndWhenInUseUsageDescription</key>
<string>Lets your address stay confirmed automatically.</string>
```

### The Android foreground service (reliability on OEM-managed phones)

A geofence alone is not reliable on Android once a manufacturer's battery
manager decides your app is idle: transitions are dropped, nothing says so,
and the watch quietly lapses to inconclusive. The phones on that list (Tecno,
Infinix, itel, Xiaomi, Oppo, Vivo) are the ones the market carries. A
foreground service, with its persistent notification, is the one thing those
managers leave alone — and OkHi's own integration guidance for the same
markets is exactly this.

Opt-in and Android only (iOS region monitoring is reliable on its own). The
plugin ships the service class; **you declare it**, with its two permissions,
in your own manifest, for the same reason you declare background location
yourself — a location foreground service changes your Play review posture:

```xml
<uses-permission android:name="android.permission.FOREGROUND_SERVICE" />
<uses-permission android:name="android.permission.FOREGROUND_SERVICE_LOCATION" />

<application>
  <service
      android:name="co.myazahq.kyc.PresenceForegroundService"
      android:exported="false"
      android:foregroundServiceType="location" />
</application>
```

Then, after the flow stored a pin:

```dart
final result = await MyazaPresenceService.enable(
  apiKey: 'pk_live_…',
  externalUserId: 'user_42',
  notification: const PresenceNotification(
    title: 'Address verification in progress', // shown in the status bar
    body: 'Open the app to see your progress',
    color: 0xFF5645F5,
  ),
);
// result.reason: started | unsupportedPlatform | noPin | permissionDenied
//              | backgroundDenied | notDeclared | unavailable
```

`enable()` walks the same permission escalation as the geofence tier and arms
the fence too. While it runs, a low-power fix every ten minutes (or hundred
metres) is turned into the same enter/exit spans the geofence folds, natively,
on the same stored state, so the two never double-count a stay; the queue
flushes while the process is alive; a fence the OS dropped (a location toggle
clears every registered fence) is re-armed; and a reboot restarts it. The
notification uses its own channel, so yours are never touched. Word it
honestly: it is on screen for days. `MyazaPresenceService.disable()` stops it.

### Which tier is running?

Permissions get revoked in Settings and nothing tells the app. Ask:

```dart
final status = await presenceStatus('user_42');
// status.tier: background | foreground | none
// status.locationServicesEnabled / foregroundPermission / backgroundPermission
// status.geofenceArmed / foregroundServiceRunning / alwaysOn
if (!status.locationServicesEnabled) {
  // The phone's location toggle is off: permission granted or not, no fix
  // can be taken. This opens the toggle's own screen.
  await openLocationSettings(target: PresenceSettingsTarget.services);
} else if (status.tier == PresenceTier.none && status.pinStored) {
  // The road back runs through Settings — no OS allows re-prompting in-app.
  await openLocationSettings();
}
```

### Showing the person where the check stands

Somebody kept from a feature until their address is verified should be able
to see the progress in your app, without a webhook relayed through your
backend. `GET /api/kyc/address/presence/:externalUserId` with the publishable
key answers `{ status, progress, tier, … }` — `status` is one of
`not_started | in_progress | verified | failed | inconclusive | expired |
revoked`, `progress.score` is 0..1 on WEIGHTED evidence, and an unknown user
answers the same `not_started` shape as a user with no watch.
