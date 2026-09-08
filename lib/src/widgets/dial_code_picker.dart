import 'package:flutter/material.dart';
import 'package:lucide_icons_flutter/lucide_icons.dart';

import '../config/country_names.g.dart';
import '../config/dial_codes.g.dart';
import '../config/id_types.dart' show countryLabel;
import '../config/theme.dart';
import 'dial_code_row.dart';
import 'dial_code_rows.dart';
import 'myaza_input.dart';
import 'themed_sheet.dart';

// ─── Country / dial-code picker ───────────────────────────────────────────────
//
// Country + international dialling code chooser for the phone field — and,
// with the dial column off, THE country picker (the key-people "where their
// ID was issued" field). One sheet for both, so the two feel identical.
// Presented through [showMyazaSheet] so it carries the SDK palette — a plain
// showModalBottomSheet lands on a sibling route where the theme extension isn't
// found, and renders light over a dark flow.
//
// Height is bounded against the space left ABOVE the keyboard: once someone
// taps into search, sizing against the full screen (as this used to) made the
// sheet effectively full-screen the moment the keys appeared — with the
// filtered results hidden underneath them.
//
// The list itself (the pinned geo row, the optional region headers) is built
// by dial_code_rows.dart; this file only renders it.

/// Opens the picker; resolves to the chosen ISO-2 code, or null if dismissed.
///
/// [pinned] is the visitor's IP country, lifted out of the alphabet to the top
/// of the list and tagged, so a guess we made on their behalf is visible AS a
/// guess and one tap away rather than buried among two hundred others.
Future<String?> showDialCodePicker(
  BuildContext context,
  String selected, {
  String? pinned,
}) =>
    showMyazaSheet<String>(
      context,
      isScrollControlled: true,
      builder: (_) => _DialCodeSheet(selected: selected, pinned: pinned),
    );

/// Opens a plain country picker (no dial codes) — the SAME sheet as the phone
/// field's. Over every ISO country we can name, or a restricted [codes] subset
/// (a workflow's registry countries). [pinned] lifts the visitor's inferred
/// country to the top as "Your location"; [grouped] lists the rest under
/// region headers, the country-select step's way (the address-scope country
/// control asks for both).
Future<String?> showCountryPicker(
  BuildContext context,
  String? selected, {
  Iterable<String>? codes,
  String? pinned,
  bool grouped = false,
}) =>
    showMyazaSheet<String>(
      context,
      isScrollControlled: true,
      builder: (_) => _DialCodeSheet(
        selected: selected ?? '',
        showDial: false,
        codes: codes,
        pinned: pinned,
        grouped: grouped,
      ),
    );

class _DialCodeSheet extends StatefulWidget {
  final String selected;

  /// False ⇒ plain country picker: every named country, no dial column.
  final bool showDial;

  /// Restricts the country list (plain picker only). Null ⇒ all named ISO.
  final Iterable<String>? codes;

  /// The visitor's IP country, pinned to the top (still subject to search).
  final String? pinned;

  /// Region headers between the rows (the pinned row stays on top).
  final bool grouped;

  const _DialCodeSheet({
    required this.selected,
    this.showDial = true,
    this.codes,
    this.pinned,
    this.grouped = false,
  });

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

    final codes = widget.showDial
        ? kDialCodes.keys
        : (widget.codes ?? kCountryNames.keys);
    final entries = codes
        .map<DialCodeEntry>((iso) => (
              iso: iso,
              name: countryLabel(iso),
              dial: widget.showDial ? kDialCodes[iso]! : '',
            ))
        .where((e) =>
            q.isEmpty ||
            e.name.toLowerCase().contains(q) ||
            (widget.showDial && e.dial.contains(q)) ||
            e.iso.toLowerCase().contains(q))
        .toList()
      ..sort((a, b) => a.name.toLowerCase().compareTo(b.name.toLowerCase()));
    final items =
        buildDialCodeItems(entries, widget.pinned, grouped: widget.grouped);

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
                // Deliberately NOT autofocused: springing the keyboard the
                // instant the sheet opens hides half the list before the
                // person has even seen it - search is one tap away.
                child: MyazaInput(
                  hint: widget.showDial ? 'Search country or code' : 'Search country',
                  prefix: Icon(LucideIcons.search,
                      size: 18, color: colors.textSecondary),
                  onChanged: (v) => setState(() => _query = v),
                ),
              ),
              Flexible(
                child: items.isEmpty
                    ? Padding(
                        padding: const EdgeInsets.all(MyazaSpacing.lg),
                        child: Text('No countries match your search.',
                            style: text.bodyMedium),
                      )
                    : ListView.builder(
                        padding: const EdgeInsets.only(bottom: MyazaSpacing.sm),
                        itemCount: items.length,
                        itemBuilder: (_, i) => switch (items[i]) {
                          DialCodeHeaderItem(:final region) =>
                            DialCodeRegionHeader(region: region),
                          DialCodeRowItem(:final entry, :final pinned) =>
                            _row(entry, pinned, items.length),
                        },
                      ),
              ),
            ],
          ),
        ),
      ),
    );
  }

  Widget _row(DialCodeEntry e, bool isPinned, int count) {
    final row = DialCodeRow(
      iso: e.iso,
      name: e.name,
      dial: e.dial,
      isSelected: e.iso == widget.selected,
      badge: isPinned ? 'Your location' : null,
      onTap: () => Navigator.of(context).pop(e.iso),
    );
    // A hairline under the pinned row only: the list below it is one list,
    // and a rule between every row is noise.
    if (!isPinned || count == 1) return row;
    return Column(
      mainAxisSize: MainAxisSize.min,
      children: [row, const DialCodeDivider()],
    );
  }
}
