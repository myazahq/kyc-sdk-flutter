import 'package:flutter/material.dart';

import '../config/theme.dart';
import 'nfc_phone.dart';
import 'passport_painters.dart';

// ─── Passport illustration ───────────────────────────────────────────────────
//
// The passport a user holds against their phone, drawn as the CLOSED booklet
// cover — the portrait shape and the title / emblem / country / chip-symbol
// stack every e-passport shares.
//
// A port of the web SDK's PassportIllustration (kyc-sdk-react
// src/components/PassportIllustration.tsx): same proportions, same theme-token
// palette, so the builder preview and the native screens show one design. The
// printed title and country are PLACEHOLDER BARS, not words — covers are
// printed in the issuing state's own language, so any literal text would be
// wrong for most holders. The only literal mark is the ICAO chip symbol, which
// genuinely is identical on every e-passport.

// ── Exact mapping of the web reference ───────────────────────────────────────
//
// Tailwind classes → px (h-60 = 240, w-24 = 96, h-2.5 = 10, gap-1.5 = 6, …).
// Web sizes are px in a 390pt layout, so they carry over 1:1 to logical pixels.
//
// Token equivalence, verified against globals.css — these are EXACT, not
// approximations:
//   web `border`          → colors.border          (#D3CFFC / #302D53)
//   web `foreground`      → colors.textDark        (#070330 / #F6F5FE)
//   web `background`      → colors.background      (#FFFFFF / #040218)
//   web `muted-foreground`→ colors.textSecondary   (#5A5775 / #ACABBA)
//
// `muted` is the one web token with no single Flutter counterpart: it is
// #F6F5FE in light (= backgroundSecondary) but #302D53 in dark (= border), so
// it is resolved per theme below rather than approximated with one token.
const double _bookletHeight = 384;   // h-96
const double _bookletAspect = 0.71;  // aspect-[0.71] — 88×125mm closed
const double _coverRadiusLeft = 8;   // rounded-l-lg  (spine side)
const double _coverRadiusRight = 16; // rounded-r-2xl

/// Booklet width at the reference height. Every printed element is expressed
/// against this and multiplied by the actual scale, so the cover reads the same
/// whether it renders at full size or is squeezed by a short container — fixed
/// pixels would leave the emblem and bars undersized (or overflowing) the
/// moment the height is clamped.
const double _refBookletWidth = _bookletHeight * _bookletAspect;

/// web `muted`, which differs per theme (see note above).
Color _muted(MyazaColorScheme colors, bool isDark) =>
    isDark ? colors.border : colors.backgroundSecondary;

/// The flow's theme is derived from consumer overrides, so `Theme.brightness`
/// tracks the HOST app rather than the flow — read the flow's own surface.
bool _isDark(MyazaColorScheme colors) =>
    colors.background.computeLuminance() < 0.5;

class PassportIllustration extends StatefulWidget {
  const PassportIllustration({super.key});

  @override
  State<PassportIllustration> createState() => _PassportIllustrationState();
}

class _PassportIllustrationState extends State<PassportIllustration> {
  @override
  Widget build(BuildContext context) {
    final colors = context.myazaColors;

    // AspectRatio holds the booklet's shape; Clip.none lets the phone hang off
    // its corner.
    //
    // The cover MUST be Positioned.fill. As a plain (loose) Stack child it
    // sizes to its own content instead of the frame, which renders the booklet
    // tall and narrow rather than at its 0.71 aspect.
    //
    // Phone size and offsets are fractions of the booklet width, taken from the
    // web (56/96 and -36/-16 against its 170.4-wide booklet), so the pair keeps
    // the reference proportions at whatever size the booklet renders.
    const bookletWidth = _refBookletWidth;

    return SizedBox(
      height: _bookletHeight,
      child: Center(
        child: AspectRatio(
          aspectRatio: _bookletAspect,
          child: Stack(
            clipBehavior: Clip.none,
            children: [
              Positioned.fill(child: _cover(colors, 1.0)),
              const Positioned(
                right: bookletWidth * kNfcPhoneRightRatio,
                bottom: bookletWidth * kNfcPhoneBottomRatio,
                child: NfcPhone(width: bookletWidth * kNfcPhoneWidthRatio),
              ),
            ],
          ),
        ),
      ),
    );
  }

  /// The booklet. Squarer on the left (the spine side) and rounder on the
  /// right — that asymmetry is what separates a booklet from a card.
  Widget _cover(MyazaColorScheme colors, double s) {
    return Container(
      decoration: BoxDecoration(
        // bg-muted/40 — a TRANSLUCENT wash, not an opaque surface token.
        color: _muted(colors, _isDark(colors)).withValues(alpha: 0.40),
        border: Border.all(color: colors.border, width: 2), // border-2
        borderRadius: BorderRadius.horizontal(
          left: Radius.circular(_coverRadiusLeft * s),
          right: Radius.circular(_coverRadiusRight * s),
        ),
        // shadow-sm
        boxShadow: [
          BoxShadow(
            color: colors.textDark.withValues(alpha: 0.06),
            blurRadius: 2,
            offset: const Offset(0, 1),
          ),
        ],
      ),
      // px-6 py-9
      padding: EdgeInsets.symmetric(horizontal: 24 * s, vertical: 36 * s),
      child: Column(
        mainAxisAlignment: MainAxisAlignment.spaceBetween,
        crossAxisAlignment: CrossAxisAlignment.center,
        children: [
          // Document title.
          _bar(colors, width: 128 * s, height: 14 * s), // h-3.5 w-32
          SizedBox(
            width: 96 * s, // h-24 w-24
            height: 96 * s,
            child: CustomPaint(
              // text-muted-foreground/60
              painter: StateEmblemPainter(
                  color: colors.textSecondary.withValues(alpha: 0.6)),
            ),
          ),
          // Issuing country.
          Column(
            children: [
              _bar(colors, width: 112 * s, height: 8 * s), // h-2 w-28
              SizedBox(height: 8 * s), // gap-2
              _bar(colors, width: 64 * s, height: 8 * s), // h-2 w-16
            ],
          ),
          SizedBox(
            width: 36 * s, // h-6 w-9
            height: 24 * s,
            child: CustomPaint(
              painter: EPassportMarkPainter(color: const Color(0xFFF59E0B).withValues(alpha: 0.7)),
            ),
          ),
        ],
      ),
    );
  }

  Widget _bar(MyazaColorScheme colors, {required double width, required double height}) {
    return Container(
      width: width,
      height: height,
      decoration: BoxDecoration(
        color: colors.border,
        borderRadius: BorderRadius.circular(height / 2),
      ),
    );
  }
}
