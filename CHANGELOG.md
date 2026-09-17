## 3.0.2

- Migrated invite-link sharing to the `share_plus` 12 `SharePlus` API.
- Requires `share_plus >=12.0.0 <13.0.0`, allowing host apps on
  `share_plus` 12.x to resolve cleanly.

## 3.0.1

- Relaxed the `share_plus` dependency constraint to allow host apps on
  `share_plus` 12.x.

## 3.0.0

Two changes in this release need action from some apps, which is what makes it
a major:

- **iOS dependency floor.** `device_info_plus` now needs 11.2.1 or later. An app
  that pins it to 10.x must move to 11. See "Swift Package Manager on iOS".
- **Android ML Kit models are fetched, not bundled.** This takes about 18.5 MB
  per device out of the APK, but the models now arrive through Google Play
  Services, so a build shipping to devices without it (Huawei, bare AOSP) must
  set `myazaKycBundledMlKit=true` to keep the offline models. See "A smaller
  Android app".

Everything else is additive. The version also matches the React Native SDK's
3.0.0, so the two platforms carry the same number for the same release.

### Opting out of the NFC permission

The SDK depends on `flutter_nfc_kit` for the eMRTD chip read, and that plugin's
own manifest declares `android.permission.NFC`. Android merges a plugin's
manifest into the host app's, so the permission appears in every build whether
or not the workflows in use touch the chip step, and there was nothing in the
README telling anyone how to remove it.

The platform-setup section now documents the removal:

```xml
<uses-permission android:name="android.permission.NFC" tools:node="remove" />
```

Nothing else changes. The chip step already checks for a radio at runtime and
skips itself when there is none, so a build without the permission behaves
exactly like a phone with no NFC hardware.

Documentation only — no code change, and no effect on apps that do read chips.
Unlike the React Native SDK, Dart has no conditional dependencies, so
`flutter_nfc_kit` still ships either way; the plugin carries no native library,
so what it costs is the permission rather than the download size.

### Swift Package Manager on iOS

The iOS plugin now ships a Swift package beside its podspec. Flutter no longer
warns that `myaza_kyc_sdk_flutter` does not support Swift Package Manager, and
an app that uses Swift Package Manager (the default from Flutter 3.44) builds
the plugin as a package instead of falling back to CocoaPods for it. Apps that
still use CocoaPods need no change.

`device_info_plus` now needs 11.2.1 or later (it was 10.1.0), the first release
that builds as a Swift package, so it drops off that warning too. An app that
pins `device_info_plus` to 10.x needs to move to 11. `flutter_tts` and
`video_compress` have no Swift Package Manager release yet, so Flutter still
lists them and builds them through CocoaPods.

### Document capture without the camera

A workflow can now set `allowDocumentScan: false` (also a `MyazaKYCConfig`
field). The document step then never opens the camera or asks for camera
permission: the person picks a photo of each side from their device, and the
usual preview, review and upload follow. At least one of `allowDocumentScan`
and `allowDocumentUpload` stays on, so a config with both off uses the camera.

### A smaller Android app

On Android the SDK now fetches its two ML Kit models, face detection and text
recognition, through Google Play Services instead of shipping them inside the
host app. Measured on the example app, an arm64 phone now downloads 32.00 MB
instead of 55.75 MB. Both are
requested the moment the flow opens, and the manifest names them, so a Play
Store install usually fetches them before the app first runs.

A model that has not arrived yet can no longer fail silently. The liveness step
waits for the face model and says so if it cannot be set up. The passport
scanner waits for the text model and lets the person continue without the chip
when it cannot. Document auto-capture asks for the model but never waits for it,
since the shutter works without it.

Apps that ship to phones without Google Play Services, such as Huawei devices,
can bring the bundled models back with `myazaKycBundledMlKit=true` in
`android/gradle.properties`.

### Release builds no longer fail on this plugin

The plugin now compiles against Android 36, which three of its dependencies
require. On 34 every host app's release build stopped before reaching app code.
Some third-party plugins in the tree still declare 34, so the README shows the
override a host app needs until they catch up.

## 2.7.0

### The address flow, complete

Address Intelligence on Flutter now walks the same four steps as the web SDK:
a search box (Google autocomplete where the org has it, an explicit search
otherwise), a satellite map with the pin to place, an entrance step that frames
the doorway in Street View imagery where coverage exists and falls back to a
photo where it does not, and a confirmation card. The details sheet edits every
part of the address, a workflow can require any of them, and the flow will not
confirm until the required ones are filled. On a development key the
confirmation card carries a test-result picker for the address verdict, and a
sandbox key gets placeholder maps and a canned device fix rather than live
vendor calls.

### Proof of address knows its market

The proof-of-address step names the document kinds the org accepts, per
country, and asks for the applicant's country on the address scope so the
right kinds are offered. Whether the applicant's name must appear on the
document is now the workflow's rule (required, optional, or not needed), and
the copy follows it.

### Presence that reports

The presence reporter waits for the server to mint its watch before posting
(a report made straight after submission used to land on nothing), and takes
the platform's last known position when a fresh fix does not arrive in time.
The session start now sends the device block, so the dashboard knows the phone
and SDK from the moment the flow opens rather than after it submits.

### Biometric flows

The face check and enrolment screens are one design with the React Native SDK:
a selfie review that a workflow can switch off, one loading screen from the
shutter to the verdict when the workflow delivers it in the app, the org's own
words on the waiting and verdict screens, and a `show()` that takes the flash
sequence length. The liveness ring builds in the workflow's brand colour
rather than the default purple.

### Smaller fixes

A workflow can skip the opening consent screen, and a flow with no consent
opens on its first real step (an address flow used to open on the pin instead
of the search). The confirmation card falls back from the static picture to the
framed Google map before the built-in tiles, without a second pin, and its
address band fits a 360dp phone. Android map gestures no longer fight the page,
and a review whose entrance image never arrives drops the empty frame.

## 2.6.0

### Several IDs in one run

A workflow can now ask for two or three IDs and get back one verification. The
applicant picks each in turn, an ID already used disappears from the later
choices, and one selfie covers the whole run — every ID is matched against it
rather than asking for a new one each time. A position strip above the steps
says which check they are on, because without it a three-ID run is three visits
to the same-looking screen with nothing distinguishing them.

### The KYB application catches up

Business flows on Flutter collected a registration number and stopped. They now
run the whole application: company documents requested by type before the people
step, key people sectioned into beneficial owners, shareholders, and directors
and representatives, corporate shareholders recognised as companies rather than
filed as people, and the registry check running at the moment the applicant
picks their company so the register's own list of officers is on screen before
the form asks who they are.

A KYB submission is also no longer described as an identity check. It is a
company being verified, and calling it "identity verification" told the
applicant they were doing something other than what they were doing.

### Coming back to where you left off

Closing the app used to mean starting again. A remount now restores the step,
the captures and what was typed, and an anonymous mount sends a device id so a
session can be found again without an account. A partial or older snapshot
restores less rather than breaking — the flow never fails because progress was
saved by a different build.

### The links the applicant still needs

A KYB applicant's job is not over when they submit: every director and owner
still has to verify, and those invites outlive the session by days. The success
screen now shows the server's reconciled list rather than the draft the
applicant typed, so people the register added appear and roles it corrected are
right. Tapping Done with checks outstanding offers a way back to the links
instead of closing over them.

### A refused contact code no longer loops

Contact proofs are single-use and expire about half an hour after the code is
checked, but they are saved with session progress and restored on resume. A
returning applicant therefore carried a dead proof while the step still read
"verified", the submission was refused, and Try Again resubmitted the same dead
token forever. The SDK now reads which channels were refused, clears exactly
those, and returns the applicant to that step with an explanation. Verifying
goes straight back to the submission. Nothing else they entered is touched.

### Redo only what was asked for

When a reviewer sends an application back for one document, the applicant walks
that step and no others. Previously the narrowing was collected and then
ignored, so a request to retake one photo restarted the entire flow.

### Smaller things

A name that matches nobody on the register preselects "I'm not one of these
people" rather than leaving the choice blank, which made claiming to be a
stranger the easiest way forward. The wait while the register is read shows the
roster it is about to become instead of a spinner. Sheets take the system's own
corner radius and sit at the system's height, every one has a handle and a close
button, and their corners run concentric with the device's display. Text that
could not be read against its background is fixed, and a sheet no longer runs
under the Dynamic Island.

Two fixes worth naming: the register's answers were being discarded after the
lookup that paid for them, and a wrong type on the poll response stopped Flutter
polling for results at all.

## 2.5.0

### Non-production flows say so

A sandbox flow is pixel-identical to a live one. That is the point — you are
testing the real thing — and also the hazard: screenshots get mistaken for
production incidents, testers wonder why a real passport was rejected, and a
`pk_test_` key shipped to production looks like it works right up until nobody
is actually verified.

A strip above the header now names the environment. It reads from the
**server's** config rather than sniffing the API key prefix, because a hosted
handoff session authenticates with an `hs_` token that carries no environment
slot — key-sniffing would leave exactly the surface an end user sees unlabelled.
Development is labelled too, and differently: it runs the real pipeline against
staging provider credentials, so "test data only" would be untrue there.

Production flows are unaffected — nothing is drawn.

### `progressStyle: none`

A third option alongside `steps` and `bar`: no progress element in the header at
all. For hosts whose own surface already communicates progress, or short flows
where a step count is more noise than reassurance. The brand row and controls
stay; only the progress element is dropped.

An unrecognised value still falls back to `steps` rather than throwing, so a
newer server adding a fourth style will not break this SDK.

## 2.4.0

### PACE chip access

The eMRTD reader spoke Basic Access Control only, so passports issued with PACE
as their sole access protocol — standard across the EU since roughly 2014, and
spreading — could not be read at all. PACE is now implemented alongside BAC, and
the session negotiates: PACE where the chip offers it, BAC where it does not.

Which protocol a read used is reported back rather than inferred. A chip that
falls back to BAC because it offers nothing else is healthy; one that falls back
because our PACE attempt broke is a bug, and the protocol alone cannot tell the
two apart — so the outcome travels with the submission as a diagnostic.

### The chip's printed details are parsed, and its photo renders on Android

DG1 — the data page as the chip stores it — is now parsed and shown on the
success screen, so the read confirms what it actually recovered instead of
asserting that something was read.

DG2 portraits encoded as JPEG 2000 now decode on Android, which has no
JPEG 2000 support of its own. Previously those chips produced a portrait the
platform could not render.

### `progressStyle`

The header's progress indicator is now configurable:

* `MyazaProgressStyle.steps` (default) — numbered circles, one per step. When a
  flow has more steps than fit, they collapse to a moving window rather than
  shrinking past legibility.
* `MyazaProgressStyle.bar` — a single thin bar on the header's bottom edge.
  Quieter, and unaffected by step count, so it suits long flows.

Both convey the same fraction; the choice is how much room it takes. A published
workflow can carry the setting, and an unrecognised value falls back to `steps`
rather than throwing — a newer server adding a third style must not break an
older SDK. Mirrors the React Native SDK's `progressStyle`.

### Also

Document capture handling and the dropdown anchoring were reworked.

## 2.3.0

### The full business (KYB) application

The business flow previously stopped at the registry lookup. It now runs the
whole application section, each part appearing only when the resolved workflow
configures it:

* **Directors & owners** — name, role, ownership percentage, country and email
  per person, with `minEntries` gating Continue.
* **Supporting documents** — one upload slot per configured document type; every
  required slot must be filled before the step will pass.
* **Applicant verification** — the submitter declares their role, and can
  identify themselves as one of the people they just listed. Picking themselves
  links the two records, so one person is verified once rather than being both a
  key person and a separate applicant. Their own capture leg then runs as an
  ordinary individual verification.
* **Invite links** — where a director or owner needs their own check, the
  success screen hands back their invite links, shareable through the native
  share sheet.

### Contact verification and proof of address, rebuilt

The email/phone OTP steps were split into composable parts (channel picker,
entry, verified state) and gained a WhatsApp delivery channel alongside SMS.
Proof of address accepts a wider range of documents and states its own recency
window.

### Also

* An NFC scan illustration that animates the document against the phone, so the
  chip step stops looking like a hang.
* `PoweredBy` and brand-mark widgets, and a shared dashed-border painter.

## 2.2.0

### `country` is optional when you launch from a workflow

`MyazaKYCConfig.country` was `required` while its own documentation said a
`workflowId` mount could omit it — so the documented usage did not compile. A
workflow user had to invent a country purely to satisfy the constructor, then
watch the resolved flow overwrite it.

It is now optional. Passing one is unchanged; omitting it is only valid
alongside a `workflowId`, and `MyazaKYC.show` refuses to mount a config that
reaches it without a country from either source, reporting `onError` with a
stated reason rather than silently rendering an empty ID-type list.

Everything country-sensitive already read `effectiveCountry(config, state)`;
the remaining direct reads (business details, contact defaults, the business
verify payload) now go through it too.

> Existing code is unaffected: `country:` is still accepted exactly as before.
> The field's type widened from `String` to `String?`, so the rare caller that
> reads `config.country` back into a non-nullable `String` will need a `?? ''`
> or a null check.

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
