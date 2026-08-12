import 'emrtd_card_access.dart';
import 'emrtd_pace.dart';
import 'emrtd_session.dart';

// ─── Choosing how to get into the chip ────────────────────────────────────────
//
// A chip may accept BAC, PACE, or both, and this decides which is tried first.
//
// The standard prefers PACE, and so should we eventually: BAC derives its keys
// from the MRZ alone, so anyone who photographs the passport page can decrypt a
// recorded session afterwards, while PACE agrees fresh keys every time.
//
// But this SDK's BAC has been reading real passports for a long time and its
// PACE has not read any, so the default here is deliberately the other way
// round: BAC first, PACE only when BAC is refused. In that order PACE can only
// ever ADD documents we can read — chips that have retired BAC — and can never
// take away one that already worked.
//
// PACE has since been confirmed against a real document — a Nigerian e-passport
// on 2026-08-11, over PACE-ECDH-GM with AES-256 on brainpoolP256r1, on both an
// iPhone 16 Pro Max and a Galaxy S24, with passive authentication passing and
// the DG2 portrait read. So the code is no longer unproven.
//
// The ordering STAYS BAC-first anyway, which is the part worth explaining:
// "confirmed on one document" is not "confirmed on the population". BAC has
// read every passport this SDK has ever seen; PACE has read one model of one
// issuer's. Going PACE-first would put the less-travelled path in front of
// every document in the world to buy a property (forward secrecy against a
// recorded session) that matters far less than reading the passport at all.
//
// PACE still runs — as the fallback, where it can only ever ADD documents we
// can read, namely chips that have retired BAC. Revisit when PACE has spanned
// several issuers, not before.
//
// Mirrors the React Native SDK's open.ts, including this reasoning.

/// Which access protocol is tried first.
///
/// `false` (the shipping default) means BAC first, PACE only if BAC is refused
/// — the conservative order described above. `true` reverses it, which is how
/// PACE gets exercised against a real chip: a passport that accepts BAC would
/// otherwise never reach the PACE code at all. Set it to `true` temporarily to
/// test PACE against a document; do not ship it.
///
/// Safe to flip either way — whichever protocol goes first, the other still
/// runs as the fallback, so this cannot turn a readable document into an
/// unreadable one.
bool preferPaceAccess = false;

/// Opens a session on [session], trying both access protocols as needed.
///
/// Throws [EmrtdError] with code `auth_failed` when both refuse the MRZ, which
/// is what the user is told about.
/// Why a session ended up on the protocol it did.
///
/// `chipAuthMethod` alone cannot answer the question that matters when PACE is
/// new: a chip reading over BAC may never have OFFERED PACE, or may have
/// offered it and had our implementation fail. Those call for opposite
/// responses — one is nothing to do, the other is a bug — so the reason is
/// recorded rather than inferred.
enum PaceOutcome {
  /// PACE opened the session.
  used,

  /// The chip published no EF.CardAccess: it does not speak PACE at all.
  notOffered,

  /// EF.CardAccess exists but offers only variants this build cannot run
  /// (finite-field DH, or integrated mapping).
  unsupportedVariant,

  /// PACE was attempted and did not complete. THIS is the one worth chasing.
  failed,

  /// Not tried — BAC succeeded first.
  notAttempted,
}

Future<void> establishChipSession({
  required EmrtdSession session,
  required String documentNumber,
  required String dateOfBirth,
  required String dateOfExpiry,
  bool preferPace = false,
  void Function(PaceOutcome outcome, String? detail)? onPaceOutcome,
}) async {
  Future<void> bac() async {
    await session.selectApplication();
    await session.openSession(
      documentNumber: documentNumber,
      dateOfBirth: dateOfBirth,
      dateOfExpiry: dateOfExpiry,
    );
  }

  void report(PaceOutcome outcome, [String? detail]) =>
      onPaceOutcome?.call(outcome, detail);

  Future<bool> pace() async {
    // EF.CardAccess is where a chip advertises PACE. Absent, unreadable, or
    // offering only variants this build does not implement all mean the same
    // thing for the read — use BAC — but they are recorded separately because
    // only one of them points at our own code.
    final file = await session.readCardAccess();
    if (file == null) {
      report(PaceOutcome.notOffered);
      return false;
    }
    final offers = parseCardAccess(file);
    final offer = selectPaceOffer(offers);
    if (offer == null) {
      report(PaceOutcome.unsupportedVariant, paceGapFor(offers)?.name);
      return false;
    }

    await session.openPaceSession(
      offer: offer,
      documentNumber: documentNumber,
      dateOfBirth: dateOfBirth,
      dateOfExpiry: dateOfExpiry,
    );
    report(PaceOutcome.used, offer.protocol.toString());
    return true;
  }

  if (preferPace) {
    try {
      if (await pace()) return;
    } on PaceError catch (e) {
      // Fall through: a chip that fails PACE may still answer BAC.
      report(PaceOutcome.failed, '${e.code}: ${e.message}');
    }
    await bac();
    return;
  }

  Object? bacFailure;
  try {
    await bac();
    report(PaceOutcome.notAttempted);
    return;
  } catch (e) {
    bacFailure = e;
  }

  // BAC was refused. A chip that has retired it may still open with PACE, and
  // trying costs one exchange against a document that has otherwise failed.
  try {
    if (await pace()) return;
  } on PaceError catch (e) {
    // Both refused — surface the BAC failure, whose message already says the
    // document details did not match, but keep why PACE went too.
    report(PaceOutcome.failed, '${e.code}: ${e.message}');
  }

  throw bacFailure;
}
