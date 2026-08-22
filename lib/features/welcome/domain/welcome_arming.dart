import '../../auth/domain/app_user.dart';

/// Decides whether the welcome overlay should be *re-armed* (shown again) in
/// response to an auth-state change, given the [previous] and [next] signed-in
/// user (each `null` when signed out / still loading).
///
/// This is the testable seam behind the "show the welcome on every login, not
/// just on cold start / sign-out" behaviour. The root [RevApp] listener feeds
/// `currentUserProvider`'s transitions through here and, when this returns
/// `true`, flips `welcomeDismissedProvider` back to `false`.
///
/// It must return `true` for a *new signed-in identity* appearing — a login
/// (`null -> user`) or a user switch (`userA -> userB`) — and `false`
/// otherwise. In particular it must stay `false` for:
///  - a re-emit of the *same* user (the profile stream fires on any doc change
///    — theme, accent, name — and we must not slam the welcome over the app
///    mid-use), and
///  - sign-out (`user -> null`), which is armed separately in `signOutProvider`.
///
// Keyed on identity (`uid`) rather than a plain null-check: a `userA -> userB`
// switch (both non-null) is a new signed-in identity and must greet too, which
// a `previous == null` test would miss. A re-emit of the same user has equal
// uids → no re-arm; sign-out has `next == null` → no re-arm.
bool shouldRearmWelcome(AppUser? previous, AppUser? next) {
  return next != null && previous?.uid != next.uid;
}
