import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../config/biometric_copy.dart';
import '../config/biometric_options.dart';
import '../config/result_copy.dart';
import '../config/scope.dart';
import '../providers/kyc_provider.dart';
import 'submitted_waiting_view.dart';

// ─── Handing over without the review ────────────────────────────────────────
//
// On the biometric scopes the selfie review (Retake / Continue) is OFF by
// default (config/biometric_options.dart): a re-authentication is a
// few-second check and a review screen is a stop in the middle of it. The
// liveness screen hands over the moment the ring has closed, WITHOUT waiting
// for the upload: the upload keeps running and reports to the provider, and
// the submitted screen waits on that record (config/selfie_upload_wait.dart).
// So the person sees one loading screen from the shutter to the verdict, not
// one per step. This view exists for the frame between "ready" and the step
// change, and it is the same screen the submitted step shows, so nothing
// visibly changes. Mirrors the RN LivenessHandover.

class LivenessHandover extends ConsumerWidget {
  const LivenessHandover({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final config = ref.watch(kycConfigProvider);
    final copy = describeWaiting(
      scope: configScope(config.scope),
      waitsForResult: config.waitsForResultOption,
      override: config.biometricCopy.waiting,
    );
    return SubmittedWaitingView(title: copy.title, description: copy.description);
  }
}
