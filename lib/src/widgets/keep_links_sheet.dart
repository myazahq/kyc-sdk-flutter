import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:lucide_icons_flutter/lucide_icons.dart';
import 'package:url_launcher/url_launcher.dart';

import '../config/theme.dart';
import 'myaza_alert.dart';
import 'myaza_button.dart';
import 'themed_sheet.dart';

// Shown when the applicant taps Done while key people still owe a check.
//
// The invite links live on the success screen, and on mobile that screen dies
// with the app: once closed, the applicant has no way back to the links unless
// the org re-sends them. The session's own hosted web page is the way back —
// the same success screen, alive for as long as the invites are — so the one
// moment to hand it over is the moment they leave. Mirrors the RN SDK's
// KeepLinksSheet.

/// Offers the session's hosted page before the flow closes. Calls [onDone]
/// when the applicant chooses to leave; dismissing the sheet keeps them on
/// the success screen.
Future<void> showKeepLinksSheet(
  BuildContext context, {
  required String url,
  required VoidCallback onDone,
}) {
  return showMyazaSheet<void>(
    context,
    isScrollControlled: true,
    builder: (sheetContext) => _KeepLinksBody(url: url, onDone: onDone),
  );
}

class _KeepLinksBody extends StatefulWidget {
  final String url;
  final VoidCallback onDone;

  const _KeepLinksBody({required this.url, required this.onDone});

  @override
  State<_KeepLinksBody> createState() => _KeepLinksBodyState();
}

class _KeepLinksBodyState extends State<_KeepLinksBody> {
  bool _copied = false;

  @override
  Widget build(BuildContext context) {
    final colors = context.myazaColors;
    final text = context.myazaText;

    return Padding(
      padding: const EdgeInsets.fromLTRB(
          MyazaSpacing.lg, MyazaSpacing.md, MyazaSpacing.lg, MyazaSpacing.lg),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Center(
            child: Container(
              width: 52,
              height: 52,
              decoration: BoxDecoration(
                shape: BoxShape.circle,
                color: colors.primary50,
              ),
              child: Icon(LucideIcons.globe, size: 26, color: colors.primary),
            ),
          ),
          const SizedBox(height: MyazaSpacing.md),
          Text(
            'Keep a way back to these links',
            style: text.heading3,
            textAlign: TextAlign.center,
          ),
          const SizedBox(height: MyazaSpacing.md),
          const MyazaAlert(
            variant: MyazaAlertVariant.warning,
            title: 'This screen will not be shown again',
            message: "Your key people's links live on a web page made for you. "
                'Open it in your browser or copy the address somewhere safe, '
                'then check who has finished and share the links from there '
                'at any time.',
          ),
          const SizedBox(height: MyazaSpacing.lg),
          MyazaButton(
            label: 'Open in my browser',
            leadingIcon: const Icon(LucideIcons.globe, size: 18),
            onPressed: () {
              launchUrl(Uri.parse(widget.url),
                  mode: LaunchMode.externalApplication);
            },
          ),
          const SizedBox(height: MyazaSpacing.sm),
          MyazaButton.outline(
            label: _copied ? 'Link copied' : 'Copy the page link',
            leadingIcon: Icon(
              _copied ? LucideIcons.check : LucideIcons.copy,
              size: 18,
            ),
            onPressed: () async {
              await Clipboard.setData(ClipboardData(text: widget.url));
              if (mounted) setState(() => _copied = true);
            },
          ),
          const SizedBox(height: MyazaSpacing.xs),
          MyazaButton.ghost(
            label: "I'm done here",
            onPressed: () {
              Navigator.of(context).pop();
              widget.onDone();
            },
          ),
        ],
      ),
    );
  }
}
