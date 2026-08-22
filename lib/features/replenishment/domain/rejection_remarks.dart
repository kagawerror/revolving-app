// Moved to `lib/core/validation/rejection_remarks.dart`.
//
// The rule is now shared by TWO features — replenishment (an approver rejecting
// a submitted report) and requests (an incharge cancelling a still-unreleased
// request) — so it lives in `core/`. A `requests → replenishment` import would
// break the feature-first boundary; both now depend inward on core instead.
//
// This re-export keeps the existing replenishment call sites unchanged.
export '../../../core/validation/rejection_remarks.dart';
