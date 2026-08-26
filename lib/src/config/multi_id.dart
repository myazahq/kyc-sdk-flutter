/// Multi-ID flows: a workflow's `multiId` block asks for SEVERAL ID checks in
/// one run — the applicant picks each check's ID from what the admin allowed
/// for THEIR country (a picked ID disappears from later checks), ONE selfie
/// covers the whole run, and everything submits as ONE verification the server
/// judges by the pass policy.
///
/// A PORT of the web SDK's `lib/multi-id.ts`, kept identical in its logic: the
/// server validates the pick sequence the client produced, so a client that
/// computes options differently produces submissions the server rejects. If a
/// rule changes here it changes in kyc-sdk-react, kyc-sdk-react-native,
/// kyc-core/src/lib/multi-id.ts and the dashboard's required-ids-model.ts in
/// the same commit.
library;

import '../services/nfc_reader.dart';

/// The workflow's multi-ID POLICY.
class MultiIdConfig {
  /// How many IDs the applicant completes (2–3).
  final int count;

  /// How many must pass for the verification to be VERIFIED.
  final int minPassed;

  const MultiIdConfig({required this.count, required this.minPassed});

  /// Reads the policy off a config map, or null for an ordinary run.
  ///
  /// REJECTS an out-of-range count rather than clamping it, because that is
  /// what the server does: clamping would walk 3 checks for a config the
  /// server does not consider multi-ID at all.
  static MultiIdConfig? fromJson(Map<String, dynamic>? json) {
    if (json == null) return null;
    final rawCount = json['count'];
    if (rawCount is! num) return null;
    final count = rawCount.truncate();
    if (count < 2 || count > 3) return null;
    final rawMin = json['minPassed'];
    final minPassed = rawMin is num
        ? rawMin.truncate().clamp(1, count)
        : count;
    return MultiIdConfig(count: count, minPassed: minPassed);
  }
}

/// One committed check: the ID, its number, and its uploaded documents.
///
/// [documentFrontPath] / [documentBackPath] are LOCAL device paths kept for the
/// back journey, so stepping back into a check restores what it captured rather
/// than asking for a document that is still perfectly good. They never reach
/// the wire — see [toWire].
class MultiIdSlot {
  final String idType;
  final String? idNumber;
  final String? documentFront;
  final String? documentBack;

  /// Each check records its OWN document capture. The row's flat
  /// documentFrontVideo column holds one, so a multi-ID run keeps them per
  /// check or loses all but one.
  final String? documentFrontVideo;
  final String? documentBackVideo;

  /// This check's own chip read. The chip belongs to a PARTICULAR document, so
  /// sending it top-level attributed it to the primary check — which is how a
  /// passport's chip read was dropped for being submitted alongside a BVN.
  /// Serialised by the caller (it is a payload, not a media id).
  final NfcChipData? chipData;

  final String? documentFrontPath;
  final String? documentBackPath;

  const MultiIdSlot({
    required this.idType,
    this.idNumber,
    this.documentFront,
    this.documentBack,
    this.documentFrontVideo,
    this.documentBackVideo,
    this.chipData,
    this.documentFrontPath,
    this.documentBackPath,
  });

  /// The check as the WIRE sees it — an explicit whitelist, not a spread, so a
  /// field added to the slot later cannot leak into a submission by default.
  Map<String, dynamic> toWire() => {
        'idType': idType,
        if (idNumber != null && idNumber!.isNotEmpty) 'idNumber': idNumber,
        if (documentFront != null) 'documentFront': documentFront,
        if (documentBack != null) 'documentBack': documentBack,
        if (documentFrontVideo != null) 'documentFrontVideo': documentFrontVideo,
        if (documentBackVideo != null) 'documentBackVideo': documentBackVideo,
      };
}

/// Per-check option lists (a pinned check keeps its list; others offer all).
List<List<String>> multiIdSlotOptions(
  int count,
  List<List<String>?>? slots,
  List<String> offered,
) {
  final offeredSet = offered.toSet();
  return List<List<String>>.generate(count, (i) {
    final pinned = (slots != null && i < slots.length) ? slots[i] : null;
    final base = (pinned != null && pinned.isNotEmpty) ? pinned : offered;
    return base.where(offeredSet.contains).toList(growable: false);
  });
}

/// The first reachable dead end across pick orders, or null.
///
/// A picked ID disappears from later checks, so an allowlist CAN strand an
/// applicant partway through. This is what the safe-options rule is built on.
bool _hasDeadEnd(List<List<String>> slotOptions, int index, List<String> picked) {
  if (index >= slotOptions.length) return false;
  final available =
      slotOptions[index].where((t) => !picked.contains(t)).toList(growable: false);
  if (available.isEmpty) return true;
  for (final pick in available) {
    if (_hasDeadEnd(slotOptions, index + 1, [...picked, pick])) return true;
  }
  return false;
}

/// The picks a check may SAFELY offer: unused AND non-stranding.
List<String> multiIdSafeOptions(
  List<List<String>> slotOptions,
  int slotIndex,
  List<String> picked,
) {
  if (slotIndex >= slotOptions.length) return const [];
  final remaining = slotOptions.sublist(slotIndex + 1);
  return slotOptions[slotIndex].where((t) => !picked.contains(t)).where((t) {
    final narrowed = remaining
        .map((opts) =>
            opts.where((o) => o != t && !picked.contains(o)).toList(growable: false))
        .toList(growable: false);
    return !_hasDeadEnd(narrowed, 0, const []);
  }).toList(growable: false);
}

/// The active plan for the check the applicant is on.
class MultiIdPlan {
  final int count;
  final int minPassed;

  /// Which check is being walked (0-based; equals [count] once all committed).
  final int index;

  /// The current check is the final one.
  final bool last;

  /// ID types committed so far, in order.
  final List<String> picked;

  /// What the CURRENT check's picker may offer.
  final List<String> safeOptions;

  const MultiIdPlan({
    required this.count,
    required this.minPassed,
    required this.index,
    required this.last,
    required this.picked,
    required this.safeOptions,
  });
}
