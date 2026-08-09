import 'package:flutter/material.dart';
import 'package:lucide_icons_flutter/lucide_icons.dart';

import '../config/theme.dart';
import '../widgets/whatsapp_icon.dart';

// ─── Contact verification — delivery-channel choice ───────────────────────────
//
// How the user wants their one-time code delivered.
//
// The org decides which channels are ON OFFER; the person receiving the code
// decides between them, because only they know whether they have WhatsApp
// installed or whether SMS is reaching them today. With a single offered
// channel there is no choice to make and this renders nothing.
//
// Styling mirrors CountryOptionTile (bordered card, primary tint when picked)
// so every "choose one" surface in the SDK looks the same.

const Map<String, String> kChannelLabels = {
  'sms': 'SMS',
  'whatsapp': 'WhatsApp',
};

const Map<String, String> _kChannelHints = {
  'sms': 'Text message',
  'whatsapp': 'Needs WhatsApp',
};

/// WhatsApp needs its own brand mark; SMS reads fine as a generic glyph.
Widget _channelGlyph(String channel, Color color) => channel == 'whatsapp'
    ? WhatsAppIcon(color: color, size: 16)
    : Icon(LucideIcons.messageSquare, size: 16, color: color);

class ContactChannelChoice extends StatelessWidget {
  final List<String> offered;
  final String picked;
  final bool enabled;
  final ValueChanged<String> onPick;

  const ContactChannelChoice({
    super.key,
    required this.offered,
    required this.picked,
    required this.onPick,
    this.enabled = true,
  });

  @override
  Widget build(BuildContext context) {
    if (offered.length < 2) return const SizedBox.shrink();
    final text = context.myazaText;
    final colors = context.myazaColors;

    return Padding(
      padding: const EdgeInsets.only(top: MyazaSpacing.md),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Text('How should we send it?',
              style: text.bodySmall.copyWith(color: colors.textSecondary)),
          const SizedBox(height: MyazaSpacing.sm),
          Row(
            children: [
              for (final channel in offered) ...[
                Expanded(
                  child: _ChannelTile(
                    label: kChannelLabels[channel] ?? channel,
                    channel: channel,
                    hint: _kChannelHints[channel] ?? '',
                    isSelected: picked == channel,
                    onTap: enabled ? () => onPick(channel) : null,
                  ),
                ),
                if (channel != offered.last)
                  const SizedBox(width: MyazaSpacing.sm),
              ],
            ],
          ),
        ],
      ),
    );
  }
}

class _ChannelTile extends StatelessWidget {
  final String label;
  final String hint;
  final String channel;
  final bool isSelected;
  final VoidCallback? onTap;

  const _ChannelTile({
    required this.label,
    required this.hint,
    required this.channel,
    required this.isSelected,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    final colors = context.myazaColors;
    final text = context.myazaText;
    final radius = BorderRadius.circular(MyazaRadius.md);

    return AnimatedContainer(
      duration: const Duration(milliseconds: 150),
      decoration: BoxDecoration(
        color: isSelected ? colors.primary50 : colors.background,
        borderRadius: radius,
        border: Border.all(
          color: isSelected ? colors.primary : colors.border,
          width: isSelected ? 1.5 : 1.0,
        ),
      ),
      child: Material(
        color: Colors.transparent,
        child: InkWell(
          onTap: onTap,
          borderRadius: radius,
          child: Padding(
            padding: const EdgeInsets.symmetric(
              vertical: MyazaSpacing.sm + 2,
              horizontal: MyazaSpacing.sm,
            ),
            child: Row(
              children: [
                Container(
                  width: 34,
                  height: 34,
                  decoration: BoxDecoration(
                    color: isSelected
                        ? colors.primary.withValues(alpha: 0.1)
                        : colors.backgroundSecondary,
                    borderRadius: BorderRadius.circular(MyazaRadius.sm),
                  ),
                  child: Center(
                    child: _channelGlyph(
                      channel,
                      isSelected ? colors.primary : colors.textSecondary,
                    ),
                  ),
                ),
                const SizedBox(width: MyazaSpacing.sm),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      Text(
                        label,
                        style: text.bodyMedium
                            .copyWith(fontWeight: FontWeight.w600),
                      ),
                      Text(
                        hint,
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: text.bodySmall
                            .copyWith(color: colors.textSecondary),
                      ),
                    ],
                  ),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}
