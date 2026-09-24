import 'package:flutter/material.dart';

import '../../config/theme.dart';
import '../../widgets/icons/icons.dart';

// ─── The presence disclosures ────────────────────────────────────────────────
//
// The three plain-language statements a data protection review asks to see,
// as a SINGLE-OPEN accordion: one open at a time, all closed to start, each
// animating open rather than snapping. Split from the intro gate per the
// 200-line rule. Copy is a lockstep mirror of the web and RN SDKs.

class _Disclosure {
  final MyazaIconData icon;
  final String title;
  final String body;
  const _Disclosure(this.icon, this.title, this.body);
}

const _kHowItWorksForeground =
    'After you finish, your device periodically confirms it is at this address '
    'over the coming days. Only day-level summaries ever leave your phone, '
    'never your movements.';
const _kHowItWorksBackground =
    'After you finish, your phone confirms it is at this address over the '
    'coming days, even when the app is closed. Only day-level summaries ever '
    'leave your phone, never your movements.';

List<_Disclosure> _disclosuresFor(bool background) => [
  _Disclosure(
    MyazaIcons.circleHelp,
    'How it works',
    background ? _kHowItWorksBackground : _kHowItWorksForeground,
  ),
  const _Disclosure(
    MyazaIcons.slidersHorizontal,
    'You stay in control',
    'You can turn location off at any time in your device settings. An '
        'unfinished check simply expires. It never counts against you.',
  ),
  const _Disclosure(
    MyazaIcons.shieldCheck,
    'Your data is protected',
    "Location summaries are used only to confirm this address and are handled "
        "under your country's data protection rules.",
  ),
];

class AddressIntroDisclosures extends StatefulWidget {
  /// The workflow opts into OS geofencing: the copy says the app can be closed.
  final bool background;

  const AddressIntroDisclosures({super.key, this.background = false});

  @override
  State<AddressIntroDisclosures> createState() =>
      _AddressIntroDisclosuresState();
}

class _AddressIntroDisclosuresState extends State<AddressIntroDisclosures> {
  int? _open;

  @override
  Widget build(BuildContext context) {
    final colors = context.myazaColors;
    final disclosures = _disclosuresFor(widget.background);
    return Container(
      clipBehavior: Clip.antiAlias,
      decoration: BoxDecoration(
        border: Border.all(color: colors.border),
        borderRadius: BorderRadius.circular(MyazaRadius.md),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          for (var i = 0; i < disclosures.length; i++)
            _DisclosureRow(
              disclosure: disclosures[i],
              open: _open == i,
              last: i == disclosures.length - 1,
              onTap: () => setState(() => _open = _open == i ? null : i),
            ),
        ],
      ),
    );
  }
}

class _DisclosureRow extends StatelessWidget {
  final _Disclosure disclosure;
  final bool open;
  final bool last;
  final VoidCallback onTap;

  const _DisclosureRow({
    required this.disclosure,
    required this.open,
    required this.last,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    final colors = context.myazaColors;
    final text = context.myazaText;
    return DecoratedBox(
      decoration: BoxDecoration(
        border: last
            ? null
            : Border(bottom: BorderSide(color: colors.border)),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Semantics(
            button: true,
            expanded: open,
            child: InkWell(
              onTap: onTap,
              child: Padding(
                padding: const EdgeInsets.symmetric(
                    horizontal: 14, vertical: MyazaSpacing.sm + 4),
                child: Row(
                  children: [
                    AnimatedContainer(
                      duration: const Duration(milliseconds: 300),
                      width: 28,
                      height: 28,
                      alignment: Alignment.center,
                      decoration: BoxDecoration(
                        color: open
                            ? colors.primary.withValues(alpha: 0.15)
                            : colors.backgroundSecondary,
                        borderRadius: BorderRadius.circular(MyazaRadius.xs),
                      ),
                      child: MyazaIcon(disclosure.icon,
                          size: 16,
                          color:
                              open ? colors.primary : colors.textSecondary),
                    ),
                    const SizedBox(width: 10),
                    Expanded(
                      child: Text(disclosure.title,
                          style: text.label.copyWith(fontWeight: FontWeight.w500)),
                    ),
                    AnimatedRotation(
                      turns: open ? 0.5 : 0,
                      duration: const Duration(milliseconds: 300),
                      curve: Curves.easeOut,
                      child: MyazaIcon(MyazaIcons.chevronDown,
                          size: 16, color: colors.textSecondary),
                    ),
                  ],
                ),
              ),
            ),
          ),
          // The body animates its height rather than snapping: the accordion
          // is the consent artefact, and a panel that jumps reads as a glitch
          // on the one screen that has to look considered.
          AnimatedSize(
            duration: const Duration(milliseconds: 300),
            curve: Curves.easeOut,
            alignment: Alignment.topCenter,
            child: open
                ? Padding(
                    padding: const EdgeInsets.fromLTRB(52, 0, 14, 14),
                    child: Text(
                      disclosure.body,
                      style: text.bodyMedium
                          .copyWith(color: colors.textSecondary, height: 1.5),
                    ),
                  )
                : const SizedBox(width: double.infinity),
          ),
        ],
      ),
    );
  }
}
