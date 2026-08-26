import 'package:flutter/material.dart';
import 'package:lucide_icons_flutter/lucide_icons.dart';

import '../config/theme.dart';
import 'themed_sheet.dart';

// ─── Select ───────────────────────────────────────────────────────────────────
//
// A themed select field that opens its options as a BOTTOM SHEET instead of
// Material's floating menu. Two reasons: the popup menu is a separate route so
// it never inherits the SDK palette (it renders light over a dark flow), and a
// sheet with full-width rows is the right target size on a phone.
//
// Use this for every option list in the flow — questionnaire selects, currency
// pickers, document types.

class MyazaSelectOption<T> {
  final T value;
  final String label;

  /// Optional icon/flag shown before the label (field and sheet row alike).
  final Widget? leading;

  /// Secondary line under the label, shown in the SHEET only — the collapsed
  /// field stays as short as its label. Currency codes need it: "GHS" and
  /// "GMD" are one letter apart and mean different money.
  final String? description;

  const MyazaSelectOption({
    required this.value,
    required this.label,
    this.leading,
    this.description,
  });
}

class MyazaSelect<T> extends StatelessWidget {
  final T? value;
  final List<MyazaSelectOption<T>> options;
  final ValueChanged<T> onChanged;

  /// Shown when nothing is selected yet.
  final String hint;

  /// Sheet header; falls back to [hint].
  final String? sheetTitle;

  final bool enabled;

  /// Narrow variant used for inline pickers (e.g. a currency beside an amount)
  /// — shrinks to its content instead of filling the row.
  final bool compact;

  /// Pin a search field to the top of the sheet, filtering options by label —
  /// for lists too long to scroll (the every-ISO-country selects). Mirrors the
  /// RN SDK's `searchable`.
  final bool searchable;

  const MyazaSelect({
    super.key,
    required this.value,
    required this.options,
    required this.onChanged,
    this.hint = 'Select an option',
    this.sheetTitle,
    this.enabled = true,
    this.compact = false,
    this.searchable = false,
  });

  MyazaSelectOption<T>? get _selected {
    for (final o in options) {
      if (o.value == value) return o;
    }
    return null;
  }

  Future<void> _open(BuildContext context) async {
    if (!enabled || options.isEmpty) return;
    final picked = await showMyazaSheet<T>(
      context,
      isScrollControlled: true,
      builder: (sheetContext) => _OptionsSheet<T>(
        title: sheetTitle ?? hint,
        options: options,
        selected: value,
        searchable: searchable,
      ),
    );
    if (picked != null) onChanged(picked);
  }

  @override
  Widget build(BuildContext context) {
    final colors = context.myazaColors;
    final text = context.myazaText;
    final selected = _selected;
    final label = selected?.label;

    final field = Container(
      padding: EdgeInsets.symmetric(
        horizontal: MyazaSpacing.md,
        vertical: compact ? 12 : MyazaSpacing.md,
      ),
      decoration: BoxDecoration(
        color: enabled ? colors.background : colors.backgroundSecondary,
        border: Border.all(color: colors.border),
        borderRadius: BorderRadius.circular(MyazaRadius.sm),
      ),
      child: Row(
        mainAxisSize: compact ? MainAxisSize.min : MainAxisSize.max,
        children: [
          if (selected?.leading != null) ...[
            selected!.leading!,
            const SizedBox(width: MyazaSpacing.sm),
          ],
          compact
              ? Text(label ?? hint, style: text.label)
              : Expanded(
                  child: Text(
                    label ?? hint,
                    overflow: TextOverflow.ellipsis,
                    style: label == null
                        ? text.label.copyWith(color: colors.textMuted)
                        : text.label,
                  ),
                ),
          const SizedBox(width: MyazaSpacing.sm),
          Icon(LucideIcons.chevronDown, size: 18, color: colors.textSecondary),
        ],
      ),
    );

    return Material(
      color: Colors.transparent,
      child: InkWell(
        onTap: enabled ? () => _open(context) : null,
        borderRadius: BorderRadius.circular(MyazaRadius.sm),
        child: field,
      ),
    );
  }
}

class _OptionsSheet<T> extends StatefulWidget {
  final String title;
  final List<MyazaSelectOption<T>> options;
  final T? selected;
  final bool searchable;

  const _OptionsSheet({
    required this.title,
    required this.options,
    required this.selected,
    this.searchable = false,
  });

  @override
  State<_OptionsSheet<T>> createState() => _OptionsSheetState<T>();
}

class _OptionsSheetState<T> extends State<_OptionsSheet<T>> {
  String _query = '';

  @override
  Widget build(BuildContext context) {
    final colors = context.myazaColors;
    final text = context.myazaText;
    final selected = widget.selected;

    final normalized = _query.trim().toLowerCase();
    final visible = widget.searchable && normalized.isNotEmpty
        ? widget.options
            .where((o) => o.label.toLowerCase().contains(normalized))
            .toList(growable: false)
        : widget.options;

    return SafeArea(
      top: false,
      child: ConstrainedBox(
        // Long option lists stay inside the sheet and scroll.
        constraints: BoxConstraints(
          maxHeight: MediaQuery.of(context).size.height * 0.6,
        ),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Padding(
              // Tight under the handle, the way the system sheets set a title.
              // The `lg` that was here stood in for a header that did not
              // exist; with one above it, it reads as a gap.
              padding: const EdgeInsets.fromLTRB(
                MyazaSpacing.md,
                0,
                MyazaSpacing.md,
                MyazaSpacing.sm,
              ),
              child: Text(
                widget.title,
                style: text.label.copyWith(fontWeight: FontWeight.w700),
              ),
            ),
            if (widget.searchable)
              // Pinned above the list, so it stays put while results scroll.
              Padding(
                padding: const EdgeInsets.fromLTRB(
                  MyazaSpacing.md,
                  0,
                  MyazaSpacing.md,
                  MyazaSpacing.sm,
                ),
                child: TextField(
                  autofocus: false,
                  autocorrect: false,
                  onChanged: (value) => setState(() => _query = value),
                  style: text.label,
                  decoration: InputDecoration(
                    hintText: 'Search',
                    hintStyle: text.label.copyWith(color: colors.textMuted),
                    prefixIcon: Icon(LucideIcons.search,
                        size: 16, color: colors.textMuted),
                    isDense: true,
                    filled: true,
                    fillColor: colors.backgroundSecondary,
                    contentPadding: const EdgeInsets.symmetric(
                      horizontal: MyazaSpacing.sm,
                      vertical: 10,
                    ),
                    enabledBorder: OutlineInputBorder(
                      borderRadius: BorderRadius.circular(MyazaRadius.sm),
                      borderSide: BorderSide(color: colors.border),
                    ),
                    focusedBorder: OutlineInputBorder(
                      borderRadius: BorderRadius.circular(MyazaRadius.sm),
                      borderSide: BorderSide(color: colors.primary),
                    ),
                  ),
                ),
              ),
            if (visible.isEmpty)
              Padding(
                padding: const EdgeInsets.all(MyazaSpacing.md),
                child: Text(
                  'No matches',
                  textAlign: TextAlign.center,
                  style: text.bodySmall.copyWith(color: colors.textMuted),
                ),
              ),
            Flexible(
              child: ListView.builder(
                shrinkWrap: true,
                padding: const EdgeInsets.only(bottom: MyazaSpacing.sm),
                itemCount: visible.length,
                itemBuilder: (context, i) {
                  final option = visible[i];
                  final isSelected = option.value == selected;
                  return InkWell(
                    onTap: () => Navigator.of(context).pop(option.value),
                    child: Padding(
                      padding: const EdgeInsets.symmetric(
                        horizontal: MyazaSpacing.md,
                        vertical: MyazaSpacing.md,
                      ),
                      child: Row(
                        children: [
                          if (option.leading != null) ...[
                            option.leading!,
                            const SizedBox(width: MyazaSpacing.sm),
                          ],
                          Expanded(
                            child: Column(
                              crossAxisAlignment: CrossAxisAlignment.start,
                              mainAxisSize: MainAxisSize.min,
                              children: [
                                Text(
                                  option.label,
                                  style: text.label.copyWith(
                                    fontWeight: isSelected
                                        ? FontWeight.w600
                                        : FontWeight.w400,
                                    color: isSelected ? colors.primary : null,
                                  ),
                                ),
                                if (option.description != null)
                                  Text(
                                    option.description!,
                                    style: text.bodySmall.copyWith(
                                      color: colors.textSecondary,
                                    ),
                                    maxLines: 1,
                                    overflow: TextOverflow.ellipsis,
                                  ),
                              ],
                            ),
                          ),
                          if (isSelected)
                            Icon(LucideIcons.check,
                                size: 18, color: colors.primary),
                        ],
                      ),
                    ),
                  );
                },
              ),
            ),
          ],
        ),
      ),
    );
  }
}
