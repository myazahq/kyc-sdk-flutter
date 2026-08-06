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

  const MyazaSelectOption({
    required this.value,
    required this.label,
    this.leading,
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

  const MyazaSelect({
    super.key,
    required this.value,
    required this.options,
    required this.onChanged,
    this.hint = 'Select an option',
    this.sheetTitle,
    this.enabled = true,
    this.compact = false,
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

class _OptionsSheet<T> extends StatelessWidget {
  final String title;
  final List<MyazaSelectOption<T>> options;
  final T? selected;

  const _OptionsSheet({
    required this.title,
    required this.options,
    required this.selected,
  });

  @override
  Widget build(BuildContext context) {
    final colors = context.myazaColors;
    final text = context.myazaText;

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
              padding: const EdgeInsets.fromLTRB(
                MyazaSpacing.md,
                MyazaSpacing.lg,
                MyazaSpacing.md,
                MyazaSpacing.sm,
              ),
              child: Text(
                title,
                style: text.label.copyWith(fontWeight: FontWeight.w700),
              ),
            ),
            Flexible(
              child: ListView.builder(
                shrinkWrap: true,
                padding: const EdgeInsets.only(bottom: MyazaSpacing.sm),
                itemCount: options.length,
                itemBuilder: (context, i) {
                  final option = options[i];
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
                            child: Text(
                              option.label,
                              style: text.label.copyWith(
                                fontWeight: isSelected
                                    ? FontWeight.w600
                                    : FontWeight.w400,
                                color: isSelected ? colors.primary : null,
                              ),
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
