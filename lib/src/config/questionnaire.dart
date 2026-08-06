// ─── Questionnaire config ─────────────────────────────────────────────────────
//
// An org-authored set of extra-info / compliance questions the SDK asks after
// capture, right before submission. The DEFINITION is template data (rides a
// workflow); the ANSWERS are per-user runtime data submitted with /verify.
// Mirrors the web SDK's QuestionnaireConfig. Answer keys are a stable contract
// once published (decisioning + webhook consumers reference them).

enum QuestionnaireFieldType {
  text,
  number,
  money,
  select,
  multiselect,
  boolean,
  date;

  static QuestionnaireFieldType fromString(String? raw) => switch (raw) {
        'number' => QuestionnaireFieldType.number,
        'money' => QuestionnaireFieldType.money,
        'select' => QuestionnaireFieldType.select,
        'multiselect' => QuestionnaireFieldType.multiselect,
        'boolean' => QuestionnaireFieldType.boolean,
        'date' => QuestionnaireFieldType.date,
        _ => QuestionnaireFieldType.text,
      };
}

/// One selectable option for select/multiselect fields.
class QuestionnaireOption {
  final String value;
  final String label;
  const QuestionnaireOption({required this.value, required this.label});

  factory QuestionnaireOption.fromJson(Map<String, dynamic> json) {
    final value = (json['value'] ?? '').toString();
    return QuestionnaireOption(
      value: value,
      label: (json['label'] as String?) ?? value,
    );
  }
}

class QuestionnaireField {
  /// Stable snake_case key — the webhook/answers field name. A stable contract.
  final String key;
  final String label;
  final QuestionnaireFieldType type;
  final bool required;
  final String? placeholder;
  final String? helpText;
  final List<QuestionnaireOption> options;
  final num? min;
  final num? max;

  /// For money fields: ISO currency codes (first = default). Publish requires ≥1.
  final List<String> currencies;

  const QuestionnaireField({
    required this.key,
    required this.label,
    required this.type,
    this.required = false,
    this.placeholder,
    this.helpText,
    this.options = const [],
    this.min,
    this.max,
    this.currencies = const [],
  });

  factory QuestionnaireField.fromJson(Map<String, dynamic> json) =>
      QuestionnaireField(
        key: (json['key'] ?? '').toString(),
        label: (json['label'] as String?) ?? (json['key'] ?? '').toString(),
        type: QuestionnaireFieldType.fromString(json['type'] as String?),
        required: json['required'] as bool? ?? false,
        placeholder: json['placeholder'] as String?,
        helpText: json['helpText'] as String?,
        options: ((json['options'] as List?) ?? const [])
            .whereType<Map>()
            .map((e) => QuestionnaireOption.fromJson(e.cast<String, dynamic>()))
            .toList(growable: false),
        min: json['min'] as num?,
        max: json['max'] as num?,
        currencies: ((json['currencies'] as List?) ?? const [])
            .map((e) => e.toString())
            .toList(growable: false),
      );
}

class QuestionnaireConfig {
  final bool enabled;
  final String? title;
  final String? description;
  final List<QuestionnaireField> fields;

  const QuestionnaireConfig({
    this.enabled = true,
    this.title,
    this.description,
    this.fields = const [],
  });

  /// Whether the questionnaire step should actually show — enabled AND has at
  /// least one field (matches the web SDK's `hasActiveQuestionnaire`).
  bool get isActive => enabled && fields.isNotEmpty;

  factory QuestionnaireConfig.fromJson(Map<String, dynamic> json) =>
      QuestionnaireConfig(
        enabled: json['enabled'] as bool? ?? true,
        title: json['title'] as String?,
        description: json['description'] as String?,
        fields: ((json['fields'] as List?) ?? const [])
            .whereType<Map>()
            .map((e) => QuestionnaireField.fromJson(e.cast<String, dynamic>()))
            .toList(growable: false),
      );
}
