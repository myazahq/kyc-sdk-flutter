import 'package:flutter/widgets.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../config/kyc_config.dart';
import '../providers/kyc_provider.dart';
import 'translate.dart';

/// The [TextFn] for a config: its custom copy in its language, else English,
/// else this SDK's default. `{firstName}`, `{lastName}` and `{businessName}`
/// are always filled from `userData`, so any text may use them.
TextFn textFnFor(MyazaKYCConfig config) => createTextFn(
      config.texts,
      config.language,
      {
        'firstName': config.userData?.firstName,
        'lastName': config.userData?.lastName,
        'businessName': config.userData?.businessName,
      },
    );

/// The flow's [TextFn], derived from the mounted config. Declares its
/// dependency so it is re-created inside each flow's scope, where the config
/// is overridden, rather than read from the root (which has no config).
final kycTextProvider = Provider<TextFn>(
  (ref) => textFnFor(ref.watch(kycConfigProvider)),
  dependencies: [kycConfigProvider],
);

/// The flow's scope as seen from [context], or null outside a flow. A route
/// opened from inside the flow (a sheet, the cropper) is a SIBLING of the
/// flow's route, so it is handed this to keep reading the flow's texts.
ProviderContainer? flowScopeOf(BuildContext context) {
  try {
    return ProviderScope.containerOf(context, listen: false);
  } catch (_) {
    return null;
  }
}

/// [child] under [scope] when there is one.
Widget inFlowScope(ProviderContainer? scope, Widget child) => scope == null
    ? child
    : UncontrolledProviderScope(container: scope, child: child);

extension KycTextContext on BuildContext {
  /// The flow's [TextFn]. Outside a flow's ProviderScope (a widget pumped on
  /// its own) it answers with the defaults, the way the web SDK's `useText`
  /// does outside its provider, so a shared widget never needs one.
  TextFn get kycText {
    try {
      return textFnFor(ProviderScope.containerOf(this, listen: false)
          .read(kycConfigProvider));
    } catch (_) {
      return defaultText;
    }
  }
}
