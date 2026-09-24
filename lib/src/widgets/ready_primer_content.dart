import 'package:flutter/widgets.dart';
import 'icons/icons.dart';

// ─── "Here's what happens next" copy ─────────────────────────────────────────
//
// A port of the web SDK's ready-primer-content.ts. Kept as data in ONE place
// per platform so the document and liveness screens can't drift from each
// other, and so the two SDKs can be diffed string-for-string.
//
// Any change here must be mirrored in
// kyc-sdk-react/src/components/ready-primer-content.ts — a user who starts on
// the hosted web flow and finishes in the native app should read the same words.

@immutable
class ReadyChecklistItem {
  const ReadyChecklistItem(this.icon, this.label);
  final MyazaIconData icon;
  final String label;
}

@immutable
class ReadyContent {
  const ReadyContent({
    required this.icon,
    required this.title,
    required this.body,
    required this.checklist,
  });

  final MyazaIconData icon;
  final String title;
  final String body;

  /// What to expect. Three at most; past that nobody reads it.
  final List<ReadyChecklistItem> checklist;
}

const readyDocument = ReadyContent(
  icon: MyazaIcons.scanLine,
  title: "You're about to scan your ID",
  body: "We'll photograph your document and read it automatically. "
      'Nothing is shared until you submit.',
  checklist: [
    ReadyChecklistItem(MyazaIcons.idCard, 'Have your physical document with you'),
    ReadyChecklistItem(MyazaIcons.sun, 'Find even lighting, avoid glare'),
    ReadyChecklistItem(MyazaIcons.timer, 'Takes about a minute'),
  ],
);

const readyLiveness = ReadyContent(
  icon: MyazaIcons.scanFace,
  title: "Let's confirm you're really here",
  body: "You'll follow a few short prompts on screen. This proves a real person "
      'is present, not a photo or a recording.',
  checklist: [
    ReadyChecklistItem(MyazaIcons.userRound, 'Put your face in the circle'),
    ReadyChecklistItem(MyazaIcons.sun, 'Find even lighting, remove sunglasses'),
    ReadyChecklistItem(MyazaIcons.timer, 'Takes about 10 seconds'),
  ],
);
