/// Outcome of replaying a captured offline release through the server-side
/// confirm transaction (`RequestRepository.confirmPendingRelease`).
///
/// - [confirmed]: this replay debited the fund exactly once and flipped the
///   request's `releaseState` to `serverConfirmed`.
/// - [alreadyConfirmed]: the request was already `serverConfirmed` (a previous
///   replay committed then died, or another device confirmed it). NO second
///   debit — idempotent no-op.
/// - [conflict]: the fund can no longer cover the release (another device
///   drained it). The request landed in `conflict` for the incharge to resolve;
///   the fund was NOT touched.
enum ReleaseSyncResult { confirmed, alreadyConfirmed, conflict }
