// Pure validation for a **rejection remark** — the written reason an actor
// must give before a rejection is allowed to go through.
//
// Two flows share this rule:
//  - replenishment: an approver rejecting a submitted report (the incharge
//    reads the remark on the report's detail screen);
//  - requests: an incharge cancelling a still-unreleased request, where the
//    remark is the only record of WHY cash that was requested never moved.
//
// In both, an empty or throwaway value ("no", "x") defeats the purpose and
// leaves an audit gap.
//
// This is the single source of truth for "is this remark acceptable?" — it is
// reused by each rejection sheet's live field validation AND re-checked in the
// repository before any write, so the rule can never be bypassed by the UI.

/// Minimum number of (trimmed) characters a rejection remark must contain.
const int kMinRejectionRemarksLength = 10;

/// Validates a rejection [raw] remark.
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
