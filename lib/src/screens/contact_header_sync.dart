import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../providers/kyc_provider.dart';

// ─── Contact verification — header sync ───────────────────────────────────────
//
// A zero-size widget whose only job is to mirror the contact screen's state up
// to the notifier, so the sheet HEADER (rendered by the shell, which cannot see
// the screen's state) can caption what is happening: which channel is in play,
// and the destination once a code is actually out.
//
// A widget rather than calls scattered through the screen: it re-syncs on every
// rebuild, so mounting, sending, picking a different channel and navigating back
// are all covered by one line at the call site instead of four call sites that
// can each be forgotten.

class ContactHeaderSync extends ConsumerWidget {
  /// 'email' | 'phone' — the step doing the reporting.
  final String channel;

  /// Delivery channel in play; empty for email, which has no choice.
  final String via;

  /// Empty until a code is actually out.
  final String destination;

  const ContactHeaderSync({
    super.key,
    required this.channel,
    required this.via,
    required this.destination,
  });

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    // Post-frame because a provider cannot be written during a build.
    // setContactHeader no-ops when nothing changed, so this costs nothing on
    // the rebuilds where the answer is the same.
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!context.mounted) return;
      ref.read(kYCNotifierProvider.notifier).setContactHeader(
            channel: channel,
            via: via,
            destination: destination,
          );
    });
    return const SizedBox.shrink();
  }
}
