import 'package:flutter/material.dart';
import '../config/theme.dart';

// One person on the KYB success screen's list: who they are, where their check
// stands, and — while it is still open — the link that gets them there.
//
// The link lives ON the row rather than in a second list above it. Two lists of
// the same people, one with links and one with statuses, is what Flutter had,
// and a reader has to hold both to answer "who still owes me something".
// Mirrors the RN SDK's KeyPeopleAwaitCard.

/// One row, from the SERVER's reconciled list.
class AwaitRow {
  final String name;

  /// The SERVER's role key (snake_case). Kept raw so the sections can group by
  /// it and a role nobody has a heading for genuinely falls outside them,
  /// rather than being folded into whichever enum value it was coerced to.
  final String role;
  final String? pct;
  final String? country;

  /// `verified` | `submitted` | `failed` | `not_needed` | `pending`.
  final String status;
  final String? inviteUrl;
  final bool isApplicant;

  /// A company on the list completes a KYB application, not a KYC. It gets a
  /// Company tag and its pending pill reads "KYB PENDING".
  final bool isCorporate;

  const AwaitRow({
    required this.name,
    required this.role,
    this.pct,
    this.country,
    required this.status,
    this.inviteUrl,
    this.isApplicant = false,
    this.isCorporate = false,
  });
}

/// The role as a person reads it. An unrecognised one still says something
/// rather than rendering a raw key.
String roleLabel(String role) => switch (role) {
      'beneficial_owner' => 'Beneficial owner (UBO)',
      'director' => 'Director',
      'signatory' => 'Signatory',
      'shareholder' => 'Shareholder',
      'authorized_representative' => 'Authorised representative',
      _ => 'Key person',
    };

String pillLabel(String status, bool isCorporate) => switch (status) {
      'verified' => 'VERIFIED',
      'submitted' => 'SUBMITTED',
      'failed' => 'CHECK FAILED',
      'not_needed' => 'NOT NEEDED',
      _ => isCorporate ? 'KYB PENDING' : 'KYC PENDING',
    };

Color pillBg(String status, MyazaColorScheme colors) => switch (status) {
      'verified' || 'submitted' => colors.successBg,
      'failed' => colors.errorBg,
      'not_needed' => colors.border,
      _ => colors.primary100,
    };

Color pillFg(String status, MyazaColorScheme colors) => switch (status) {
      'verified' || 'submitted' => MyazaColors.success,
      'failed' => MyazaColors.error,
      'not_needed' => colors.textMuted,
      _ => colors.primary,
    };

