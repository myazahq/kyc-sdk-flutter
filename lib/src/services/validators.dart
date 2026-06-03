import '../config/id_types.dart';

// ─── Result type ──────────────────────────────────────────────────────────────

class ValidationResult {
  final bool isValid;
  final String? errorMessage;

  const ValidationResult.ok() : isValid = true, errorMessage = null;
  const ValidationResult.fail(this.errorMessage) : isValid = false;
}

// ─── Nigeria ──────────────────────────────────────────────────────────────────

/// BVN — exactly 11 digits.
ValidationResult validateBvn(String value) {
  final v = value.trim();
  if (v.isEmpty) return const ValidationResult.fail('BVN is required');
  if (!RegExp(r'^\d{11}$').hasMatch(v)) {
    return const ValidationResult.fail('BVN must be exactly 11 digits');
  }
  return const ValidationResult.ok();
}

/// NIN — exactly 11 digits.
ValidationResult validateNin(String value) {
  final v = value.trim();
  if (v.isEmpty) return const ValidationResult.fail('NIN is required');
  if (!RegExp(r'^\d{11}$').hasMatch(v)) {
    return const ValidationResult.fail('NIN must be exactly 11 digits');
  }
  return const ValidationResult.ok();
}

/// vNIN — exactly 16 alphanumeric characters (letters + digits, uppercase).
ValidationResult validateVnin(String value) {
  final v = value.trim().toUpperCase();
  if (v.isEmpty) return const ValidationResult.fail('vNIN is required');
  if (!RegExp(r'^[A-Z0-9]{16}$').hasMatch(v)) {
    return const ValidationResult.fail(
        'vNIN must be exactly 16 alphanumeric characters');
  }
  return const ValidationResult.ok();
}

/// Nigerian International Passport — letter followed by 8 digits (e.g. A12345678).
ValidationResult validateNgPassport(String value) {
  final v = value.trim().toUpperCase();
  if (v.isEmpty) return const ValidationResult.fail('Passport number is required');
  if (!RegExp(r'^[A-Z]\d{8}$').hasMatch(v)) {
    return const ValidationResult.fail(
        'Passport number must be a letter followed by 8 digits (e.g. A12345678)');
  }
  return const ValidationResult.ok();
}

/// Nigerian Driver's License — state code (3 letters) + hyphen + up to 12
/// alphanumeric characters (e.g. FKJ-B123456A).
ValidationResult validateNgDriversLicense(String value) {
  final v = value.trim().toUpperCase();
  if (v.isEmpty) {
    return const ValidationResult.fail("Driver's License number is required");
  }
  if (!RegExp(r'^[A-Z]{3}-[A-Z0-9]{6,12}$').hasMatch(v)) {
    return const ValidationResult.fail(
        "Enter a valid Driver's License number (e.g. FKJ-B123456A)");
  }
  return const ValidationResult.ok();
}

/// Nigerian PVC (Permanent Voter's Card) — 19 alphanumeric characters.
ValidationResult validateNgPvc(String value) {
  final v = value.trim().toUpperCase();
  if (v.isEmpty) {
    return const ValidationResult.fail("Voter's Card number is required");
  }
  if (!RegExp(r'^[A-Z0-9]{19}$').hasMatch(v)) {
    return const ValidationResult.fail(
        "Voter's Card number must be 19 alphanumeric characters");
  }
  return const ValidationResult.ok();
}

// ─── Ghana ────────────────────────────────────────────────────────────────────

/// Ghana Card — GHA-XXXXXXXXX-Y (GHA + 9 digits + 1 check digit).
ValidationResult validateGhanaCard(String value) {
  final v = value.trim().toUpperCase();
  if (v.isEmpty) return const ValidationResult.fail('Ghana Card number is required');
  if (!RegExp(r'^GHA-\d{9}-\d$').hasMatch(v)) {
    return const ValidationResult.fail(
        'Ghana Card must be in the format GHA-123456789-0');
  }
  return const ValidationResult.ok();
}

/// Ghana Voter's Card — 10 digits.
ValidationResult validateGhanaVoters(String value) {
  final v = value.trim();
  if (v.isEmpty) {
    return const ValidationResult.fail("Voter's Card number is required");
  }
  if (!RegExp(r'^\d{10}$').hasMatch(v)) {
    return const ValidationResult.fail(
        "Voter's Card number must be exactly 10 digits");
  }
  return const ValidationResult.ok();
}

/// Ghana Driver's License — 8–12 alphanumeric characters.
ValidationResult validateGhanaDriversLicense(String value) {
  final v = value.trim().toUpperCase();
  if (v.isEmpty) {
    return const ValidationResult.fail("Driver's License number is required");
  }
  if (!RegExp(r'^[A-Z0-9]{8,12}$').hasMatch(v)) {
    return const ValidationResult.fail(
        "Driver's License must be 8–12 alphanumeric characters");
  }
  return const ValidationResult.ok();
}

/// Ghana SSNIT — letter + 8 digits (e.g. C123456789) or 13 alphanumeric chars.
ValidationResult validateGhanaSsnit(String value) {
  final v = value.trim().toUpperCase();
  if (v.isEmpty) return const ValidationResult.fail('SSNIT number is required');
  if (!RegExp(r'^[A-Z]\d{12}$').hasMatch(v) &&
      !RegExp(r'^[A-Z0-9]{10,14}$').hasMatch(v)) {
    return const ValidationResult.fail(
        'Enter a valid SSNIT number (e.g. C0123456789012)');
  }
  return const ValidationResult.ok();
}

/// Ghana Passport — G + 7 digits (e.g. G0123456).
ValidationResult validateGhanaPassport(String value) {
  final v = value.trim().toUpperCase();
  if (v.isEmpty) return const ValidationResult.fail('Passport number is required');
  if (!RegExp(r'^G\d{7}$').hasMatch(v)) {
    return const ValidationResult.fail(
        'Ghana Passport must start with G followed by 7 digits (e.g. G0123456)');
  }
  return const ValidationResult.ok();
}

// ─── Kenya ────────────────────────────────────────────────────────────────────

/// Kenya National ID — 1 to 8 digits.
ValidationResult validateKeNationalId(String value) {
  final v = value.trim();
  if (v.isEmpty) return const ValidationResult.fail('National ID number is required');
  if (!RegExp(r'^\d{1,8}$').hasMatch(v)) {
    return const ValidationResult.fail(
        'Kenya National ID must be 1–8 digits');
  }
  return const ValidationResult.ok();
}

/// Kenya Passport — letter + 7 digits (e.g. A1234567).
ValidationResult validateKePassport(String value) {
  final v = value.trim().toUpperCase();
  if (v.isEmpty) return const ValidationResult.fail('Passport number is required');
  if (!RegExp(r'^[A-Z]\d{7}$').hasMatch(v)) {
    return const ValidationResult.fail(
        'Kenya Passport must be a letter followed by 7 digits (e.g. A1234567)');
  }
  return const ValidationResult.ok();
}

// ─── South Africa ─────────────────────────────────────────────────────────────

/// South Africa National ID — exactly 13 digits (YYMMDD + 4 digits + citizenship + checksum).
ValidationResult validateZaNationalId(String value) {
  final v = value.trim();
  if (v.isEmpty) return const ValidationResult.fail('National ID number is required');
  if (!RegExp(r'^\d{13}$').hasMatch(v)) {
    return const ValidationResult.fail(
        'South African National ID must be exactly 13 digits');
  }
  // Basic Luhn-style sanity: first 6 digits encode YYMMDD
  final month = int.tryParse(v.substring(2, 4)) ?? 0;
  final day   = int.tryParse(v.substring(4, 6)) ?? 0;
  if (month < 1 || month > 12 || day < 1 || day > 31) {
    return const ValidationResult.fail(
        'National ID number contains an invalid date of birth');
  }
  return const ValidationResult.ok();
}

// ─── Côte d'Ivoire ────────────────────────────────────────────────────────────

/// CI CNI — 9 to 11 alphanumeric characters (e.g. CI0123456789).
ValidationResult validateCiCni(String value) {
  final v = value.trim().toUpperCase();
  if (v.isEmpty) return const ValidationResult.fail('CNI number is required');
  if (!RegExp(r'^[A-Z0-9]{9,11}$').hasMatch(v)) {
    return const ValidationResult.fail(
        'CNI number must be 9–11 alphanumeric characters');
  }
  return const ValidationResult.ok();
}

/// CI Residence Card — 9 to 13 alphanumeric characters.
ValidationResult validateCiResidenceCard(String value) {
  final v = value.trim().toUpperCase();
  if (v.isEmpty) return const ValidationResult.fail('Residence Card number is required');
  if (!RegExp(r'^[A-Z0-9]{9,13}$').hasMatch(v)) {
    return const ValidationResult.fail(
        'Residence Card number must be 9–13 alphanumeric characters');
  }
  return const ValidationResult.ok();
}

// ─── Dispatch helper ──────────────────────────────────────────────────────────

/// Validates [value] for the given [country] + [idType] combination.
/// Returns [ValidationResult.ok()] if the combination has no format rule.
ValidationResult validateIdNumber(
  String value,
  Country country,
  IdType idType,
) {
  return switch ((country, idType)) {
    (Country.NG, IdType.bvn)            => validateBvn(value),
    (Country.NG, IdType.nin)            => validateNin(value),
    (Country.NG, IdType.vnin)           => validateVnin(value),
    (Country.NG, IdType.passport)       => validateNgPassport(value),
    (Country.NG, IdType.driversLicense) => validateNgDriversLicense(value),
    (Country.NG, IdType.pvc)            => validateNgPvc(value),
    (Country.GH, IdType.ghanaCard)      => validateGhanaCard(value),
    (Country.GH, IdType.voters)         => validateGhanaVoters(value),
    (Country.GH, IdType.driversLicense) => validateGhanaDriversLicense(value),
    (Country.GH, IdType.ssnit)          => validateGhanaSsnit(value),
    (Country.GH, IdType.passport)       => validateGhanaPassport(value),
    (Country.KE, IdType.nationalId)     => validateKeNationalId(value),
    (Country.KE, IdType.passport)       => validateKePassport(value),
    (Country.ZA, IdType.nationalId)     => validateZaNationalId(value),
    (Country.CI, IdType.cni)            => validateCiCni(value),
    (Country.CI, IdType.residenceCard)  => validateCiResidenceCard(value),
    _                                   => const ValidationResult.ok(),
  };
}

// ─── Masking helper ───────────────────────────────────────────────────────────

/// Masks an ID number for logs: shows first 4 + last 3 digits, rest as '*'.
/// e.g. "12345678901" → "1234****901"
String maskIdNumber(String id) {
  if (id.length <= 7) return '*' * id.length;
  final prefix = id.substring(0, 4);
  final suffix = id.substring(id.length - 3);
  final masked = '*' * (id.length - 7);
  return '$prefix$masked$suffix';
}
