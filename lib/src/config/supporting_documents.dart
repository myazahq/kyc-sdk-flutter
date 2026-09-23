// ─── Supporting documents config ─────────────────────────────────────────────
//
// Artefacts the organisation keeps ON FILE, which are NOT the identity evidence
// the verification is decided on: the person is verified against the government
// database, and a downstream process still wants a document on record.
//
// MIRROR of the server's `requestedSupportingDocuments`
// (kyc-core src/lib/workflows/supporting-documents-config.ts), the web SDK's
// lib/supporting-documents.ts and the React Native SDK's
// config/supportingDocuments.ts. Four copies of one rule, because the mobile
// SDKs cannot import the web package — change it in one and change it in all,
// in the same commit. The server VALIDATES what the client produced, so a
// client that resolved differently just builds submissions the server refuses.
//
// There is no catalogue to mirror: a document is whatever the ORG named it, so
// the SDK renders the title and guidance the workflow sent rather than
// captioning a key it recognises.

/// One requested supporting document, as the workflow configures it.
class SupportingDocumentRequest {
  const SupportingDocumentRequest({
    required this.key,
    required this.label,
    this.description,
    this.required = false,
    this.idTypes = const [],
    this.alwaysAsk = false,
    this.reads = const [],
  });

  /// The organisation's own slug — the wire `type` this upload submits as.
  final String key;

  /// The title the applicant reads.
  final String label;

  /// Guidance under the slot: which document, and what it has to show.
  final String? description;
  final bool required;

  /// Which verified IDs it is asked for, as `"CC/idType"`. Empty = every ID.
  final List<String> idTypes;

  /// Offer it on every flow, whatever ID was verified, so [idTypes] decides
  /// only who MUST provide it rather than who sees the slot. Off = the scope
  /// hides it from everybody else, which is the default.
  final bool alwaysAsk;

  /// The named values the server will read off it, in the author's own words.
  /// Shown to the applicant so an upload says what it is being taken FOR.
  ///
  /// DISPLAY ONLY, and deliberately not a mirror of the server's field
  /// resolution: it drops blanks and repeats and stops there. The server
  /// decides what is actually read, and an extra name on a chip costs an
  /// applicant nothing.
  final List<String> reads;

  /// Null for an entry with no key or no title: a slot the applicant cannot
  /// read reaches nobody, and publish refuses one, so this only ever bites a
  /// draft mid-edit.
  static SupportingDocumentRequest? fromJson(Map<String, dynamic> json) {
    final key = (json['key'] as String?)?.trim();
    final label = (json['label'] as String?)?.trim();
    if (key == null || key.isEmpty || label == null || label.isEmpty) {
      return null;
    }
    final ids = json['idTypes'];
    final description = (json['description'] as String?)?.trim();
    return SupportingDocumentRequest(
      key: key,
      label: label,
      description: (description?.isEmpty ?? true) ? null : description,
      required: json['required'] == true,
      idTypes: ids is List ? ids.whereType<String>().toList() : const [],
      alwaysAsk: json['alwaysAsk'] == true,
      reads: _reads(json['fields']),
    );
  }

  /// The names on a document's fields: what the applicant is told we read.
  static List<String> _reads(Object? fields) {
    if (fields is! List) return const [];
    final seen = <String>{};
    final out = <String>[];
    for (final field in fields.whereType<Map>()) {
      final label = (field['label'] as String?)?.trim();
      if (label == null || label.isEmpty || !seen.add(label.toLowerCase())) {
        continue;
      }
      out.add(label);
    }
    return out;
  }
}

class SupportingDocumentsConfig {
  const SupportingDocumentsConfig({this.enabled = false, this.types = const []});

  final bool enabled;
  final List<SupportingDocumentRequest> types;

  static SupportingDocumentsConfig? fromJson(Map<String, dynamic>? json) {
    if (json == null) return null;
    final raw = json['types'];
    return SupportingDocumentsConfig(
      enabled: json['enabled'] == true,
      types: raw is List
          ? raw
              .whereType<Map>()
              .map((e) => SupportingDocumentRequest.fromJson(Map<String, dynamic>.from(e)))
              .whereType<SupportingDocumentRequest>()
              .toList()
          : const [],
    );
  }
}

/// A document resolved for THIS attempt, ready to render as a slot.
class ResolvedSupportingDocument {
  const ResolvedSupportingDocument({
    required this.key,
    required this.label,
    required this.description,
    required this.required,
    this.reads = const [],
  });

  final String key;
  final String label;

  /// Guidance under the slot, when the author wrote some.
  final String? description;
  final bool required;

  /// The named values the server will read off it. See the request's own note.
  final List<String> reads;
}

/// `"${country}/${idType}"` — the composite `idTypes` entries are written in.
String idComposite(String country, String idType) =>
    '${country.trim().toUpperCase()}/${idType.trim()}';

/// The documents to ask for, given the IDs this attempt has committed.
///
/// An empty result means the step does not appear at all — which is the point
/// of the per-document scoping: a document may exist only because the person
/// used a particular ID, so a flow that asks for one must not put the step in
/// front of somebody who used another.
List<ResolvedSupportingDocument> resolveSupportingDocuments(
  SupportingDocumentsConfig? config,
  List<String> verifiedIds,
) {
  if (config == null || !config.enabled) return const [];
  final wanted = verifiedIds.map((id) => id.toUpperCase()).toSet();
  final seen = <String>{};
  final out = <ResolvedSupportingDocument>[];
  for (final entry in config.types) {
    final scoped = entry.idTypes.isNotEmpty;
    final inScope =
        !scoped || entry.idTypes.any((id) => wanted.contains(id.trim().toUpperCase()));
    // `alwaysAsk` keeps the slot on screen for everybody, so the scope decides
    // only who must fill it: an out-of-scope applicant may hand the document
    // over and is never blocked for not having one.
    if (!inScope && !entry.alwaysAsk) continue;
    if (!seen.add(entry.key)) continue;
    out.add(ResolvedSupportingDocument(
      key: entry.key,
      label: entry.label,
      description: entry.description,
      required: entry.required && inScope,
      reads: entry.reads,
    ));
  }
  return out;
}

/// The composites this attempt has committed — one per ID, multi-ID included.
List<String> verifiedIdsFor({
  String? country,
  String? idType,
  List<String> multiIdTypes = const [],
}) {
  if (country == null || country.isEmpty) return const [];
  final ids = multiIdTypes.isNotEmpty
      ? multiIdTypes
      : (idType != null && idType.isNotEmpty ? [idType] : const <String>[]);
  return ids.map((id) => idComposite(country, id)).toSet().toList();
}

/// Whether the step has anything to ask for on this attempt.
bool hasSupportingDocumentsStep(
  SupportingDocumentsConfig? config,
  List<String> verifiedIds,
) =>
    resolveSupportingDocuments(config, verifiedIds).isNotEmpty;

/// One uploaded supporting document held in flow state.
///
/// Shaped like `BusinessDocumentUpload` on purpose — the wire body the server
/// takes is the same `{ type, mediaId }` pair, and the slot widget the two
/// share needs the same preview fields. Kept as its own type rather than
/// reusing that one so a business record never ends up in this list.
class SupportingDocumentUpload {
  const SupportingDocumentUpload({
    required this.type,
    required this.mediaId,
    required this.fileName,
    this.previewPath,
    this.isPdf = false,
  });

  /// The document's key, chosen by the org — what the server matches this
  /// upload back to its own request on.
  final String type;
  final String mediaId;
  final String fileName;

  /// Local temp path of the picked file, for the slot thumbnail. Kept on the
  /// RECORD so the preview survives leaving and re-entering the step. Never
  /// serialised.
  final String? previewPath;
  final bool isPdf;

  Map<String, dynamic> toJson() => {'type': type, 'mediaId': mediaId};

  /// Restores a saved session's upload. The preview is deliberately dropped —
  /// progress carries ids, not bytes — so a resumed slot shows as uploaded
  /// without a thumbnail.
  static SupportingDocumentUpload? fromJson(Map<String, dynamic> json) {
    final type = json['type'];
    final mediaId = json['mediaId'];
    if (type is! String || mediaId is! String || type.isEmpty || mediaId.isEmpty) {
      return null;
    }
    return SupportingDocumentUpload(
      type: type,
      mediaId: mediaId,
      fileName: json['fileName'] as String? ?? type,
    );
  }
}

/// The line under "Supporting documents", from what the flow is actually
/// asking for.
///
/// It used to be one sentence about keeping documents on file plus a note that
/// required ones are marked with an asterisk, which tells somebody how to read
/// the screen rather than what is being asked of them, and the asterisk carries
/// no information at all when every document is required. The counts are what a
/// person wants: how many they have to produce before they can go on.
///
/// MIRRORS the web SDK's supportingDocumentsIntro. Keep the wording in step.
String supportingDocumentsIntro(List<ResolvedSupportingDocument> slots) {
  final total = slots.length;
  final required = slots.where((s) => s.required).length;

  // Nothing is compulsory, so the honest line is that the step can be skipped.
  if (required == 0) {
    return total == 1
        ? 'Upload this document if you have it, so we can keep it on file. You can skip it.'
        : 'Upload any of these you have, so we can keep them on file. You can skip the rest.';
  }

  if (required == total) {
    return total == 1
        ? 'We need this document to continue. Upload it below.'
        : 'We need all $total of these documents to continue. Upload one for each item below.';
  }

  // Mixed, and the only case where the asterisk earns its place on the screen.
  // The noun agrees with the TOTAL, which is always two or more here.
  return 'We need $required of these $total documents to continue, marked with *. '
      'Upload the others if you have them.';
}
