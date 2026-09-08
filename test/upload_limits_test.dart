import 'dart:convert';
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:myaza_kyc_sdk_flutter/src/config/upload_limits.dart';

// ─── The shared vectors (test/upload_limits_vectors.json) ─────────────────────
//
// The size rule and the hint under every drop zone are data the three SDKs
// must agree on; one file holds them and each mirror's test reads it.

void main() {
  final vectors = jsonDecode(
      File('test/upload_limits_vectors.json').readAsStringSync())
      as Map<String, dynamic>;

  test('carry the shared caps and hint', () {
    expect(kImageMaxBytes, vectors['imageMaxBytes']);
    expect(kPdfMaxBytes, vectors['pdfMaxBytes']);
    expect(kUploadHint, vectors['hint']);
    expect(kUploadHint.contains('—'), isFalse);
  });

  for (final raw in vectors['cases'] as List<dynamic>) {
    final c = raw as Map<String, dynamic>;
    test(c['name'] as String, () {
      expect(uploadSizeError(c['mime'] as String?, c['bytes'] as int?),
          c['error'] as String?);
    });
  }

  test('the drop zones read the hint from the one constant', () {
    for (final rel in [
      'lib/src/screens/proof_of_address_parts.dart',
      'lib/src/screens/business_document_slot.dart',
    ]) {
      final src = File(rel).readAsStringSync();
      expect(src, contains('kUploadHint'));
      expect(src, isNot(contains('up to 20MB')));
    }
  });
}
