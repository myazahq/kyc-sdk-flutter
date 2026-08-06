## 2.1.0

### Android document capture rebuilt on native CameraX

The document step no longer drives the camera through the Flutter camera
plugin on Android. It now runs a single native CameraX session — preview,
frame analysis and still capture — which fixes the four problems the plugin
path had on devices like the Galaxy S24:

* **Faster to open**, and no longer re-initialises the camera between the front
  and back of a two-sided document, or on a retake.
* **Sharper preview.** The plugin needed a use-case combination many devices
  cannot serve, so CameraX quietly downgraded the streams.
* **Smooth capture.** A still no longer tears down the video recording and
  reconfigures the camera surface.
* **No rotation drift.** The preview no longer re-rotates itself off the
  accelerometer when the phone is held flat over a document.

iOS is unchanged; it keeps the plugin path, which was already stable.

### Chip reading is now our own implementation

The eMRTD reader no longer depends on the `dmrtd` package, whose licence does
not permit redistribution inside a commercial SDK. The Basic Access Control
handshake, secure messaging and file reading are implemented in the SDK and
checked against the worked example published in ICAO 9303 Part 11 Appendix D —
session keys, send-sequence counter and the protected command bytes all match
the standard exactly.

Reading adapts to the document rather than assuming a fixed chunk size: chips
disagree about how many bytes they will serve per read and about how to refuse,
so the reader backs off on a wrong-length error, adopts a length the chip names
for itself, keeps the data from a short read, and switches to extended reads for
files past 32 KB. Nothing about the submitted data changed.

**PACE support.** Chips that have retired Basic Access Control can now be read.
PACE uses the passport's printed details only to unlock a fresh random value and
then agrees new session keys each time, so recording a session no longer reveals
anything to someone who later photographs the page. Generic Mapping over
elliptic curves is implemented, with 3DES and AES at 128, 192 and 256 bits.

BAC is still tried first and PACE only when a chip refuses it. That is the
opposite of the standard's preference and deliberately so for this release: BAC
has read real documents here for a long time and PACE has read none, so in this
order PACE can only add documents that can be read, never take away one that
already worked. The order flips once PACE is confirmed on real passports.

Two variants are not implemented and fall back to BAC rather than failing:
Integrated Mapping, and PACE over finite-field Diffie-Hellman. Virtually all
issued passports offer the elliptic-curve variants.

### Full-screen document capture

The camera fills the screen instead of sitting in a fixed box, so the guide —
and therefore the document — occupies far more of the sensor. Controls moved
in-frame: a back button, the document being captured (flag + type), the live
framing hint, "upload a photo instead", and the shutter, with the torch beside
it.

### New

* **Torch**, on both platforms, for capturing documents in poor light.
* **Auto-capture now verifies the document.** It checks that the recognised
  text identifies the document you asked for, so it no longer fires at anything
  text-dense (a screen, a book, another ID). Passports additionally require the
  machine-readable zone in frame, which also means the chip step no longer has
  to scan the document a second time.
* **Chip-read progress on Android.** iOS gets a system NFC sheet from the OS;
  Android had nothing, so the SDK now shows an equivalent sheet with per-step
  detail — including that the security-data step is the long one.
* **Automatic chip retry.** The first read attempt routinely failed on Android
  and an immediate retry succeeded with the phone untouched; the reader now
  does that itself instead of asking the user to.

### Fixed

* Side videos that recorded correctly could be uploaded as zero bytes, when a
  late frame reconstructed the encoder over the finished file.
* The back button and side badge overlapped the status bar in the full-screen
  camera.
* The capture hint could sit behind the shutter button.

## 2.0.1

* **Sandbox and production now share one base URL** (`https://trust.myaza.app`).
  The environment is still derived solely from the API key prefix (`pk_test_…` →
  sandbox, `pk_live_…` → production); only the host the sandbox keys resolve to
  changed — no integration code changes are required.

## 2.0.0

First release on pub.dev, under the package's final name.

* **Package renamed** to `myaza_kyc_sdk_flutter` (import
  `package:myaza_kyc_sdk_flutter/myaza_kyc_sdk_flutter.dart`).
* **Environment is derived from the API key prefix** — the `environment` config
  field is gone. `pk_test_…` → sandbox (`sandbox.trust.myaza.app`),
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
