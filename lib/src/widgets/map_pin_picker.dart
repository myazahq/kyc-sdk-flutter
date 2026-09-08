import 'package:flutter/material.dart';

import '../config/address_flow.dart' show kPinEpsilon;
import '../config/theme.dart';
import '../utils/map_tiles.dart';
import 'map_pin_picker_parts.dart';

/// A dependency-free OSM slippy map with a FIXED CENTRE PIN — the user moves
/// the map under the pin (the pattern address pickers use on phones), so the
/// pin is always exactly the centre and there is no marker to fumble. Maths in
/// utils/map_tiles.dart; this is only the gesture shell. Mirrors the web and
/// RN SDKs' MapPinPicker: tiles for the committed centre, a live translate
/// during the drag, and a commit (+ onChange) on release.
class MapPinPicker extends StatefulWidget {
  /// The confirmed pin, when one exists — the map centres on it.
  final MapLatLng? value;

  /// Fired when the user settles the map (drag end / zoom / recentre).
  final ValueChanged<MapLatLng> onChange;
  final MapLatLng defaultCenter;
  final int defaultZoom;
  final double height;

  /// Off for the review step's summary map: no gestures, no zoom controls.
  /// The pin is being CONFIRMED there, not placed, and a map that moves under
  /// a confirmation invites an edit nobody asked for.
  final bool interactive;

  /// Drawn over the map, bottom centre — the locate pill on the pin step.
  final Widget? overlay;

  /// Corner rounding. 0 where a parent already shapes the frame: the review
  /// card rounds its TOP corners only, and the picker's own radius (and its
  /// border) put a curve and a hairline where the map meets the address band.
  /// Mirrors the RN picker's `cornerRadius`.
  final double? cornerRadius;

  const MapPinPicker({
    super.key,
    required this.value,
    required this.onChange,
    required this.defaultCenter,
    required this.defaultZoom,
    this.height = 256,
    this.interactive = true,
    this.overlay,
    this.cornerRadius,
  });

  @override
  State<MapPinPicker> createState() => _MapPinPickerState();
}

class _MapPinPickerState extends State<MapPinPicker> {
  late MapLatLng _center = widget.value ?? widget.defaultCenter;

  // The close-in zoom exists so the applicant can ANSWER "is the pin on your
  // building?", which a read-only summary never asks: there, the caller's own
  // zoom stands.
  late int _zoom = widget.value != null && widget.interactive
      ? kMapPinZoom
      : widget.defaultZoom;

  // Live drag offset — applied as a translate so panning stays smooth; the
  // centre (and tile set) commits on release.
  Offset? _drag;

  @override
  void didUpdateWidget(MapPinPicker old) {
    super.didUpdateWidget(old);
    // An EXTERNAL recentre (a search pick, a locate) moves the map and zooms
    // in. Compared against the centre this map is actually showing, not
    // against the old prop: the widget commits its own pans through onChange,
    // so a prop comparison treats every drag as an external recentre and yanks
    // the zoom back to 17 — including on someone who had zoomed out on purpose
    // to find their area.
    //
    // The epsilon is the flow's own settle guard: a difference below it is
    // tile drift, and moving (let alone zooming) for that is exactly what the
    // guard exists to stop.
    final v = widget.value;
    if (v != null &&
        ((_center.lat - v.lat).abs() >= kPinEpsilon ||
            (_center.lng - v.lng).abs() >= kPinEpsilon)) {
      setState(() {
        _center = v;
        if (widget.interactive && _zoom < kMapPinZoom) _zoom = kMapPinZoom;
      });
    }
  }

  void _commitDrag(Offset drag) {
    if (drag == Offset.zero) return;
    final next = panCenter(_center, _zoom, drag.dx, drag.dy);
    setState(() => _center = next);
    widget.onChange(next);
  }

  void _zoomBy(int delta) {
    final next = (_zoom + delta).clamp(kMinZoom, kMaxZoom);
    if (next == _zoom) return;
    setState(() => _zoom = next);
    widget.onChange(_center);
  }

  @override
  Widget build(BuildContext context) {
    final colors = context.myazaColors;
    final radius = widget.cornerRadius ?? MyazaRadius.md;
    return Semantics(
      label: widget.interactive
          ? 'Map. Drag to position the pin on your address.'
          : 'Map showing the pinned address.',
      child: ClipRRect(
        borderRadius: BorderRadius.circular(radius),
        child: Container(
          height: widget.height,
          decoration: BoxDecoration(
            color: colors.backgroundSecondary,
            // A squared-off map is clipped by its card, which draws the edge.
            border: radius == 0 ? null : Border.all(color: colors.border),
            borderRadius: BorderRadius.circular(radius),
          ),
          child: LayoutBuilder(
            builder: (context, constraints) {
              final tiles = visibleTiles(
                  _center, _zoom, constraints.maxWidth, widget.height);
              final map = Stack(
                clipBehavior: Clip.hardEdge,
                children: [
                  Positioned.fill(
                    child: MapTileLayer(tiles: tiles, offset: _drag),
                  ),
                  MapCentrePin(height: widget.height, lifted: _drag != null),
                  if (widget.interactive)
                    Positioned(
                      right: 8,
                      top: 8,
                      child: MapZoomControls(onZoom: _zoomBy),
                    ),
                  if (widget.overlay != null)
                    Positioned(
                      left: 0,
                      right: 0,
                      bottom: MyazaSpacing.md,
                      child: Center(child: widget.overlay!),
                    ),
                  const MapAttribution(),
                ],
              );
              // A non-interactive map wears NO gesture layer at all, rather
              // than one with its callbacks nulled: the review step wraps the
              // whole map in its own tap target, and an opaque detector in
              // between is a hazard nothing in this widget would reveal.
              if (!widget.interactive) return map;
              return GestureDetector(
                behavior: HitTestBehavior.opaque,
                onPanStart: (_) => setState(() => _drag = Offset.zero),
                onPanUpdate: (d) =>
                    setState(() => _drag = (_drag ?? Offset.zero) + d.delta),
                onPanEnd: (_) {
                  final drag = _drag;
                  setState(() => _drag = null);
                  if (drag != null) _commitDrag(drag);
                },
                onPanCancel: () => setState(() => _drag = null),
                child: map,
              );
            },
          ),
        ),
      ),
    );
  }
}
