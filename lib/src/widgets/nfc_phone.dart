import 'dart:math' as math;

import 'package:flutter/material.dart';
import 'package:lucide_icons_flutter/lucide_icons.dart';

import '../config/theme.dart';

// ─── NFC phone (passport illustration) ────────────────────────────────────────
//
// The phone held against the passport cover, reading the chip underneath — the
// pulse sits INSIDE the phone, where the antenna actually is. Split from
// passport_illustration.dart for the 200-line rule.
//
// Exact port of the web reference's phone block:
//   h-32 w-[72px]  rounded-2xl  border-2 border-foreground/30  bg-background/95
//   speaker  mt-2.5 h-1 w-7  bg-foreground/20
//   pulse    h-14 w-14 · ping inset-0 primary/20 · pulse inset-2 primary/15
//   core     h-11 w-11 bg-primary shadow-lg · Nfc h-5 w-5

// Reference sizes from the web (w-[72px] / h-32) at its booklet width of 272.6.
// Everything below is expressed as a fraction of the ACTUAL booklet width so
// the phone keeps its proportion to the passport at any rendered size — the
// booklet is aspect-driven, so a fixed-pixel phone grows relative to it
// whenever the illustration is laid out shorter than the reference 240.
const double kNfcPhoneWidthRatio = 0.26408; // 72 / 272.6
const double kNfcPhoneHeightRatio = 0.46947; // 128 / 272.6
const double kNfcPhoneRightRatio = -0.16139; // -44 / 272.6
const double kNfcPhoneBottomRatio = -0.07336; // -20 / 272.6

const double _refPhoneW = 72;

class NfcPhone extends StatefulWidget {
  /// Rendered width; inner details scale from it.
  final double width;

  const NfcPhone({super.key, this.width = _refPhoneW});

  @override
  State<NfcPhone> createState() => _NfcPhoneState();
}

class _NfcPhoneState extends State<NfcPhone>
    with SingleTickerProviderStateMixin {
  late final AnimationController _pulse = AnimationController(
    vsync: this,
    duration: const Duration(milliseconds: 1800),
  )..repeat();

  @override
  void dispose() {
    _pulse.dispose();
    super.dispose();
  }

  /// Scale of this instance against the web reference (56pt wide).
  double get _s => widget.width / _refPhoneW;

  @override
  Widget build(BuildContext context) {
    final colors = context.myazaColors;
    return _phone(colors);
  }

  /// The phone held against the cover, reading the chip underneath it — the
  /// pulse sits inside the phone, where the antenna actually is.
  Widget _phone(MyazaColorScheme colors) {
    return Container(
      width: widget.width,
      height: widget.width * (kNfcPhoneHeightRatio / kNfcPhoneWidthRatio),
      decoration: BoxDecoration(
        color: colors.background.withValues(alpha: 0.95), // bg-background/95
        border: Border.all(color: colors.textDark.withValues(alpha: 0.3), width: 2),
        borderRadius: BorderRadius.circular(16 * _s),
        boxShadow: [
          BoxShadow(
            color: colors.textDark.withValues(alpha: 0.12),
            blurRadius: 12,
            offset: const Offset(0, 4),
          ),
        ],
      ),
      child: Stack(
        alignment: Alignment.center,
        children: [
          Positioned(
            top: 10 * _s, // mt-2.5
            child: Container(
              width: 28 * _s, // w-7
              height: 4 * _s,
              decoration: BoxDecoration(
                color: colors.textDark.withValues(alpha: 0.2),
                borderRadius: BorderRadius.circular(2),
              ),
            ),
          ),
          _nfcPulse(colors),
        ],
      ),
    );
  }

  Widget _nfcPulse(MyazaColorScheme colors) {
    return AnimatedBuilder(
      animation: _pulse,
      builder: (context, child) {
        final t = _pulse.value;
        return SizedBox(
          width: 56 * _s, // h-14 w-14
          height: 56 * _s,
          child: Stack(
            alignment: Alignment.center,
            children: [
              // Expanding ring — the web version's `animate-ping`.
              Transform.scale(
                scale: 1 + t * 0.6,
                child: Opacity(
                  opacity: (1 - t) * 0.2,
                  child: Container(
                    decoration: BoxDecoration(color: colors.primary, shape: BoxShape.circle),
                  ),
                ),
              ),
              // Inner breathing halo — the web version's second layer
              // (`animate-pulse` at inset-2). Missing here, which is why the
              // pulse looked thinner than the reference.
              Padding(
                // inset-2 on a 56px box = 8px each side → a 40px circle.
                padding: EdgeInsets.all(8 * _s),
                child: Opacity(
                  // Sine so it eases at both ends like CSS animate-pulse,
                  // rather than the sawtooth a raw controller value gives.
                  opacity: 0.15 * (0.5 + 0.5 * math.sin(t * 2 * math.pi)),
                  child: Container(
                    decoration: BoxDecoration(
                        color: colors.primary, shape: BoxShape.circle),
                  ),
                ),
              ),
              child!,
            ],
          ),
        );
      },
      child: Container(
        width: 44 * _s, // h-11 w-11
        height: 44 * _s,
        decoration: BoxDecoration(
          color: colors.primary,
          shape: BoxShape.circle,
          // shadow-lg
          boxShadow: [
            BoxShadow(
              color: colors.primary.withValues(alpha: 0.35),
              blurRadius: 15 * _s,
              offset: Offset(0, 4 * _s),
            ),
          ],
        ),
        child: Icon(LucideIcons.nfc, size: 20 * _s, color: colors.onPrimary),
      ),
    );
  }
}
