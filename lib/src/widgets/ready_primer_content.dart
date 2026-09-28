import 'package:flutter/widgets.dart';
import 'icons/icons.dart';

// ─── "Here's what happens next" copy ─────────────────────────────────────────
//
// A port of the web SDK's ready-primer-content.ts. Kept as data in ONE place
// per platform so the document and liveness screens can't drift from each
// other, and so the two SDKs can be diffed string-for-string.
//
// The words are catalogue texts (a workflow may reword them); this file holds
// their KEYS, and each key's default lives in i18n/defaults_welcome.dart.

@immutable
class ReadyChecklistItem {
  const ReadyChecklistItem(this.icon, this.labelKey);
  final MyazaIconData icon;

  /// Text key of the line (see i18n/).
  final String labelKey;
}

@immutable
class ReadyContent {
  const ReadyContent({
    required this.icon,
    required this.titleKey,
    required this.bodyKey,
    required this.checklist,
  });

  final MyazaIconData icon;
  /// Text keys of the heading and the paragraph (see i18n/).
  final String titleKey;
  final String bodyKey;

  /// What to expect. Three at most; past that nobody reads it.
  final List<ReadyChecklistItem> checklist;
}

const readyDocument = ReadyContent(
  icon: MyazaIcons.scanLine,
  titleKey: 'primer.document.title',
  bodyKey: 'primer.document.body',
  checklist: [
    ReadyChecklistItem(MyazaIcons.idCard, 'primer.document.checklist1'),
    ReadyChecklistItem(MyazaIcons.sun, 'primer.document.checklist2'),
    ReadyChecklistItem(MyazaIcons.timer, 'primer.document.checklist3'),
  ],
);

const readyLiveness = ReadyContent(
  icon: MyazaIcons.scanFace,
  titleKey: 'primer.selfie.title',
  bodyKey: 'primer.selfie.body',
  checklist: [
    ReadyChecklistItem(MyazaIcons.userRound, 'primer.selfie.checklist1'),
    ReadyChecklistItem(MyazaIcons.glasses, 'primer.selfie.checklist2'),
    ReadyChecklistItem(MyazaIcons.sun, 'primer.selfie.checklist4'),
    ReadyChecklistItem(MyazaIcons.sparkles, 'primer.selfie.checklist5'),
  ],
);

/// Passive Liveness asks for no prompts, so its description says so.
const readyLivenessPassive = ReadyContent(
  icon: MyazaIcons.scanFace,
  titleKey: 'primer.selfie.title',
  bodyKey: 'primer.selfie.bodyPassive',
  checklist: [
    ReadyChecklistItem(MyazaIcons.userRound, 'primer.selfie.checklist1'),
    ReadyChecklistItem(MyazaIcons.glasses, 'primer.selfie.checklist2'),
    ReadyChecklistItem(MyazaIcons.sun, 'primer.selfie.checklist4'),
    ReadyChecklistItem(MyazaIcons.sparkles, 'primer.selfie.checklist5'),
  ],
);

/// The primer for the workflow's liveness method.
ReadyContent readyLivenessFor(String livenessMode) =>
    livenessMode == 'passive' ? readyLivenessPassive : readyLiveness;
