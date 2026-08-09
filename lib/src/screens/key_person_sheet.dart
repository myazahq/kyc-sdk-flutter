import 'package:flutter/material.dart';
import 'package:lucide_icons_flutter/lucide_icons.dart';

import '../config/business_application.dart';
import '../config/theme.dart';
import '../widgets/myaza_button.dart';
import '../widgets/themed_sheet.dart';
import 'key_person_form.dart';

// ─── Add/edit key-person sheet ───────────────────────────────────────────────
//
// The list step stays a clean stack of summary cards; the FORM lives here —
// slide-up sheet, grab handle, the five fields, and a pinned primary action.
// Editing adds a visually separated destructive "Remove this person" beneath
// the save (never beside it — HIG destructive separation).
//
// Save is enabled once the draft is valid. A combined-ownership overshoot
// WARNS here but never blocks saving — the fix may live on a different
// person's %, and trapping the user inside this sheet would force them to
// discard their work to go adjust it.
//
// Mirrors the web SDK's KeyPersonSheet and the RN SDK's KeyPersonSheet 1:1.

sealed class KeyPersonSheetResult {
  const KeyPersonSheetResult();
}

class KeyPersonSaved extends KeyPersonSheetResult {
  final KeyPersonEntry entry;
  const KeyPersonSaved(this.entry);
}

class KeyPersonRemoved extends KeyPersonSheetResult {
  const KeyPersonRemoved();
}

/// Opens the sheet; resolves with the outcome (null = dismissed unchanged).
Future<KeyPersonSheetResult?> showKeyPersonSheet(
  BuildContext context, {
  required bool editing,
  required KeyPersonEntry initial,
  double uboThreshold = 25,
  required double otherPctTotal,
}) {
  return showMyazaSheet<KeyPersonSheetResult>(
    context,
    isScrollControlled: true,
    builder: (_) => _KeyPersonSheetBody(
      editing: editing,
      initial: initial,
      uboThreshold: uboThreshold,
      otherPctTotal: otherPctTotal,
    ),
  );
}

class _KeyPersonSheetBody extends StatefulWidget {
  final bool editing;
  final KeyPersonEntry initial;
  final double uboThreshold;

  /// Sum of every OTHER person's ownership % — for the combined warning.
  final double otherPctTotal;

  const _KeyPersonSheetBody({
    required this.editing,
    required this.initial,
    required this.uboThreshold,
    required this.otherPctTotal,
  });

  @override
  State<_KeyPersonSheetBody> createState() => _KeyPersonSheetBodyState();
}

class _KeyPersonSheetBodyState extends State<_KeyPersonSheetBody> {
  late KeyPersonEntry _draft;
  late final TextEditingController _name;
  late final TextEditingController _email;
  late final TextEditingController _pct;

  @override
  void initState() {
    super.initState();
    _draft = widget.initial;
    _name = TextEditingController(text: _draft.name);
    _email = TextEditingController(text: _draft.email);
    _pct = TextEditingController(text: _draft.ownershipPct);
  }

  @override
  void dispose() {
    _name.dispose();
    _email.dispose();
    _pct.dispose();
    super.dispose();
  }

  String _fmtPct(double n) =>
      n == n.roundToDouble() ? n.round().toString() : n.toStringAsFixed(1);

  @override
  Widget build(BuildContext context) {
    final colors = context.myazaColors;
    final text = context.myazaText;

    final draftPct = _draft.ownershipValue;
    final combinedTotal = widget.otherPctTotal + (draftPct ?? 0);
    final combinedPctError = combinedTotal > 100
        ? 'Combined ownership would be ${_fmtPct(combinedTotal)}% — over by '
            '${_fmtPct(combinedTotal - 100)}%.'
        : null;
    final canSave = _draft.isValid;

    // The sheet is lifted above the keyboard and sized against the space that
    // remains, so the focused field is never underneath the keys.
    return Padding(
      padding:
          EdgeInsets.only(bottom: MediaQuery.viewInsetsOf(context).bottom),
      child: SafeArea(
        top: false,
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            const SizedBox(height: MyazaSpacing.sm),
            Center(
              child: Container(
                width: 36,
                height: 4,
                decoration: BoxDecoration(
                  color: colors.border,
                  borderRadius: BorderRadius.circular(MyazaRadius.full),
                ),
              ),
            ),
            Padding(
              padding: const EdgeInsets.fromLTRB(
                MyazaSpacing.md,
                MyazaSpacing.sm + 4,
                MyazaSpacing.md,
                MyazaSpacing.sm,
              ),
              child: Row(
                children: [
                  Expanded(
                    child: Text(
                      widget.editing ? 'Edit person' : 'Add a person',
                      style: text.body.copyWith(fontWeight: FontWeight.w700),
                    ),
                  ),
                  IconButton(
                    onPressed: () => Navigator.of(context).pop(),
                    visualDensity: VisualDensity.compact,
                    tooltip: 'Close',
                    icon: Icon(LucideIcons.x,
                        size: 20, color: colors.textSecondary),
                  ),
                ],
              ),
            ),
            Flexible(
              child: SingleChildScrollView(
                keyboardDismissBehavior:
                    ScrollViewKeyboardDismissBehavior.onDrag,
                padding: const EdgeInsets.symmetric(
                    horizontal: MyazaSpacing.md),
                child: KeyPersonForm(
                  entry: _draft,
                  nameCtrl: _name,
                  emailCtrl: _email,
                  pctCtrl: _pct,
                  uboThreshold: widget.uboThreshold,
                  combinedPctError: combinedPctError,
                  onChange: (entry) => setState(() => _draft = entry),
                ),
              ),
            ),
            Padding(
              padding: const EdgeInsets.fromLTRB(
                MyazaSpacing.md,
                MyazaSpacing.sm,
                MyazaSpacing.md,
                MyazaSpacing.lg,
              ),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  MyazaButton(
                    label: widget.editing ? 'Save changes' : 'Add person',
                    onPressed: canSave
                        ? () => Navigator.of(context)
                            .pop(KeyPersonSaved(_draft))
                        : null,
                  ),
                  if (widget.editing) ...[
                    const SizedBox(height: MyazaSpacing.xs),
                    SizedBox(
                      height: 44,
                      child: TextButton(
                        onPressed: () => Navigator.of(context)
                            .pop(const KeyPersonRemoved()),
                        child: Text(
                          'Remove this person',
                          style: text.bodySmall.copyWith(
                            color: MyazaColors.error,
                            fontWeight: FontWeight.w600,
                          ),
                        ),
                      ),
                    ),
                  ],
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }
}
