import 'package:flutter/material.dart';

import '../config/theme.dart';
import '../services/api_service.dart';
import '../widgets/country_flag.dart';
import '../widgets/myaza_input.dart';
import '../widgets/icons/icons.dart';

// ─── The search result list ───────────────────────────────────────────────────
//
// Count first ("40 results" says whether to narrow before you start reading),
// a filter that narrows without re-searching, and one row per candidate. Split
// from business_search.dart (200-line rule). Every dimension here — 40px
// filter, 12px row padding, 6px row gaps, 256px list — is the web and RN
// SDKs', so the three render the same screen.

class BusinessSearchResults extends StatelessWidget {
  final String country;
  final List<BusinessSearchHit> hits;
  final List<BusinessSearchHit> shown;
  final bool truncated;
  final String filter;
  final ValueChanged<String> onFilter;
  final ValueChanged<BusinessSearchHit> onPicked;

  const BusinessSearchResults({
    super.key,
    required this.country,
    required this.hits,
    required this.shown,
    required this.truncated,
    required this.filter,
    required this.onFilter,
    required this.onPicked,
  });

  @override
  Widget build(BuildContext context) {
    final colors = context.myazaColors;
    final text = context.myazaText;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        const SizedBox(height: 12),
        Row(
          mainAxisAlignment: MainAxisAlignment.spaceBetween,
          children: [
            Text(
              shown.length == hits.length
                  ? '${hits.length} results'
                  : '${shown.length} of ${hits.length} results',
              style: text.bodyMedium.copyWith(color: colors.textSecondary),
            ),
            Row(
              children: [
                Text('Filter',
                    style:
                        text.bodyMedium.copyWith(color: colors.textSecondary)),
                const SizedBox(width: MyazaSpacing.sm),
                SizedBox(
                  width: 176,
                  child: MyazaInput(
                    hint: 'Name or number',
                    height: 40,
                    fontSize: 14,
                    prefix: MyazaIcon(MyazaIcons.filter,
                        size: 14, color: colors.textMuted),
                    onChanged: onFilter,
                  ),
                ),
              ],
            ),
          ],
        ),
        const SizedBox(height: 12),
        ConstrainedBox(
          constraints: const BoxConstraints(maxHeight: 256),
          child: ListView.builder(
            shrinkWrap: true,
            itemCount: shown.length,
            itemBuilder: (context, i) {
              final hit = shown[i];
              return Padding(
                padding: const EdgeInsets.only(bottom: 6),
                child: InkWell(
                  onTap: () => onPicked(hit),
                  borderRadius: BorderRadius.circular(MyazaRadius.sm),
                  child: Container(
                    padding: const EdgeInsets.all(12),
                    decoration: BoxDecoration(
                      border: Border.all(color: colors.border),
                      borderRadius: BorderRadius.circular(MyazaRadius.sm),
                    ),
                    child: Row(
                      children: [
                        MyazaIcon(MyazaIcons.building2,
                            size: 16, color: colors.textSecondary),
                        const SizedBox(width: 12),
                        Expanded(
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              Text(
                                hit.name,
                                style: text.label,
                                maxLines: 1,
                                overflow: TextOverflow.ellipsis,
                              ),
                              const SizedBox(height: 2),
                              Row(
                                children: [
                                  MyazaCountryFlag(country: country, size: 14),
                                  const SizedBox(width: 6),
                                  Text(
                                    hit.registrationNumber,
                                    style: text.bodySmall.copyWith(
                                        color: colors.textSecondary),
                                  ),
                                ],
                              ),
                            ],
                          ),
                        ),
                      ],
                    ),
                  ),
                ),
              );
            },
          ),
        ),
        if (shown.isEmpty)
          Padding(
            padding: const EdgeInsets.only(top: 12),
            child: Text(
              'Nothing here matches "${filter.trim()}". Clear the filter to '
              'see all ${hits.length}.',
              style: text.bodyMedium.copyWith(color: colors.textSecondary),
            ),
          ),
        if (truncated)
          Padding(
            padding: const EdgeInsets.only(top: 6),
            child: Text(
              'Showing the first ${hits.length}. Add more of the name to '
              'narrow it down.',
              style: text.bodySmall.copyWith(color: colors.textSecondary),
            ),
          ),
      ],
    );
  }
}
