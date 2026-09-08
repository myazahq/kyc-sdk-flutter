import 'package:flutter/material.dart';

import '../../config/theme.dart';
import '../../utils/map_tiles.dart';
import '../../widgets/framed_map_picker.dart';
import '../../widgets/map_pin_marker.dart';
import '../../widgets/map_pin_picker.dart';
import 'address_map_stub.dart';

// ─── The review card's map ───────────────────────────────────────────────────
//
// The map as a PICTURE: a confirmation screen wants a photograph of the place,
// not a second instrument. Split from address_review_card.dart (200-line
// rule). The order the surfaces fall back in is the same one the web and RN
// review cards keep, and it is a pure function so a test can pin it: the
// picture, then the SAME framed Google map the pin step drew, and only then
// the built-in tiles. Flutter used to skip the middle rung, so a deployment
// without the Maps Static API (a separate console enablement) confirmed the
// address on OpenStreetMap while RN confirmed it on Google (user report
// 2026-09-08).
//
// A REFUSED picture is lifted into state, as RN's staticMapFailed is, and the
// surface is re-decided from it: the live maps draw their own pin, so the
// SDK's overlay pin belongs on the picture alone. Falling back inside the
// image's errorBuilder while the Stack still painted the overlay put two pins
// on the framed map (user report 2026-09-08, the iPhone).

/// Web's review map is h-48 (192px) at mobile widths; keep the mirror exact.
const double kReviewMapHeight = 192;

enum ReviewMapSurface { stub, picture, framed, builtIn }

/// Which surface the review card draws. [staticMapFailed] is the picture
/// refused (the Static API answers 403 and the route 404s); [hasFrame] is a
/// server-minted maps frame URL.
ReviewMapSurface reviewMapSurface({
  required bool vendorsStubbed,
  required bool hasStaticMap,
  required bool staticMapFailed,
  required bool hasFrame,
}) {
  if (vendorsStubbed) return ReviewMapSurface.stub;
  if (hasStaticMap && !staticMapFailed) return ReviewMapSurface.picture;
  if (hasFrame) return ReviewMapSurface.framed;
  return ReviewMapSurface.builtIn;
}

class AddressReviewMap extends StatefulWidget {
  final MapLatLng pin;
  final bool vendorsStubbed;
  final String? mapsFrameUrl;
  final String? staticMapUrl;
  final Map<String, String> imageHeaders;

  const AddressReviewMap({
    super.key,
    required this.pin,
    required this.vendorsStubbed,
    required this.mapsFrameUrl,
    required this.staticMapUrl,
    required this.imageHeaders,
  });

  @override
  State<AddressReviewMap> createState() => _AddressReviewMapState();
}

class _AddressReviewMapState extends State<AddressReviewMap> {
  /// The picture was refused (the Static API answers 403 and the route 404s).
  bool _pictureFailed = false;

  @override
  void didUpdateWidget(AddressReviewMap old) {
    super.didUpdateWidget(old);
    // A moved pin is a new picture; give it its own chance.
    if (old.staticMapUrl != widget.staticMapUrl) _pictureFailed = false;
  }

  /// Called from the image's errorBuilder, so it runs during build: the flag
  /// is flipped after the frame, and only once.
  void _markPictureFailed() {
    if (_pictureFailed) return;
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (mounted && !_pictureFailed) setState(() => _pictureFailed = true);
    });
  }

  /// The live map, squared off: the card rounds its top corners and the band
  /// below draws the bottom edge, so the picker's own radius and border put a
  /// curve and a hairline where the map meets the address.
  Widget _liveMap() {
    final frameUrl = widget.mapsFrameUrl;
    if (frameUrl != null) {
      // Touches are swallowed: the tap that matters is the one back to editing.
      return IgnorePointer(
        child: FramedMapPicker(
          frameUrl: frameUrl,
          value: widget.pin,
          onChange: (_) {},
          defaultCenter: widget.pin,
          defaultZoom: 16,
          height: kReviewMapHeight,
          cornerRadius: 0,
        ),
      );
    }
    return MapPinPicker(
      value: widget.pin,
      onChange: (_) {},
      defaultCenter: widget.pin,
      defaultZoom: 16,
      height: kReviewMapHeight,
      interactive: false,
      cornerRadius: 0,
    );
  }

  /// The picture, with the SDK's own pin over it so the flow shows ONE pin
  /// throughout rather than a vendor marker on the last screen. Once the
  /// picture is refused the SAME tree is kept, marker withheld: the live map
  /// the errorBuilder mounted stays where it is rather than being rebuilt in
  /// a new position (the framed one is a WebView, and a remount reloads it).
  Widget _picture(MyazaColorScheme colors, {required bool marker}) {
    return Stack(
      alignment: Alignment.center,
      children: [
        // The picture's space, held in the map's grey while the bytes land,
        // rather than the live map flashing for the half second before them
        // (RN's staticMapPending).
        ColoredBox(
          color: colors.backgroundSecondary,
          child: Image.network(
            widget.staticMapUrl!,
            headers: widget.imageHeaders,
            width: double.infinity,
            height: kReviewMapHeight,
            fit: BoxFit.cover,
            // A refused picture falls back to the live map, exactly as the
            // pin step's own choice of surface.
            errorBuilder: (_, __, ___) {
              _markPictureFailed();
              return _liveMap();
            },
          ),
        ),
        if (marker)
          IgnorePointer(child: MapPinMarker(lifted: false, color: colors.primary)),
      ],
    );
  }

  @override
  Widget build(BuildContext context) {
    final colors = context.myazaColors;
    final surface = reviewMapSurface(
      vendorsStubbed: widget.vendorsStubbed,
      hasStaticMap: widget.staticMapUrl != null,
      staticMapFailed: _pictureFailed,
      hasFrame: widget.mapsFrameUrl != null,
    );
    return switch (surface) {
      ReviewMapSurface.stub => AddressMapStub(
          hasPin: true,
          onLand: (_) {},
          defaultCenter: widget.pin,
          height: kReviewMapHeight,
        ),
      ReviewMapSurface.picture => _picture(colors, marker: true),
      ReviewMapSurface.framed || ReviewMapSurface.builtIn =>
        widget.staticMapUrl != null ? _picture(colors, marker: false) : _liveMap(),
    };
  }
}
