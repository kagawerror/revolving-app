// Pure validation for an approver's replenishment **rejection remarks**.
//
// An approver must explain *why* a submitted replenishment report is being
// rejected before the rejection is allowed to go through. The incharge reads
// this remark on the report's detail screen, so an empty or throwaway value
// ("no", "x") defeats the purpose.
//
// This is the single source of truth for "is this remark acceptable?" — it is
// reused by the rejection sheet's live field validation AND re-checked before
// the repository call, so the rule can never be bypassed by the UI.

/// Minimum number of (trimmed) characters a rejection remark must contain.
const int kMinRejectionRemarksLength = 10;

/// Validates an approver's rejection [raw] remark.
///
/// Returns `null` when the remark is acceptable, or a short, user-facing error
/// message when it is not (matching the `String? Function(String)` shape Flutter
/// form validators expect).
String? validateRejectionRemarks(String raw) {
  final text = raw.trim();
  if (text.isEmpty) return 'A reason is required to reject.';
  if (text.length < kMinRejectionRemarksLength) {
    return 'Please be specific — at least $kMinRejectionRemarksLength characters.';
  }
  return null;
}
