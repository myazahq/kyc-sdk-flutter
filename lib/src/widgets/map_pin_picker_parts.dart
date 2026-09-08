import 'package:flutter/material.dart';
import 'package:lucide_icons_flutter/lucide_icons.dart';

import '../config/theme.dart';
import '../utils/map_tiles.dart';
import 'map_pin_marker.dart';

// ─── Map picker chrome ───────────────────────────────────────────────────────
//
// Split from map_pin_picker.dart per the 200-line rule. The picker itself owns
// the gestures and the centre it commits; this file is the tiles, the pin, the
// attribution and the zoom controls.

/// The zoom a recentre lands on. Close enough to answer "is the pin on YOUR
/// building?" without pinching first, which a city-wide view is not.
const int kMapPinZoom = 17;

/// The tiles for a committed centre, translated live during a drag so panning
/// stays smooth without refetching on every frame.
class MapTileLayer extends StatelessWidget {
  final List<TilePlacement> tiles;
  final Offset? offset;

  const MapTileLayer({super.key, required this.tiles, this.offset});

  @override
  Widget build(BuildContext context) {
    return Transform.translate(
      offset: offset ?? Offset.zero,
      child: Stack(
        clipBehavior: Clip.none,
        children: [
          for (final tile in tiles)
            Positioned(
              key: ValueKey(tile.key),
              left: tile.left,
              top: tile.top,
              width: kTileSize.toDouble(),
              height: kTileSize.toDouble(),
              child: Image.network(
                tile.url,
                gaplessPlayback: true,
                errorBuilder: (_, __, ___) => const SizedBox.shrink(),
              ),
            ),
        ],
      ),
    );
  }
}

/// The fixed centre pin, its stem tip on the exact centre; lifted, with the
/// landing dot beneath it, while the map pans.
class MapCentrePin extends StatelessWidget {
  final double height;
  final bool lifted;

  const MapCentrePin({super.key, required this.height, this.lifted = false});

  @override
  Widget build(BuildContext context) {
    return Positioned(
      left: 0,
      right: 0,
      top: 0,
      bottom: height / 2,
      child: IgnorePointer(
        child: Align(
          alignment: Alignment.bottomCenter,
          child: MapPinMarker(
            lifted: lifted,
            color: context.myazaColors.primary,
          ),
        ),
      ),
    );
  }
}

/// Required by the OSM tile-usage terms, so it is always visible.
class MapAttribution extends StatelessWidget {
  const MapAttribution({super.key});

  @override
  Widget build(BuildContext context) {
    final colors = context.myazaColors;
    return Positioned(
      right: 6,
      bottom: 4,
      child: IgnorePointer(
        child: Container(
          padding: const EdgeInsets.symmetric(horizontal: 4),
          decoration: BoxDecoration(
            color: colors.background.withValues(alpha: 0.7),
            borderRadius: BorderRadius.circular(3),
          ),
          child: Text(
            '© OpenStreetMap contributors',
            style: context.myazaText.bodySmall
                .copyWith(fontSize: 10, color: colors.textSecondary),
          ),
        ),
      ),
    );
  }
}

class MapZoomControls extends StatelessWidget {
  final void Function(int delta) onZoom;
  const MapZoomControls({super.key, required this.onZoom});

  @override
  Widget build(BuildContext context) {
    final colors = context.myazaColors;
    return Container(
      decoration: BoxDecoration(
        color: colors.background,
        border: Border.all(color: colors.border),
        borderRadius: BorderRadius.circular(MyazaRadius.sm),
      ),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          _ZoomButton(
            icon: LucideIcons.plus,
            label: 'Zoom in',
            onTap: () => onZoom(1),
          ),
          Container(height: 1, width: 32, color: colors.border),
          _ZoomButton(
            icon: LucideIcons.minus,
            label: 'Zoom out',
            onTap: () => onZoom(-1),
          ),
        ],
      ),
    );
  }
}

class _ZoomButton extends StatelessWidget {
  final IconData icon;
  final String label;
  final VoidCallback onTap;
  const _ZoomButton({required this.icon, required this.label, required this.onTap});

  @override
  Widget build(BuildContext context) {
    final colors = context.myazaColors;
    return Semantics(
      button: true,
      label: label,
      child: InkWell(
        onTap: onTap,
        child: Padding(
          padding: const EdgeInsets.all(8),
          child: Icon(icon, size: 16, color: colors.textDark),
        ),
      ),
    );
  }
}
