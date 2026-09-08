import 'package:flutter/material.dart';
import 'package:lucide_icons_flutter/lucide_icons.dart';

import '../../config/theme.dart';
import '../../widgets/myaza_input.dart';

/// The minimum a query must reach before either backend is asked. Below it the
/// answer is noise and the request is wasted.
const int kAddressSearchMinQuery = 3;

/// The AUTOCOMPLETE backend's field: typing IS the request, so it carries a
/// leading search icon and a trailing spinner while a details call resolves.
class AddressAutocompleteField extends StatelessWidget {
  final TextEditingController controller;
  final bool busy;
  final ValueChanged<String> onChanged;

  const AddressAutocompleteField({
    super.key,
    required this.controller,
    required this.busy,
    required this.onChanged,
  });

  @override
  Widget build(BuildContext context) {
    final colors = context.myazaColors;
    return Semantics(
      textField: true,
      label: 'Search your address',
      child: MyazaInput(
      controller: controller,
      hint: 'Search your address, e.g. 12 Adeola Odeku Street',
      autofocus: true,
      autocorrect: false,
      textInputAction: TextInputAction.search,
      onChanged: onChanged,
      prefix: Icon(LucideIcons.search, size: 16, color: colors.textSecondary),
      suffix: busy
          ? SizedBox(
              width: 16,
              height: 16,
              child: CircularProgressIndicator(
                  strokeWidth: 2, color: colors.textSecondary),
            )
          : null,
      ),
    );
  }
}

/// The BASIC backend's field: explicit submit only, so a search button sits
/// beside the input and is disabled below the minimum query length.
///
/// A separate widget from the autocomplete field because the two are different
/// contracts, not two styles: the basic source forbids per-keystroke calls, so
/// there is deliberately no way to fire one from typing here.
class AddressBasicSearchField extends StatefulWidget {
  final TextEditingController controller;
  final bool busy;
  final VoidCallback onSubmit;

  const AddressBasicSearchField({
    super.key,
    required this.controller,
    required this.busy,
    required this.onSubmit,
  });

  @override
  State<AddressBasicSearchField> createState() =>
      _AddressBasicSearchFieldState();
}

class _AddressBasicSearchFieldState extends State<AddressBasicSearchField> {
  @override
  Widget build(BuildContext context) {
    final colors = context.myazaColors;
    final ready =
        widget.controller.text.trim().length >= kAddressSearchMinQuery;
    final enabled = ready && !widget.busy;
    return Row(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Expanded(
          child: Semantics(
            textField: true,
            label: 'Search your address',
            child: MyazaInput(
              controller: widget.controller,
              hint: 'Search your address, e.g. 12 Adeola Odeku Street',
              autocorrect: false,
              textInputAction: TextInputAction.search,
              // Rebuilt on every keystroke only so the button's enabled state
              // tracks the query; nothing is requested until submit.
              onChanged: (_) => setState(() {}),
              onSubmitted: (_) => widget.onSubmit(),
            ),
          ),
        ),
        const SizedBox(width: MyazaSpacing.sm),
        Semantics(
          button: true,
          label: 'Search',
          child: Material(
            color: Colors.transparent,
            child: InkWell(
              onTap: enabled ? widget.onSubmit : null,
              borderRadius: BorderRadius.circular(MyazaRadius.sm),
              child: Container(
                width: MyazaSizing.inputHeight,
                height: MyazaSizing.inputHeight,
                alignment: Alignment.center,
                decoration: BoxDecoration(
                  border: Border.all(color: colors.border),
                  borderRadius: BorderRadius.circular(MyazaRadius.sm),
                ),
                child: widget.busy
                    ? SizedBox(
                        width: 16,
                        height: 16,
                        child: CircularProgressIndicator(
                            strokeWidth: 2, color: colors.primary),
                      )
                    : Icon(LucideIcons.search,
                        size: 18,
                        color: enabled ? colors.primary : colors.gray400),
              ),
            ),
          ),
        ),
      ],
    );
  }
}
