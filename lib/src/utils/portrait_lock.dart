import 'package:flutter/services.dart' show DeviceOrientation, SystemChrome;
import 'package:flutter/widgets.dart';

// ─── Portrait for the lifetime of a flow ─────────────────────────────────────
//
// Every screen the SDK draws is a portrait-only UI, and on Android the camera
// preview (CameraX) follows the DISPLAY orientation: if the host app permits
// rotation, tilting the phone to photograph a document — which is exactly what
// somebody does holding it flat over a page — flips the feed sideways a moment
// later.
//
// The rule lived inline in the KYC flow widget, so the OTHER host that mounts a
// camera step, face re-authentication, never locked anything (2026-09-16). One
// mixin, so a new host cannot forget it: `with PortraitLock` and nothing else.
//
// Two things it deliberately does NOT do:
//   • Guess the host's previous setting. Flutter does not expose it, so the
//     release restores ALL orientations and a host that wants its own lock
//     re-applies it after the flow returns (the behaviour the KYC flow already
//     had).
//   • Count nested holders. The two hosts are alternatives, never stacked, so a
//     depth counter would be machinery for a case that cannot arise; if one is
//     ever mounted inside the other, this is the thing to revisit.

mixin PortraitLock<T extends StatefulWidget> on State<T> {
  @override
  void initState() {
    super.initState();
    SystemChrome.setPreferredOrientations([DeviceOrientation.portraitUp]);
  }

  @override
  void dispose() {
    SystemChrome.setPreferredOrientations(DeviceOrientation.values);
    super.dispose();
  }
}
