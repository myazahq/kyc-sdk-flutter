// Workflow SCOPE — what a flow verifies about the subject (mirror of the
// server's lib/workflows/scope.ts and the web/RN SDKs' lib/scope.ts; keep the
// four in lockstep). Absent/null = the full verification.

const Set<String> kWorkflowScopes = {
  'address',
  'biometric-authentication',
  'biometric-enrollment',
  'questionnaire',
  'contact',
};

/// The marker idType a scoped submission carries (the KYB product-in-idType
/// convention; the server requires the matching published workflow).
const Map<String, String> kScopeIdTypes = {
  'address': 'address',
  'biometric-authentication': 'biometric-auth',
  'biometric-enrollment': 'biometric-enroll',
  'questionnaire': 'questionnaire',
  'contact': 'contact',
};

String? configScope(String? scope) =>
    scope != null && kWorkflowScopes.contains(scope) ? scope : null;

/// The biometric scopes run the liveness capture; every other scope has no
/// camera step at all.
bool isFaceScope(String? scope) =>
    scope == 'biometric-authentication' || scope == 'biometric-enrollment';
