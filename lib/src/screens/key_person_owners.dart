import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../config/business_application.dart';
import '../config/theme.dart';
import '../widgets/myaza_input.dart';

// ─── Who owns this company ───────────────────────────────────────────────────
//
// A beneficial owner is a natural person, so a corporate shareholder is a
// branch of the ownership chain that stops at a legal entity. Where the company
// is registered somewhere we can look up, the server follows it. Where it is
// not — a foreign parent, an offshore vehicle — this is the only route to the
// people above it, and asking is better than recording nothing.
//
// Deliberately short: a name and a share. Everything else about them is
// unknowable to the person filling in this form, and a longer list is one
// people abandon.

const _maxOwners = 10;

class KeyPersonOwners extends StatefulWidget {
  final List<KeyPersonOwnerEntry> owners;
  final String companyName;
  final ValueChanged<List<KeyPersonOwnerEntry>> onChanged;

  const KeyPersonOwners({
    super.key,
    required this.owners,
    required this.companyName,
    required this.onChanged,
  });

  @override
  State<KeyPersonOwners> createState() => _KeyPersonOwnersState();
}

class _KeyPersonOwnersState extends State<KeyPersonOwners> {
  // One controller per field, kept across rebuilds so typing does not reset the
  // caret. Rows are dynamic, so the sheet cannot own these the way it owns the
  // fixed fields above.
  final _controllers = <String, TextEditingController>{};

  @override
  void dispose() {
    for (final c in _controllers.values) {
      c.dispose();
    }
    super.dispose();
  }

  TextEditingController _controllerFor(String key, String value) =>
      _controllers.putIfAbsent(key, () => TextEditingController(text: value));

  List<KeyPersonOwnerEntry> get owners => widget.owners;
  String get companyName => widget.companyName;

  void _onChanged(List<KeyPersonOwnerEntry> next) {
    // Removing a row shifts every later one down, so the keyed controllers no
    // longer line up with their values. Dropping them lets the next build
    // rebuild each from the row it is now showing.
    if (next.length != owners.length) {
      for (final c in _controllers.values) {
        c.dispose();
      }
      _controllers.clear();
    }
    widget.onChanged(next);
  }

  void _patch(int index, KeyPersonOwnerEntry next) => _onChanged([
        for (var i = 0; i < owners.length; i++) i == index ? next : owners[i],
      ]);

  @override
  Widget build(BuildContext context) {
    final colors = context.myazaColors;
    final text = context.myazaText;
    final name = companyName.trim().isEmpty ? 'this company' : companyName.trim();

    return Container(
      padding: const EdgeInsets.all(MyazaSpacing.md),
      decoration: BoxDecoration(
        borderRadius: BorderRadius.circular(MyazaRadius.lg),
        border: Border.all(color: colors.border),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Text('Who owns $name? (optional)', style: text.label),
          const SizedBox(height: 2),
          Text(
            'A company cannot verify an identity, so tell us the people behind '
            'it if you know them.',
            style: text.bodySmall.copyWith(color: colors.textSecondary),
          ),
          for (var i = 0; i < owners.length; i++) ...[
            const SizedBox(height: MyazaSpacing.sm),
            MyazaInput(
              key: ValueKey('owner-name-$i'),
              hint: 'Full name',
              controller: _controllerFor('name-$i', owners[i].name),
              textCapitalization: TextCapitalization.words,
              onChanged: (v) => _patch(i, owners[i].copyWith(name: v)),
            ),
            const SizedBox(height: MyazaSpacing.xs),
            MyazaInput(
              key: ValueKey('owner-pct-$i'),
              hint: 'Their share, e.g. 75',
              controller: _controllerFor('pct-$i', owners[i].ownershipPct),
              keyboardType: const TextInputType.numberWithOptions(decimal: true),
              inputFormatters: [
                FilteringTextInputFormatter.allow(RegExp(r'[0-9.]')),
              ],
              suffix: Text(
                '%',
                style: text.bodySmall.copyWith(color: colors.textSecondary),
              ),
              onChanged: (v) => _patch(i, owners[i].copyWith(ownershipPct: v)),
            ),
            Align(
              alignment: Alignment.centerLeft,
              child: TextButton(
                onPressed: () => _onChanged([
                  for (var j = 0; j < owners.length; j++)
                    if (j != i) owners[j],
                ]),
                child: Text(
                  'Remove',
                  style: text.bodySmall.copyWith(color: MyazaColors.error),
                ),
              ),
            ),
          ],
          if (owners.length < _maxOwners) ...[
            const SizedBox(height: MyazaSpacing.sm),
            OutlinedButton(
              onPressed: () =>
                  _onChanged([...owners, const KeyPersonOwnerEntry()]),
              child: Text(
                owners.isEmpty ? 'Add an owner' : 'Add another',
                style: text.bodySmall.copyWith(fontWeight: FontWeight.w600),
              ),
            ),
          ],
        ],
      ),
    );
  }
}
