// ─── The org's copy tokens ──────────────────────────────────────────────────
//
// `{firstName}` / `{lastName}` in a piece of builder-authored copy are filled
// from the consumer's userData, exactly as the consent and success screens
// have always done. A missing value fills as '' and the result is trimmed, so
// a template that was ONLY a token comes back empty and the caller can fall
// back to its default rather than render a blank line. Mirrors the web and RN
// SDKs' fillTokens.

String fillCopyTokens(String template, {String? firstName, String? lastName}) =>
    template
        .replaceAll('{firstName}', firstName ?? '')
        .replaceAll('{lastName}', lastName ?? '')
        .trim();
