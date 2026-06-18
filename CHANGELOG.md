## 2.0.1

* **Sandbox and production now share one base URL** (`https://identity.myaza.app`).
  The environment is still derived solely from the API key prefix (`pk_test_…` →
  sandbox, `pk_live_…` → production); only the host the sandbox keys resolve to
  changed — no integration code changes are required.

## 2.0.0

First release on pub.dev, under the package's final name.

* **Package renamed** to `myaza_kyc_sdk_flutter` (import
  `package:myaza_kyc_sdk_flutter/myaza_kyc_sdk_flutter.dart`).
* **Environment is derived from the API key prefix** — the `environment` config
  field is gone. `pk_test_…` → sandbox (`sandbox.identity.myaza.app`),
  `pk_live_…` → production.
* **Flutter 3.27+ / Dart 3.6+** is now the minimum supported toolchain.
* Docs: added a Requirements section (iOS 13.0, Android minSdk 21, camera
  permission setup).

## 1.0.0

Initial public release of the Myaza KYC Flutter SDK — ID capture, document scan,
and on-device active liveness (Apple Vision on iOS, Google ML Kit on Android),
talking to the Myaza KYC API.

Robustness & UX:

* **Typed errors.** `onError` receives a `KYCError` with a stable `code`
  (`network_error`, `invalid_api_key`, `insufficient_credits`, `upload_failed`,
  `camera_permission_denied`, `feature_disabled`, `unknown`) — identical to the
  React SDK.
* **Camera permission.** A denied camera shows a dedicated screen with an
  *Open Settings* action and reports `camera_permission_denied`; document
  capture keeps a gallery-upload fallback there.
* **Network resilience.** Uploads + verify retry transient failures
  (network / timeout / 5xx) with exponential backoff + jitter; `onError` fires
  only after retries are exhausted, with "retrying (n/3)…" feedback.
* **Multiple faces.** Liveness pauses ("Make sure only your face is visible")
  when more than one face is in frame and resumes automatically.
* **Lighting.** Live too-dark / too-bright detection during liveness, with
  guidance; auto-capture is discouraged until lighting is acceptable.
* **Voice guidance.** Spoken liveness instructions (TTS output, no microphone)
  via `VoiceGuidanceConfig` — toggle with `VoiceGuidanceConfig.off`, or set a
  voice `language` (e.g. `fr-FR`).
* **`allowDocumentUpload`.** Hide the device-gallery document option when set to
  `false` (still offered on the permission screen as an escape hatch).
