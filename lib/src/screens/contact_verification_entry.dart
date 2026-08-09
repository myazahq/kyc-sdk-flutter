import 'package:flutter/material.dart';

import 'contact_verification_channel.dart';
import 'contact_verification_parts.dart';

// ─── Contact verification — destination entry ─────────────────────────────────
//
// The first half of the step, composed as one widget so the screen has a single
// child per phase. Split from contact_verification_parts.dart to keep both
// files inside the 200-line limit.

/// The first half of the step: where to send the code, and — when the workflow
/// offers a choice — how. One widget so the screen composes a single child.
class ContactEntryPanel extends StatelessWidget {
  final bool isPhone;
  final TextEditingController emailController;
  final String defaultCountry;
  final bool enabled;
  final ValueChanged<String> onEmailChanged;
  final void Function(String e164, bool isValid) onPhoneChanged;
  final List<String> offeredChannels;
  final String pickedChannel;
  final ValueChanged<String> onPickChannel;

  const ContactEntryPanel({
    super.key,
    required this.isPhone,
    required this.emailController,
    required this.defaultCountry,
    required this.enabled,
    required this.onEmailChanged,
    required this.onPhoneChanged,
    required this.offeredChannels,
    required this.pickedChannel,
    required this.onPickChannel,
  });

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        ContactDestinationField(
          isPhone: isPhone,
          emailController: emailController,
          defaultCountry: defaultCountry,
          enabled: enabled,
          onEmailChanged: onEmailChanged,
          onPhoneChanged: onPhoneChanged,
        ),
        ContactChannelChoice(
          offered: offeredChannels,
          picked: pickedChannel,
          enabled: enabled,
          onPick: onPickChannel,
        ),
      ],
    );
  }
}
