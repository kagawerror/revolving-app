# Revolving Fund App — Phase 5 Design Spec (Push via OneSignal, free tier)

- **Date:** 2026-06-03
- **Status:** Approved (extends Phases 1–4); supersedes the earlier firebase_messaging draft.
- **Builds on:** the Phase 4 `notifications` collection + in-app alerts.

## 1. Purpose

Deliver the existing in-app alerts (low-balance, replenishment submitted/approved/rejected) to
devices as push notifications using **OneSignal's free tier** — chosen so the project stays entirely
on Firebase's free **Spark** plan (no Cloud Functions / Blaze). OneSignal manages device tokens; a
tiny **free Cloudflare Worker relay** holds the OneSignal REST key and performs the actual sends.

## 2. Locked decisions

| Decision | Choice |
|---|---|
| Push provider | **OneSignal** (free tier, unlimited mobile push) |
| Server/sender | **Cloudflare Worker relay** (free, always-on) holding the OneSignal REST key — NOT Cloud Functions |
| Platforms | **Android first** (OneSignal links to FCM via your service account in its dashboard); iOS deferred (APNs) |
| Foreground UX | **In-app SnackBar** (we intercept the foreground display) |
| Firestore token storage | **None** — OneSignal owns tokens; we only set identity (external id + tags) |

## 3. Why a relay is still required

Sending a push to *other* users requires the OneSignal **REST API key**, a secret that must never
ship in the app (it would let anyone push to all users). The relay is the only place that key lives.
The app sends a push *request* (not the key) to the relay; the relay calls OneSignal. The relay is
stateless and needs **no** Firestore access — the app passes the audience (`companyId`,
`recipientRoles`) and text, and the relay maps those to OneSignal tag filters.

## 4. Architecture

**Client (Flutter):**
- `services/messaging/onesignal_service.dart` — thin wrapper over `onesignal_flutter`: `init(appId)`,
  `requestPermission()`, `login(uid)` / `logout()`, `setAudienceTags(companyId, role)`, foreground
  + click listeners. Plugin-bound; not unit-tested.
- `features/messaging/domain/push_sender.dart` — `PushSender` interface
  (`notify({companyId, recipientRoles, title, body})`).
- `features/messaging/data/http_push_sender.dart` — `HttpPushSender` POSTs the request to the relay
  URL (injectable `http.Client`). A `NoopPushSender` (no-op) is the default in repositories/tests.
- `features/messaging/presentation/messaging_providers.dart` + `messaging_initializer.dart` — on
  sign-in: init OneSignal, request permission, `login(uid)`, set tags; on sign-out: `logout()`.
  Foreground → SnackBar via a global `scaffoldMessengerKey`; click → Alerts via `rootNavigatorKey`.
- Global keys in `lib/app_keys.dart`; wired in `main.dart` / `app_router.dart`.

**Identity model (how targeting works):**
- Each signed-in device calls `OneSignal.login(uid)` and is tagged `company_id` + `role`.
- To alert "incharges of company c1", the relay sends a OneSignal notification filtered by
  `company_id == c1 AND role == incharge`. For multiple recipient roles, the relay sends **one
  OneSignal request per role** (avoids tag AND/OR precedence pitfalls).

**Sending path:**
- The repositories that create a notification doc (release low-balance; replenishment
  submit/approve/reject) ALSO call the injected `PushSender.notify(...)` (fire-and-forget, errors
  swallowed — never affects the money transaction). Default `NoopPushSender` keeps existing tests
  HTTP-free; the app wires `HttpPushSender`.

**Relay (Cloudflare Worker, TypeScript — provided, deployed by the user):**
- `POST /` with `{companyId, recipientRoles[], title, body}` → for each role, calls the OneSignal
  REST API (`/notifications`) with the app id + a filter on `company_id` and `role`. Holds
  `ONESIGNAL_APP_ID` + `ONESIGNAL_REST_KEY` as Worker secrets. Optionally checks a shared
  `RELAY_TOKEN` header so only the app can invoke it.

## 5. Configuration (.env via --dart-define)

- `ONESIGNAL_APP_ID` — public app id (safe in app).
- `PUSH_RELAY_URL` — the deployed Worker URL.
- `PUSH_RELAY_TOKEN` — optional shared token the app sends to the relay (the OneSignal REST key is
  NOT in the app — only in the Worker).

## 6. Security

- The OneSignal **REST API key lives only in the Cloudflare Worker** (secret), never in the app or
  Firestore.
- No Firestore rule changes needed (no token storage). The relay needs no Firestore access.
- Optional `PUSH_RELAY_TOKEN` shared header limits who can invoke the relay.

## 7. Dependencies

- Add `onesignal_flutter`. `firebase_messaging` is no longer used for push (left in pubspec; may be
  removed later). `http` (already present) for the relay call.

## 8. Out of scope (deferred)

- iOS APNs (needs an Apple Developer APNs key + OneSignal iOS config).
- Per-notification deep-link payloads (we navigate to the Alerts list for any push).
- Server-side audience dedup / quiet hours / batching.
- Real-time dashboard (Phase 6).

## 9. Setup the user performs (documented in SETUP.md)

1. Create a free OneSignal app; under it, configure the **Google Android (FCM)** platform by
   uploading the Firebase service-account JSON (so OneSignal can deliver via FCM). Copy the
   **App ID** and **REST API Key**.
2. Deploy the provided Cloudflare Worker (free) with `ONESIGNAL_APP_ID`, `ONESIGNAL_REST_KEY`
   (and optional `RELAY_TOKEN`) as secrets; copy its URL.
3. Put `ONESIGNAL_APP_ID`, `PUSH_RELAY_URL` (and `PUSH_RELAY_TOKEN`) in `.env`; run with
   `--dart-define-from-file=.env`.
