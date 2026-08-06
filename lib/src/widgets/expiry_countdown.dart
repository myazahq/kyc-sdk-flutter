import 'dart:async';

import 'package:flutter/material.dart';

// ─── Expiry countdown ─────────────────────────────────────────────────────────
//
// Live "expires in m:ss" ticker for a one-time code. Ticks once a second and
// stops itself at zero, so a stale challenge reads as expired instead of
// claiming minutes that already elapsed.

class ExpiryCountdown extends StatefulWidget {
  /// When the code stops being valid (server-sent, may be UTC — `difference`
  /// compares absolute time so the local/UTC flag doesn't matter).
  final DateTime expiresAt;

  final TextStyle? style;

  /// Shown once the countdown reaches zero.
  final String expiredLabel;

  const ExpiryCountdown({
    super.key,
    required this.expiresAt,
    this.style,
    this.expiredLabel = 'The code has expired. Request a new one.',
  });

  @override
  State<ExpiryCountdown> createState() => _ExpiryCountdownState();
}

class _ExpiryCountdownState extends State<ExpiryCountdown> {
  Timer? _timer;
  late Duration _left;

  @override
  void initState() {
    super.initState();
    _left = _remaining();
    _timer = Timer.periodic(const Duration(seconds: 1), (_) => _tick());
  }

  @override
  void didUpdateWidget(covariant ExpiryCountdown oldWidget) {
    super.didUpdateWidget(oldWidget);
    // A resend issues a new challenge — restart rather than keep counting the
    // old one down.
    if (oldWidget.expiresAt != widget.expiresAt) {
      _timer?.cancel();
      _left = _remaining();
      _timer = Timer.periodic(const Duration(seconds: 1), (_) => _tick());
    }
  }

  void _tick() {
    if (!mounted) return;
    final next = _remaining();
    setState(() => _left = next);
    if (next <= Duration.zero) _timer?.cancel();
  }

  Duration _remaining() {
    final left = widget.expiresAt.difference(DateTime.now());
    return left.isNegative ? Duration.zero : left;
  }

  @override
  void dispose() {
    _timer?.cancel();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    if (_left <= Duration.zero) {
      return Text(widget.expiredLabel, style: widget.style);
    }
    final seconds = _left.inSeconds;
    final label = '${seconds ~/ 60}:${(seconds % 60).toString().padLeft(2, '0')}';
    return Text('The code expires in $label', style: widget.style);
  }
}
