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
