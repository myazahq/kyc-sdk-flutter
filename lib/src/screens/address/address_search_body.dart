import 'dart:async';

import 'package:flutter/material.dart';
import 'package:uuid/uuid.dart';

import '../../config/theme.dart';
import '../../services/api_service.dart';
import '../../utils/map_tiles.dart' show MapLatLng;
import 'address_search_field.dart';
import 'address_search_results.dart';

// ─── Finding the address, as words ───────────────────────────────────────────
//
// Two backends behind one screen, chosen by what the platform serves, never by
// trying one and falling back. Places AUTOCOMPLETE is as-you-type, debounced,
// on ONE session token per typing session (Google's billing unit), re-minted
// after each details call. The BASIC search is explicit-submit only: that
// source forbids autocomplete, and the budget goes on the query the applicant
// meant. Every failure degrades to the empty state; the map is always there.

const _kAutocompleteDebounce = Duration(milliseconds: 300);
const _uuid = Uuid();

class AddressSearchBody extends StatefulWidget {
  final KYCApiService api;

  /// True when the platform serves Places suggestions.
  final bool autocomplete;
  final String? country;

  /// The device fix: a ranking bias so nearby streets come first.
  final MapLatLng? near;
  final ValueChanged<ResolvedPlace> onResolved;

  const AddressSearchBody({
    super.key,
    required this.api,
    required this.autocomplete,
    required this.country,
    required this.onResolved,
    this.near,
  });

  @override
  State<AddressSearchBody> createState() => _AddressSearchBodyState();
}

class _AddressSearchBodyState extends State<AddressSearchBody> {
  final TextEditingController _query = TextEditingController();
  Timer? _debounce;
  String _session = _uuid.v4();

  bool _busy = false;
  List<PlaceSuggestion>? _suggestions;
  List<AddressSearchHit>? _hits;

  @override
  void dispose() {
    _debounce?.cancel();
    _query.dispose();
    super.dispose();
  }

  // ── Autocomplete ───────────────────────────────────────────────────────────

  void _onTyped(String value) {
    if (!widget.autocomplete) return;
    _debounce?.cancel();
    final q = value.trim();
    if (q.length < kAddressSearchMinQuery) {
      setState(() => _suggestions = null);
      return;
    }
    _debounce = Timer(_kAutocompleteDebounce, () => _suggest(q));
  }

  Future<void> _suggest(String q) async {
    List<PlaceSuggestion> result;
    try {
      result = await widget.api.addressAutocomplete(
        q,
        session: _session,
        country: widget.country,
        near: widget.near,
      );
    } catch (_) {
      result = const [];
    }
    if (!mounted) return;
    setState(() => _suggestions = result);
  }

  Future<void> _pickSuggestion(PlaceSuggestion suggestion) async {
    setState(() => _busy = true);
    try {
      final place =
          await widget.api.addressPlace(suggestion.placeId, session: _session);
      // A details call CLOSES the billing session, so the next keystroke opens
      // a new one.
      _session = _uuid.v4();
      if (!mounted) return;
      setState(() => _busy = false);
      widget.onResolved(place);
    } catch (_) {
      if (!mounted) return;
      setState(() {
        _busy = false;
        _suggestions = const [];
      });
    }
  }

  // ── Basic search ───────────────────────────────────────────────────────────

  Future<void> _search() async {
    final q = _query.text.trim();
    if (q.length < kAddressSearchMinQuery || _busy) return;
    setState(() => _busy = true);
    List<AddressSearchHit> result;
    try {
      result = await widget.api.addressSearch(q, country: widget.country);
    } catch (_) {
      result = const [];
    }
    if (!mounted) return;
    setState(() {
      _busy = false;
      _hits = result;
    });
  }

  void _pickHit(AddressSearchHit hit) {
    setState(() {
      _hits = null;
      _query.clear();
    });
    // A basic hit carries only its line, so `formatted` IS that line and the
    // sheet falls back to it rather than showing an empty breakdown.
    widget.onResolved(ResolvedPlace(
      lat: hit.lat,
      lng: hit.lng,
      houseNumber: hit.houseNumber,
      road: hit.road,
      formatted: hit.label,
      country: hit.country,
    ));
  }

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        if (widget.autocomplete)
          AddressAutocompleteField(
            controller: _query,
            busy: _busy,
            onChanged: _onTyped,
          )
        else
          AddressBasicSearchField(
            controller: _query,
            busy: _busy,
            onSubmit: _search,
          ),
        if (widget.autocomplete && _suggestions != null) ...[
          const SizedBox(height: MyazaSpacing.sm),
          AddressSearchResults(
            emptyMessage:
                'No matches. Use your location or place the pin by hand.',
            rows: [
              for (var i = 0; i < _suggestions!.length; i++)
                AddressSearchResultRow(
                  title: _suggestions![i].mainText,
                  subtitle: _suggestions![i].secondaryText,
                  last: i == _suggestions!.length - 1,
                  disabled: _busy,
                  onTap: () => _pickSuggestion(_suggestions![i]),
                ),
            ],
          ),
        ],
        if (!widget.autocomplete && _hits != null) ...[
          const SizedBox(height: MyazaSpacing.sm),
          AddressSearchResults(
            emptyMessage: 'No matches. Drag the map to place the pin instead.',
            rows: [
              for (var i = 0; i < _hits!.length; i++)
                AddressSearchResultRow(
                  title: _hits![i].label,
                  last: i == _hits!.length - 1,
                  onTap: () => _pickHit(_hits![i]),
                ),
            ],
          ),
        ],
      ],
    );
  }
}
