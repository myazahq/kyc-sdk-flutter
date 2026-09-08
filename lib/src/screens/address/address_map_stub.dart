import 'package:flutter/material.dart';
import 'package:lucide_icons_flutter/lucide_icons.dart';

import '../../config/theme.dart';
import '../../utils/map_tiles.dart';
import '../../widgets/dashed_border.dart';

// The SANDBOX map stand-in (the web SDK's preview placeholder, for test keys):
// no tiles, no framed page, no vendor loads. The pin lands on the default
// centre once — what the real map's first idle emits — so Continue stays
// reachable and the integrator walks the whole flow.
//
// A MIRROR of the RN SDK's AddressMapStub.tsx.
class AddressMapStub extends StatefulWidget {
  final bool hasPin;
  final ValueChanged<MapLatLng> onLand;
  final MapLatLng defaultCenter;
  final double height;

  const AddressMapStub({
    super.key,
    required this.hasPin,
    required this.onLand,
    required this.defaultCenter,
    required this.height,
  });

  @override
  State<AddressMapStub> createState() => _AddressMapStubState();
}

class _AddressMapStubState extends State<AddressMapStub> {
  @override
  void initState() {
    super.initState();
    // After the frame: landing a pin writes flow state, which a build must
    // never do.
    if (!widget.hasPin) {
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (mounted) widget.onLand(widget.defaultCenter);
      });
    }
  }

  @override
  Widget build(BuildContext context) {
    final colors = context.myazaColors;
    final text = context.myazaText;
    return SizedBox(
      height: widget.height,
      child: CustomPaint(
        painter: DashedRoundedBorder(color: colors.border, radius: 12),
        child: Center(
          child: Padding(
            padding: const EdgeInsets.all(MyazaSpacing.lg),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                Icon(
                  LucideIcons.mapPinHouse,
                  size: 32,
                  color: colors.textSecondary,
                ),
                const SizedBox(height: MyazaSpacing.sm),
                Text(
                  'Applicants place their pin on a live map here. '
                  'The map loads only for real users.',
                  textAlign: TextAlign.center,
                  style: text.bodySmall.copyWith(color: colors.textSecondary),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}
