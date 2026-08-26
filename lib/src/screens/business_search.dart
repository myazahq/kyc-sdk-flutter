import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:lucide_icons_flutter/lucide_icons.dart';

import '../config/theme.dart';
import '../providers/kyc_provider.dart';
import '../services/api_service.dart';
import '../widgets/myaza_alert.dart';
import '../widgets/myaza_button.dart';
import '../widgets/myaza_input.dart';
import '../widgets/myaza_select.dart';
import 'business_search_results.dart';

// ─── Finding the company by name, because that is what people know ───────────
//
// A registration number is on a certificate in a drawer; the name is in the
// applicant's head. Asking for the number first turns the very first field
// into a search of their own filing cabinet, which is where KYB applications
// are abandoned.
//
// The search itself is FREE and read-only; only picking a result leads to the
// paid register check. It fires on an explicit submit, never on keystroke: a
// debounce spends the register's small, uncontracted rate-limit budget on
// every prefix nobody asked for. Sizes and rhythm mirror the web and RN SDKs
// (12px block gaps, 48px input/button) — keep the three in lockstep.

class BusinessSearch extends ConsumerStatefulWidget {
  final String country;
  final ValueChanged<BusinessSearchHit> onPicked;
  final VoidCallback onManualEntry;

  const BusinessSearch({
    super.key,
    required this.country,
    required this.onPicked,
    required this.onManualEntry,
  });

  @override
  ConsumerState<BusinessSearch> createState() => _BusinessSearchState();
}

class _BusinessSearchState extends ConsumerState<BusinessSearch> {
  final _queryCtrl = TextEditingController();
  String _phase = 'idle'; // 'idle' | 'searching' | 'results' | 'unavailable'
  List<BusinessSearchHit> _hits = const [];
  bool _truncated = false;
  // Narrows what came back; it never replaces the search. Matches the name
  // AND the number — a box inviting either that answered only one looked
  // broken.
  String _filter = '';
  // Four countries file companies per state or emirate, and the provider
  // searches ONE register at a time. Without the region it fails closed —
  // a company filed a state away would otherwise come back "not registered".
  List<BusinessRegion> _regions = const [];

  @override
  void initState() {
    super.initState();
    _loadRegions();
  }

  @override
  void didUpdateWidget(BusinessSearch oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.country != widget.country) _loadRegions();
  }

  @override
  void dispose() {
    _queryCtrl.dispose();
    super.dispose();
  }

  Future<void> _loadRegions() async {
    setState(() => _regions = const []);
    if (widget.country.isEmpty) return;
    final country = widget.country;
    try {
      final res = await ref
          .read(kYCNotifierProvider.notifier)
          .api
          .businessRegions(country);
      if (mounted && widget.country == country) {
        setState(() => _regions = res.regions);
      }
    } catch (_) {
      // An empty list means "do not ask" — also the safe answer when the
      // catalogue is unreachable: the search itself says so on its own.
    }
  }

  Future<void> _run() async {
    final q = _queryCtrl.text.trim();
    final region = ref.read(kYCNotifierProvider).businessSubdivisionCode;
    if (q.length < 2) return;
    if (_regions.isNotEmpty && (region ?? '').isEmpty) return;
    setState(() => _phase = 'searching');
    try {
      final res = await ref.read(kYCNotifierProvider.notifier).api.businessSearch(
            country: widget.country,
            query: q,
            limit: 50,
            subdivisionCode: region,
          );
      if (!mounted) return;
      setState(() {
        _hits = res.results;
        _truncated = res.results.length >= 50;
        _filter = '';
        _phase = 'results';
      });
    } catch (_) {
      // Deliberately NOT an empty result list. "No matches" reads as "this
      // business is not registered", a claim an outage has not earned.
      if (mounted) setState(() => _phase = 'unavailable');
    }
  }

  @override
  Widget build(BuildContext context) {
    final colors = context.myazaColors;
    final text = context.myazaText;
    final region = ref.watch(
        kYCNotifierProvider.select((s) => s.businessSubdivisionCode));
    final searching = _phase == 'searching';
    final q = _filter.trim().toLowerCase();
    final shown = q.isEmpty
        ? _hits
        : _hits
            .where((h) =>
                h.name.toLowerCase().contains(q) ||
                h.registrationNumber.toLowerCase().contains(q))
            .toList(growable: false);

    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        if (_regions.isNotEmpty) ...[
          Text('State or region of registration', style: text.label),
          const SizedBox(height: MyazaSpacing.sm),
          MyazaSelect<String>(
            value: (region ?? '').isEmpty ? null : region,
            sheetTitle: 'State or region',
            searchable: true,
            options: [
              for (final r in _regions)
                MyazaSelectOption(value: r.code, label: r.name),
            ],
            onChanged: (code) => ref
                .read(kYCNotifierProvider.notifier)
                .setBusinessField('subdivisionCode', code),
          ),
          const SizedBox(height: 12),
        ],

        // No label: the placeholder says it, and the magnifier says what kind
        // of field this is — the web SDK's exact arrangement.
        MyazaInput(
          controller: _queryCtrl,
          hint: 'Search by company name',
          prefix: Icon(LucideIcons.search, size: 16, color: colors.textMuted),
          onChanged: (_) => setState(() {}),
          onSubmitted: (_) => _run(),
        ),
        const SizedBox(height: 12),
        // The spinner lives IN the button, as on web — a separate spinner row
        // pushed the results down and said the same thing twice.
        MyazaButton(
          label: searching ? 'Searching…' : 'Search',
          leadingIcon:
              searching ? null : const Icon(LucideIcons.search, size: 18),
          isLoading: searching,
          onPressed: searching ||
                  _queryCtrl.text.trim().length < 2 ||
                  (_regions.isNotEmpty && (region ?? '').isEmpty)
              ? null
              : () => _run(),
        ),

        if (_phase == 'results' && _hits.isNotEmpty)
          BusinessSearchResults(
            country: widget.country,
            hits: _hits,
            shown: shown,
            truncated: _truncated,
            filter: _filter,
            onFilter: (value) => setState(() => _filter = value),
            onPicked: widget.onPicked,
          ),

        if (_phase == 'results' && _hits.isEmpty)
          Padding(
            padding: const EdgeInsets.only(top: 12),
            child: Text(
              'Nothing found under that name. Try a shorter version of it, '
              'or enter the details yourself.',
              style: text.bodyMedium.copyWith(color: colors.textSecondary),
            ),
          ),

        if (_phase == 'unavailable')
          const Padding(
            padding: EdgeInsets.only(top: 12),
            child: MyazaAlert(
              variant: MyazaAlertVariant.warning,
              title: 'Search is unavailable',
              message: 'We could not reach the company register just now. '
                  'Try again, or enter the details yourself and we will check '
                  'them when you submit.',
            ),
          ),

        // Always offered, not only on failure: some companies are not in the
        // index at all, and a dead end at the first step ends the application.
        Padding(
          padding: const EdgeInsets.only(top: 12),
          child: Align(
            alignment: Alignment.centerLeft,
            child: InkWell(
              onTap: widget.onManualEntry,
              borderRadius: BorderRadius.circular(MyazaRadius.xs),
              child: Padding(
                padding: const EdgeInsets.symmetric(vertical: MyazaSpacing.xs),
                child: Row(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Icon(LucideIcons.pencil,
                        size: 14, color: colors.textSecondary),
                    const SizedBox(width: 6),
                    Text(
                      'Enter the details myself',
                      style: text.bodyMedium.copyWith(
                        fontWeight: FontWeight.w500,
                        color: colors.textSecondary,
                      ),
                    ),
                  ],
                ),
              ),
            ),
          ),
        ),
      ],
    );
  }
}
