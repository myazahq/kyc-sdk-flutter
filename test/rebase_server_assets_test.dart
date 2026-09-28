import 'package:flutter_test/flutter_test.dart';
import 'package:myaza_kyc_sdk_flutter/src/utils/resolve_url.dart';

// Regression (2026-09-28): over a dev USB tunnel (adb reverse → localhost) the
// org logo loaded but a workflow's own logo and the footer logos did not: they
// carried the server's PUBLIC_SERVER_URL host, and only `branding.logo` was
// rebased onto the address the SDK talks to.
void main() {
  const base = 'http://localhost:3001';
  const server = 'http://172.20.10.3:3001/api/kyc/branding/logo';

  test('rebases the org logo, the footer logos and the workflow logos', () {
    final out = rebaseServerAssets({
      'branding': {
        'logo': '$server/org',
        'trustAttribution': {'mode': 'custom', 'logo': '$server/light', 'logoDark': '$server/dark'},
      },
      'config': {
        'country': 'NG',
        'appearance': {'logo': '$server/wf', 'theme': 'dark', 'dark': {'logo': '$server/wf-dark'}},
      },
    }, base);
    final branding = out['branding'] as Map;
    final attribution = branding['trustAttribution'] as Map;
    final appearance = (out['config'] as Map)['appearance'] as Map;
    expect(branding['logo'], '$base/api/kyc/branding/logo/org');
    expect(attribution['logo'], '$base/api/kyc/branding/logo/light');
    expect(attribution['logoDark'], '$base/api/kyc/branding/logo/dark');
    expect(appearance['logo'], '$base/api/kyc/branding/logo/wf');
    expect((appearance['dark'] as Map)['logo'], '$base/api/kyc/branding/logo/wf-dark');
    expect(appearance['theme'], 'dark');
    expect((out['config'] as Map)['country'], 'NG');
  });

  test('leaves a literal image URL that is not the server\'s own alone', () {
    final out = rebaseServerAssets({
      'config': {
        'appearance': {'logo': 'https://cdn.example.com/logo.png'},
      },
    }, base);
    expect(((out['config'] as Map)['appearance'] as Map)['logo'], 'https://cdn.example.com/logo.png');
  });

  test('passes a response without branding or appearance through', () {
    expect(rebaseServerAssets({'idTypes': []}, base), {'idTypes': []});
  });
}
