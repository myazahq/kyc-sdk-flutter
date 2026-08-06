import 'package:flutter/material.dart';
import 'package:lucide_icons_flutter/lucide_icons.dart';

import '../config/dial_codes.g.dart';
import '../config/id_types.dart' show countryLabel;
import '../config/theme.dart';
import 'country_flag.dart';
import 'myaza_input.dart';
import 'themed_sheet.dart';

// ─── Dial-code picker ─────────────────────────────────────────────────────────
//
// Country + international dialling code chooser for the phone field. Presented
// through [showMyazaSheet] so it carries the SDK palette — a plain
// showModalBottomSheet lands on a sibling route where the theme extension isn't
// found, and renders light over a dark flow.
//
// Height is bounded against the space left ABOVE the keyboard. The search field
// autofocuses, so sizing against the full screen (as this used to) made the
// sheet effectively full-screen the moment the keys appeared.

/// Opens the picker; resolves to the chosen ISO-2 code, or null if dismissed.
Future<String?> showDialCodePicker(BuildContext context, String selected) =>
    showMyazaSheet<String>(
      context,
      isScrollControlled: true,
      builder: (_) => _DialCodeSheet(selected: selected),
    );

class _DialCodeSheet extends StatefulWidget {
  final String selected;
  const _DialCodeSheet({required this.selected});

  @override
  State<_DialCodeSheet> createState() => _DialCodeSheetState();
}

class _DialCodeSheetState extends State<_DialCodeSheet> {
  String _query = '';

  @override
  Widget build(BuildContext context) {
    final colors = context.myazaColors;
    final text = context.myazaText;
    final media = MediaQuery.of(context);
    final q = _query.trim().toLowerCase();

    final entries = kDialCodes.keys
        .map((iso) =>
            (iso: iso, name: countryLabel(iso), dial: kDialCodes[iso]!))
        .where((e) =>
            q.isEmpty ||
            e.name.toLowerCase().contains(q) ||
            e.dial.contains(q) ||
            e.iso.toLowerCase().contains(q))
        .toList()
      ..sort((a, b) => a.name.toLowerCase().compareTo(b.name.toLowerCase()));

    // Space actually available above the keyboard, then capped so the sheet
    // stays a sheet rather than swallowing the screen.
    final available = media.size.height - media.viewInsets.bottom;
    final maxHeight = (available * 0.85).clamp(240.0, media.size.height * 0.6);

    return Padding(
      padding: EdgeInsets.only(bottom: media.viewInsets.bottom),
      child: SafeArea(
        top: false,
        child: ConstrainedBox(
          constraints: BoxConstraints(maxHeight: maxHeight),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              Padding(
                padding: const EdgeInsets.fromLTRB(
                  MyazaSpacing.md,
                  MyazaSpacing.md,
                  MyazaSpacing.md,
                  MyazaSpacing.sm,
                ),
                child: MyazaInput(
                  hint: 'Search country or code',
                  autofocus: true,
                  prefix: Icon(LucideIcons.search,
                      size: 18, color: colors.textSecondary),
                  onChanged: (v) => setState(() => _query = v),
                ),
              ),
              Flexible(
                child: entries.isEmpty
                    ? Padding(
                        padding: const EdgeInsets.all(MyazaSpacing.lg),
                        child: Text('No countries match your search.',
                            style: text.bodyMedium),
                      )
                    : ListView.builder(
                        padding: const EdgeInsets.only(bottom: MyazaSpacing.sm),
                        itemCount: entries.length,
                        itemBuilder: (_, i) {
                          final e = entries[i];
                          final isSelected = e.iso == widget.selected;
                          return Material(
                            color: isSelected
                                ? colors.primary50
                                : Colors.transparent,
                            child: InkWell(
                              onTap: () => Navigator.of(context).pop(e.iso),
                              child: Padding(
                                padding: const EdgeInsets.symmetric(
                                  horizontal: MyazaSpacing.md,
                                  vertical: MyazaSpacing.sm,
                                ),
                                child: Row(
                                  children: [
                                    MyazaCountryFlag(country: e.iso, size: 24),
                                    const SizedBox(width: MyazaSpacing.md),
                                    Expanded(
                                      child: Text(e.name,
                                          style: text.bodyMedium),
                                    ),
                                    Text('+${e.dial}',
                                        style: text.label.copyWith(
                                            color: colors.textSecondary)),
                                  ],
                                ),
                              ),
                            ),
                          );
                        },
                      ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}
