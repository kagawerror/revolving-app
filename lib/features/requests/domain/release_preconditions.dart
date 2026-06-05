import '../../../core/error/failure.dart';

/// Pure precondition for a cash release: both the release proof photo and the
/// recipient signature are MANDATORY. Returns a [ValidationFailure] describing
/// the first missing piece, or `null` when both are present.
///
/// Pure Dart — no Firebase. Called at the top of the release repository method
/// (before any transaction) and mirrored independently in `firestore.rules`.
Failure? ensureReleaseSignature({
  required String releaseProofUrl,
  required String releaseSignatureUrl,
}) {
  if (releaseProofUrl.trim().isEmpty) {
    return const ValidationFailure('A release proof photo is required.');
  }
  if (releaseSignatureUrl.trim().isEmpty) {
    return const ValidationFailure('A recipient signature is required.');
  }
  return null;
}
