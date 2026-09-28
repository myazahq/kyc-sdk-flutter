import 'customisable_texts.dart';

// ─── Custom texts ─────────────────────────────────────────────────────────────
//
// A port of the web SDK's i18n/translate.ts, with the same semantics, so a
// workflow's custom copy reads the same on every SDK. The KEY is the contract
// (test/customisable_texts_vectors.json); the wording of each default is this
// SDK's own, so a workflow that sets nothing sees exactly what it always saw.

/// The language every workflow falls back to, and the one the defaults are in.
const String kBaseTextLanguage = 'en';

/// A workflow's custom copy: language (BCP-47) to key to text.
typedef WorkflowTexts = Map<String, Map<String, String>>;

/// Values for `{name}` placeholders.
typedef TextVars = Map<String, Object?>;

/// Looks a text up by key. [legacy] is an older dedicated config field that
/// already held this text (e.g. `consent.title`): it wins over English custom
/// copy and the default, but another language's own text still wins there.
/// [fallback] is the wording for a key this SDK has no default for (a variant
/// the workflow cannot change, which still takes the legacy value).
typedef TextFn = String Function(
  String key, {
  TextVars? vars,
  String? legacy,
  String? fallback,
});

final RegExp _placeholder = RegExp(r'\{([a-zA-Z][a-zA-Z0-9]*)\}');
final RegExp _spaces = RegExp(r'[ \t]{2,}');

/// Fills `{name}` placeholders. A named value that is null becomes '' so no
/// brace leaks to the screen; a name not passed at all stays visible.
String fillPlaceholders(String template, [TextVars vars = const {}]) =>
    template.replaceAllMapped(_placeholder, (m) {
      final name = m.group(1)!;
      if (!vars.containsKey(name)) return m.group(0)!;
      final value = vars[name];
      return value == null ? '' : '$value';
    });

String? _usable(Object? value) =>
    value is String && value.trim().isNotEmpty ? value : null;

/// The text for [key]: the workflow's copy in [language] (when not English),
/// else the [legacy] field, else the workflow's English copy, else this SDK's
/// default. Workflow copy counts only for a customisable key; a blank value
/// counts as unset. Runs of spaces collapse and the ends are trimmed.
String resolveText(
  String key, {
  WorkflowTexts? texts,
  String? language,
  TextVars? vars,
  String? legacy,
  String? fallback,
}) {
  final lang = language ?? kBaseTextLanguage;
  String? pick(String l) =>
      kCustomisableTextKeys.contains(key) ? _usable(texts?[l]?[key]) : null;
  final own = lang == kBaseTextLanguage ? null : pick(lang);
  final template = own ??
      _usable(legacy) ??
      pick(kBaseTextLanguage) ??
      kDefaultTexts[key] ??
      fallback ??
      key;
  return fillPlaceholders(template, vars ?? const {})
      .replaceAll(_spaces, ' ')
      .trim();
}

/// A [TextFn] bound to one workflow's texts, language and fixed variables.
TextFn createTextFn(
  WorkflowTexts? texts,
  String? language, [
  TextVars baseVars = const {},
]) =>
    (key, {vars, legacy, fallback}) => resolveText(
          key,
          texts: texts,
          language: language,
          legacy: legacy,
          fallback: fallback,
          vars: {...baseVars, ...?vars},
        );

/// The defaults only, for code that runs with no workflow in reach. A
/// function (not a closure) so it can be a constant default argument.
String defaultTextFn(String key,
        {TextVars? vars, String? legacy, String? fallback}) =>
    resolveText(key, vars: vars, legacy: legacy, fallback: fallback);

/// [defaultTextFn], as a [TextFn] value.
const TextFn defaultText = defaultTextFn;

/// Reads a `texts` block off a config payload defensively: anything that is
/// not a map of maps of strings is dropped, never thrown on.
WorkflowTexts? parseWorkflowTexts(Object? raw) {
  if (raw is! Map) return null;
  final out = <String, Map<String, String>>{};
  raw.forEach((lang, entries) {
    if (lang is! String || entries is! Map) return;
    final inner = <String, String>{};
    entries.forEach((k, v) {
      if (k is String && v is String) inner[k] = v;
    });
    out[lang] = inner;
  });
  return out;
}
