// ─── Upload size limits ───────────────────────────────────────────────────────
//
// One rule for every document the applicant attaches (proof of address, the
// KYB company documents, the entrance photo): images up to 5 MB, PDFs up to
// 15 MB (user decision 2026-09-06). The server's own cap is higher, so refusing
// here gives an immediate, specific message instead of a slow 413. A THREE-WAY
// MIRROR with the web SDK's `lib/upload-limits.ts` and RN's
// `config/uploadLimits.ts`, pinned to `test/upload_limits_vectors.json`.

const int kImageMaxBytes = 5 * 1024 * 1024;
const int kPdfMaxBytes = 15 * 1024 * 1024;

/// The line under every drop zone: what is accepted, and how big.
const String kUploadHint = 'PDF, JPG, PNG · PDF max 15 MB, images max 5 MB';

bool isPdfMime(String? mime) =>
    (mime?.split(';').first ?? '').trim().toLowerCase() == 'application/pdf';

/// The refusal for a file over its cap, or null when it fits. An unknown size
/// also passes: the server still judges the bytes at its own cap, and a picker
/// that reports no size must not block a good file.
String? uploadSizeError(String? mime, int? bytes) {
  if (bytes == null) return null;
  if (isPdfMime(mime)) {
    return bytes > kPdfMaxBytes ? 'PDF is too large (max 15 MB).' : null;
  }
  return bytes > kImageMaxBytes ? 'Image is too large (max 5 MB).' : null;
}
