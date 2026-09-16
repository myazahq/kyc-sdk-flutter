import 'package:flutter/material.dart';

import '../config/theme.dart';
import '../utils/selfie_sharpness.dart';
import 'myaza_alert.dart';

// ─── "This photo looks blurry", on the selfie review ─────────────────────────
//
// Measures the still once per photo and shows a warning when it reads soft.
// Self-contained so the review view only has to place it: it owns the
// measurement, the race with a retake, and the copy.
//
// A NOTICE, NEVER A GATE (see utils/selfie_sharpness.dart). Nothing here can
// disable Continue, and a photo that could not be measured shows nothing.

const String kSelfieSoftTitle = 'This photo looks blurry';
const String kSelfieSoftMessage =
    'For the best chance of a match, retake it holding the phone steady '
    'until your face is sharp.';

/// Measures a base64 JPEG. Swappable so a widget test need not run an isolate.
typedef SelfieSharpnessMeasure = Future<double?> Function(String base64Jpeg);

class SelfieSoftNotice extends StatefulWidget {
  /// Null on a restored session, where only the uploaded mediaId survived.
  final String? selfieBase64;
  final SelfieSharpnessMeasure measure;

  const SelfieSoftNotice({
    super.key,
    required this.selfieBase64,
    this.measure = measureSelfieSharpness,
  });

  @override
  State<SelfieSoftNotice> createState() => _SelfieSoftNoticeState();
}

class _SelfieSoftNoticeState extends State<SelfieSoftNotice> {
  bool _soft = false;

  /// The photo the pending measurement belongs to. An answer for any other
  /// photo (the applicant retook while it ran) is dropped.
  String? _measuring;

  @override
  void initState() {
    super.initState();
    _measure();
  }

  @override
  void didUpdateWidget(SelfieSoftNotice oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (widget.selfieBase64 != oldWidget.selfieBase64) {
      _soft = false;
      _measure();
    }
  }

  void _measure() {
    final photo = widget.selfieBase64;
    _measuring = photo;
    if (photo == null) return;
    widget.measure(photo).then((score) {
      if (!mounted || _measuring != photo) return;
      if (isSelfieBlurry(score)) setState(() => _soft = true);
    }, onError: (Object _) {});
  }

  @override
  Widget build(BuildContext context) {
    // A core transition rather than flutter_animate: the notice arrives after
    // the review is already on screen, and this leaves no timer behind when
    // the review is torn down mid-fade.
    return AnimatedSwitcher(
      duration: const Duration(milliseconds: 250),
      child: _soft
          ? const Padding(
              key: ValueKey('selfie-soft'),
              padding: EdgeInsets.only(top: MyazaSpacing.lg),
              child: MyazaAlert(
                variant: MyazaAlertVariant.warning,
                title: kSelfieSoftTitle,
                message: kSelfieSoftMessage,
              ),
            )
          : const SizedBox.shrink(key: ValueKey('selfie-sharp')),
    );
  }
}
