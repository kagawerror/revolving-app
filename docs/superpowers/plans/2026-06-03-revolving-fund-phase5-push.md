# Revolving Fund App — Phase 5 Implementation Plan (Push via OneSignal, free tier)

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development. Steps use checkbox (`- [ ]`) syntax.

**Goal:** Deliver the existing in-app alerts as push notifications using OneSignal (free) — client identity + receive on the device, and sends performed by a free Cloudflare Worker relay (holds the OneSignal REST key). No Cloud Functions / Blaze; Firestore stays on Spark.

**Architecture:** OneSignal client (`login(uid)` + `company_id`/`role` tags), foreground→SnackBar, click→Alerts. A `PushSender` abstraction (default `NoopPushSender`; app uses `HttpPushSender` → the relay). The repos that create a notification doc also fire `PushSender.notify(...)` (fire-and-forget). The Worker maps `{companyId, recipientRoles, title, body}` to OneSignal tag-filtered sends.

**Reference spec:** `docs/superpowers/specs/2026-06-03-revolving-fund-phase5-push-design.md`

**Builds on:** Phase 4 `notifications` writes inside `FirestoreRequestRepository.release` (low-balance) and `FirestoreReplenishmentRepository` (`submit`/`approve`/`reject` via `_addNotification`); `currentUserProvider`/`AppUser` (uid, companyId, role.name); `AlertsScreen`; role-guarded go_router (refreshListenable); `http` + `mocktail` + `fake_cloud_firestore`.

---

## File Structure (Phase 5)

```
lib/services/messaging/onesignal_service.dart
lib/features/messaging/domain/push_sender.dart
lib/features/messaging/data/http_push_sender.dart        # + NoopPushSender
lib/features/messaging/presentation/messaging_providers.dart
lib/features/messaging/presentation/messaging_initializer.dart
lib/app_keys.dart
lib/main.dart                      # init OneSignal, keys, initializer
lib/routing/app_router.dart        # rootNavigatorKey
relay/                             # Cloudflare Worker (TypeScript) — deployed by user
  src/index.ts
  wrangler.toml
  README.md
SETUP.md                           # push setup
android/app/src/main/AndroidManifest.xml  # POST_NOTIFICATIONS
.env.example                       # ONESIGNAL_APP_ID, PUSH_RELAY_URL, PUSH_RELAY_TOKEN
```

---

# SLICE I — OneSignal client (identity + receive)

### Task 32: Dependencies + config + Android permission

**Files:** Modify `pubspec.yaml`, `lib/core/config/app_secrets.dart`, `.env.example`, `android/app/src/main/AndroidManifest.xml`.

- [ ] **Step 1:** Add to `pubspec.yaml` dependencies: `onesignal_flutter: ^5.3.0` (use the latest 5.x that resolves). Run `flutter pub get`; if 5.3.0 doesn't resolve, pick the nearest 5.x and note it.

- [ ] **Step 2:** Add to `lib/core/config/app_secrets.dart`:

```dart
  static const String oneSignalAppId =
      String.fromEnvironment('ONESIGNAL_APP_ID');
  static const String pushRelayUrl =
      String.fromEnvironment('PUSH_RELAY_URL');
  static const String pushRelayToken =
      String.fromEnvironment('PUSH_RELAY_TOKEN');

  static bool get hasOneSignal => oneSignalAppId.isNotEmpty;
  static bool get hasPushRelay => pushRelayUrl.isNotEmpty;
```

- [ ] **Step 3:** Append to `.env.example`:

```
# OneSignal (free push). App ID is public/safe in-app; the REST key lives ONLY in the relay.
ONESIGNAL_APP_ID=
# Cloudflare Worker relay URL + optional shared token
PUSH_RELAY_URL=
PUSH_RELAY_TOKEN=
```

- [ ] **Step 4:** Add inside `<manifest>` in `AndroidManifest.xml` (alongside CAMERA):

```xml
<uses-permission android:name="android.permission.POST_NOTIFICATIONS"/>
```

- [ ] **Step 5:** `flutter analyze` clean; `flutter test` green. **Commit** `chore(messaging): add onesignal_flutter, push config, POST_NOTIFICATIONS`

---

### Task 33: `OneSignalService` wrapper

**Files:** Create `lib/services/messaging/onesignal_service.dart`. (Plugin-bound; no unit test.)

> NOTE: match the installed `onesignal_flutter` (v5+) API. The method names below are v5; if the resolved version differs, adapt to its API and keep the same behavior. Do not invent APIs — read the package's exported symbols if unsure.

- [ ] **Step 1: Implement**

```dart
import 'package:onesignal_flutter/onesignal_flutter.dart';

/// Thin wrapper over OneSignal for init, identity, tags, and listeners.
class OneSignalService {
  bool _initialized = false;

  Future<void> init(String appId) async {
    if (_initialized || appId.isEmpty) return;
    OneSignal.initialize(appId);
    _initialized = true;
  }

  Future<bool> requestPermission() => OneSignal.Notifications.requestPermission(true);

  Future<void> login(String externalId) => OneSignal.login(externalId);
  Future<void> logout() => OneSignal.logout();

  Future<void> setAudienceTags({required String companyId, required String role}) =>
      OneSignal.User.addTags({'company_id': companyId, 'role': role});

  /// Foreground: prevent the default OS display and forward the title/body.
  void onForeground(void Function(String? title, String? body) handler) {
    OneSignal.Notifications.addForegroundWillDisplayListener((event) {
      event.preventDefault();
      handler(event.notification.title, event.notification.body);
    });
  }

  void onClick(void Function() handler) {
    OneSignal.Notifications.addClickListener((event) => handler());
  }
}
```

- [ ] **Step 2:** `flutter analyze lib/services/messaging`. **Commit** `feat(messaging): OneSignal service wrapper`

---

### Task 34: Global keys + providers + `MessagingInitializer`

**Files:** Create `lib/app_keys.dart`, `lib/features/messaging/presentation/messaging_providers.dart`, `lib/features/messaging/presentation/messaging_initializer.dart`.

- [ ] **Step 1: `lib/app_keys.dart`**

```dart
import 'package:flutter/material.dart';

final GlobalKey<ScaffoldMessengerState> scaffoldMessengerKey =
    GlobalKey<ScaffoldMessengerState>();
final GlobalKey<NavigatorState> rootNavigatorKey = GlobalKey<NavigatorState>();
```

- [ ] **Step 2: `messaging_providers.dart`** (the `PushSender` providers are added in Slice J; this slice only needs the OneSignal service)

```dart
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../services/messaging/onesignal_service.dart';

final oneSignalServiceProvider =
    Provider<OneSignalService>((ref) => OneSignalService());
```

- [ ] **Step 3: `messaging_initializer.dart`**

```dart
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../app_keys.dart';
import '../../../core/config/app_secrets.dart';
import '../../auth/domain/app_user.dart';
import '../../auth/presentation/auth_providers.dart';
import '../../notifications/presentation/alerts_screen.dart';
import 'messaging_providers.dart';

class MessagingInitializer extends ConsumerStatefulWidget {
  final Widget child;
  const MessagingInitializer({super.key, required this.child});
  @override
  ConsumerState<MessagingInitializer> createState() => _MessagingInitializerState();
}

class _MessagingInitializerState extends ConsumerState<MessagingInitializer> {
  bool _wired = false;
  String? _identityUid;

  Future<void> _ensureInit() async {
    if (_wired || !AppSecrets.hasOneSignal) return;
    _wired = true;
    final svc = ref.read(oneSignalServiceProvider);
    await svc.init(AppSecrets.oneSignalAppId);
    svc.onForeground((title, body) {
      final text = title ?? body ?? 'New notification';
      scaffoldMessengerKey.currentState
          ?.showSnackBar(SnackBar(content: Text(text)));
    });
    svc.onClick(() {
      rootNavigatorKey.currentState
          ?.push(MaterialPageRoute(builder: (_) => const AlertsScreen()));
    });
  }

  Future<void> _onUser(AppUser? user) async {
    await _ensureInit();
    if (!AppSecrets.hasOneSignal) return;
    final svc = ref.read(oneSignalServiceProvider);
    if (user == null) {
      if (_identityUid != null) {
        _identityUid = null;
        await svc.logout();
      }
      return;
    }
    if (_identityUid == user.uid) return;
    _identityUid = user.uid;
    await svc.requestPermission();
    await svc.login(user.uid);
    await svc.setAudienceTags(companyId: user.companyId, role: user.role.name);
  }

  @override
  Widget build(BuildContext context) {
    ref.listen(currentUserProvider, (_, next) => _onUser(next.valueOrNull));
    return widget.child;
  }
}
```

- [ ] **Step 4:** `flutter analyze`. **Commit** `feat(messaging): global keys, providers, MessagingInitializer (OneSignal identity + handlers)`

---

### Task 35: Wire `main.dart` + router + sign-out logout

**Files:** Modify `lib/main.dart`, `lib/routing/app_router.dart`, `lib/features/{companies,requests}/presentation/*_home_screen.dart` sign-out buttons.

- [ ] **Step 1: `main.dart`** — set the messenger key + wrap with the initializer:

```dart
return MaterialApp.router(
  title: 'Revolving Fund',
  theme: AppTheme.light(),
  routerConfig: router,
  scaffoldMessengerKey: scaffoldMessengerKey,
  builder: (context, child) =>
      MessagingInitializer(child: child ?? const SizedBox.shrink()),
);
```
Add imports: `app_keys.dart`, `features/messaging/presentation/messaging_initializer.dart`. (No OneSignal init in `main()` itself — the initializer handles it once a session exists.)

- [ ] **Step 2: `app_router.dart`** — give GoRouter the shared navigator key:

```dart
return GoRouter(
  navigatorKey: rootNavigatorKey,
  initialLocation: '/login',
  refreshListenable: refresh,
  // ... unchanged
);
```
Add `import '../app_keys.dart';`.

- [ ] **Step 3: sign-out logout** — add to `messaging_providers.dart`:

```dart
import '../../auth/presentation/auth_providers.dart';
// ...
final signOutProvider = Provider<Future<void> Function()>((ref) {
  return () async {
    try {
      await ref.read(oneSignalServiceProvider).logout();
    } catch (_) {
      // best-effort; sign out regardless
    }
    await ref.read(authRepositoryProvider).signOut();
  };
});
```

- [ ] **Step 4:** In `admin_home_screen.dart`, `incharge_home_screen.dart`, `approver_home_screen.dart`, replace the logout `onPressed: () => ref.read(authRepositoryProvider).signOut(),` with `onPressed: () => ref.read(signOutProvider)(),` (import `messaging_providers.dart`; drop the now-unused `authRepositoryProvider` import if unused).

- [ ] **Step 5:** `flutter analyze && flutter test` (green). **Commit** `feat(messaging): wire OneSignal init, keys, router navigatorKey, sign-out logout`

---

# SLICE J — Push sending (PushSender + relay)

### Task 36: `PushSender` + `HttpPushSender` (TDD) + `NoopPushSender`

**Files:** Create `lib/features/messaging/domain/push_sender.dart`, `lib/features/messaging/data/http_push_sender.dart`; Test `test/features/messaging/data/http_push_sender_test.dart`.

- [ ] **Step 1: Interface + Noop** `push_sender.dart`

```dart
abstract interface class PushSender {
  /// Best-effort push to all users in [companyId] holding any of [recipientRoles].
  Future<void> notify({
    required String companyId,
    required List<String> recipientRoles,
    required String title,
    required String body,
  });
}

/// Default no-op (used in tests and when no relay is configured).
class NoopPushSender implements PushSender {
  const NoopPushSender();
  @override
  Future<void> notify({
    required String companyId,
    required List<String> recipientRoles,
    required String title,
    required String body,
  }) async {}
}
```

- [ ] **Step 2: Failing test** `http_push_sender_test.dart`

```dart
import 'dart:convert';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:rev_app/features/messaging/data/http_push_sender.dart';

class _MockClient extends http.BaseClient {
  final List<http.Request> sent = [];
  final int status;
  _MockClient([this.status = 200]);
  @override
  Future<http.StreamedResponse> send(http.BaseRequest request) async {
    sent.add(request as http.Request);
    return http.StreamedResponse(Stream.value(utf8.encode('ok')), status);
  }
}

void main() {
  test('POSTs audience + text to the relay URL with token header', () async {
    final client = _MockClient();
    final sender = HttpPushSender(
        relayUrl: 'https://relay.example/', relayToken: 'secret', client: client);
    await sender.notify(
        companyId: 'c1', recipientRoles: ['incharge'], title: 'T', body: 'B');
    expect(client.sent, hasLength(1));
    final req = client.sent.single;
    expect(req.method, 'POST');
    expect(req.url.toString(), 'https://relay.example/');
    expect(req.headers['x-relay-token'], 'secret');
    final body = jsonDecode(req.body) as Map<String, dynamic>;
    expect(body['companyId'], 'c1');
    expect(body['recipientRoles'], ['incharge']);
    expect(body['title'], 'T');
  });

  test('swallows errors (never throws) on non-200', () async {
    final sender = HttpPushSender(
        relayUrl: 'https://relay.example/', relayToken: '', client: _MockClient(500));
    // Should complete without throwing.
    await sender.notify(
        companyId: 'c1', recipientRoles: ['incharge'], title: 'T', body: 'B');
  });

  test('no-ops when relayUrl is empty', () async {
    final client = _MockClient();
    final sender = HttpPushSender(relayUrl: '', relayToken: '', client: client);
    await sender.notify(
        companyId: 'c1', recipientRoles: ['incharge'], title: 'T', body: 'B');
    expect(client.sent, isEmpty);
  });
}
```

- [ ] **Step 3: Run → FAIL.**

- [ ] **Step 4: Implement** `http_push_sender.dart`

```dart
import 'dart:async';
import 'dart:convert';
import 'dart:developer' as developer;

import 'package:http/http.dart' as http;

import '../domain/push_sender.dart';

class HttpPushSender implements PushSender {
  final String relayUrl;
  final String relayToken;
  final http.Client client;

  HttpPushSender({
    required this.relayUrl,
    required this.relayToken,
    http.Client? client,
  }) : client = client ?? http.Client();

  @override
  Future<void> notify({
    required String companyId,
    required List<String> recipientRoles,
    required String title,
    required String body,
  }) async {
    if (relayUrl.isEmpty) return;
    try {
      await client
          .post(
            Uri.parse(relayUrl),
            headers: {
              'content-type': 'application/json',
              if (relayToken.isNotEmpty) 'x-relay-token': relayToken,
            },
            body: jsonEncode({
              'companyId': companyId,
              'recipientRoles': recipientRoles,
              'title': title,
              'body': body,
            }),
          )
          .timeout(const Duration(seconds: 10));
    } catch (e, st) {
      // Best-effort: a failed push must never affect the triggering operation.
      developer.log('push relay failed', name: 'push', error: e, stackTrace: st);
    }
  }
}
```

- [ ] **Step 5: Run → PASS.** **Commit** `feat(messaging): PushSender abstraction + HttpPushSender (TDD) + Noop`

---

### Task 37: Inject `PushSender` into the notification-producing repos

**Files:** Modify `lib/features/requests/data/firestore_request_repository.dart`, `lib/features/replenishment/data/firestore_replenishment_repository.dart`, `lib/features/messaging/presentation/messaging_providers.dart`, and the repos' providers in `request_providers.dart` / `replenishment_providers.dart`.

- [ ] **Step 1:** Add a `PushSender` to `FirestoreRequestRepository` as an OPTIONAL constructor arg (default `NoopPushSender`) so existing tests/constructors are unaffected:

```dart
final PushSender _push;
FirestoreRequestRepository(this._db, [PushSender? push]) : _push = push ?? const NoopPushSender();
```
In `release(...)`, capture whether the fund NEWLY went low (set a flag inside the transaction alongside the existing lowBalance `tx.set`). After `runTransaction` returns Ok, if it newly went low, fire-and-forget:
```dart
if (_newlyLow) {
  _push.notify(
    companyId: fund.companyId,
    recipientRoles: const ['incharge'],
    title: 'Fund ${fund.name} is low',
    body: 'A fund has reached its low-balance threshold. Replenish soon.',
  ); // not awaited — best-effort
}
```
(Use a local captured from the tx; `fund` here is the pre-release snapshot — its `companyId`/`name` are correct. Add `import '../../messaging/domain/push_sender.dart';`.)

- [ ] **Step 2:** Add the same optional `PushSender` to `FirestoreReplenishmentRepository`. After each successful `_addNotification(...)` call (submit/approve/reject), fire `_push.notify(...)` with the SAME companyId/recipientRoles/title/body used for that notification (extract a tiny helper to avoid duplication). Not awaited.

- [ ] **Step 3:** In `messaging_providers.dart`, add:

```dart
import '../../../core/config/app_secrets.dart';
import '../data/http_push_sender.dart';
import '../domain/push_sender.dart';

final pushSenderProvider = Provider<PushSender>((ref) => HttpPushSender(
      relayUrl: AppSecrets.pushRelayUrl,
      relayToken: AppSecrets.pushRelayToken,
    ));
```

- [ ] **Step 4:** Update `requestRepositoryProvider` and `replenishmentRepositoryProvider` to pass the push sender:

```dart
final requestRepositoryProvider = Provider<RequestRepository>(
    (ref) => FirestoreRequestRepository(ref.watch(firestoreProvider), ref.watch(pushSenderProvider)));
// and similarly for replenishmentRepositoryProvider
```
(Import `messaging_providers.dart` where these live.)

- [ ] **Step 5:** `flutter analyze && flutter test` — all existing tests still pass (they construct repos WITHOUT a push sender → Noop, no HTTP). **Commit** `feat(messaging): fire best-effort push on low-balance + replenishment events`

---

### Task 38: Cloudflare Worker relay (TypeScript)

**Files:** Create `relay/src/index.ts`, `relay/wrangler.toml`, `relay/README.md`. (Not built/deployed in this repo's CI — it's a separate free deploy.)

- [ ] **Step 1: `relay/src/index.ts`**

```ts
// Free Cloudflare Worker: receives {companyId, recipientRoles, title, body} from the app
// and sends one OneSignal push per role, filtered by company_id + role tags.
// Secrets (wrangler secret put): ONESIGNAL_APP_ID, ONESIGNAL_REST_KEY, RELAY_TOKEN (optional).

export interface Env {
  ONESIGNAL_APP_ID: string;
  ONESIGNAL_REST_KEY: string;
  RELAY_TOKEN?: string;
}

interface PushRequest {
  companyId: string;
  recipientRoles: string[];
  title: string;
  body: string;
}

export default {
  async fetch(req: Request, env: Env): Promise<Response> {
    if (req.method !== 'POST') return new Response('Method not allowed', { status: 405 });
    if (env.RELAY_TOKEN && req.headers.get('x-relay-token') !== env.RELAY_TOKEN) {
      return new Response('Unauthorized', { status: 401 });
    }
    let payload: PushRequest;
    try {
      payload = await req.json();
    } catch {
      return new Response('Bad JSON', { status: 400 });
    }
    const { companyId, recipientRoles, title, body } = payload;
    if (!companyId || !Array.isArray(recipientRoles) || recipientRoles.length === 0) {
      return new Response('Missing fields', { status: 400 });
    }

    const results = await Promise.allSettled(
      recipientRoles.map((role) =>
        fetch('https://api.onesignal.com/notifications', {
          method: 'POST',
          headers: {
            'content-type': 'application/json',
            Authorization: `Key ${env.ONESIGNAL_REST_KEY}`,
          },
          body: JSON.stringify({
            app_id: env.ONESIGNAL_APP_ID,
            target_channel: 'push',
            filters: [
              { field: 'tag', key: 'company_id', relation: '=', value: companyId },
              { operator: 'AND' },
              { field: 'tag', key: 'role', relation: '=', value: role },
            ],
            headings: { en: title },
            contents: { en: body },
          }),
        })
      )
    );

    const ok = results.filter((r) => r.status === 'fulfilled').length;
    return new Response(JSON.stringify({ sent: ok, roles: recipientRoles.length }), {
      headers: { 'content-type': 'application/json' },
    });
  },
};
```

- [ ] **Step 2: `relay/wrangler.toml`**

```toml
name = "rev-app-push-relay"
main = "src/index.ts"
compatibility_date = "2024-11-01"
```

- [ ] **Step 3: `relay/README.md`** — document: `npm i -g wrangler`; `wrangler secret put ONESIGNAL_APP_ID`, `ONESIGNAL_REST_KEY`, `RELAY_TOKEN`; `wrangler deploy`; copy the URL into the app's `.env` `PUSH_RELAY_URL` (+ `PUSH_RELAY_TOKEN`). Note the free tier (100k req/day) and that the OneSignal REST key lives only here.

- [ ] **Step 4: Commit** `feat(relay): free Cloudflare Worker that sends OneSignal pushes`

---

### Task 39: SETUP.md push section

**Files:** Modify `SETUP.md`.

- [ ] **Step 1:** Append a "Push notifications (Phase 5 — OneSignal, free)" section:
  1. Create a free OneSignal app; add the **Google Android (FCM)** platform by uploading your Firebase service-account JSON. Copy the **App ID** + **REST API Key**.
  2. Deploy `relay/` (see `relay/README.md`) with the App ID + REST key as Worker secrets; copy the Worker URL.
  3. Put `ONESIGNAL_APP_ID`, `PUSH_RELAY_URL`, `PUSH_RELAY_TOKEN` in `.env`; run with `--dart-define-from-file=.env`.
  4. Identity: the app calls `OneSignal.login(uid)` and tags `company_id`/`role`; the relay targets those tags. iOS push (APNs) is deferred.

- [ ] **Step 2: Commit** `docs: document OneSignal push setup`

---

## Manual Verification (end of Phase 5)

(Requires OneSignal app + deployed relay + a real Android device.)
1. Sign in → app requests notification permission → in OneSignal dashboard the device appears with `company_id`/`role` tags and external id = uid.
2. Trigger a low-balance (release that crosses threshold) → the incharge device gets a push; tapping opens Alerts; app open → SnackBar.
3. Submit/approve/reject a replenishment → the right role receives a push.
4. Sign out → `OneSignal.logout()` (device no longer tied to that uid).

## Self-Review (against the Phase 5 spec)

- **Coverage:** OneSignal identity (login + tags) ✓; foreground SnackBar ✓; click→Alerts ✓; sign-out logout ✓; PushSender abstraction + HttpPushSender (TDD) + Noop default ✓; fire push on low-balance + replenishment events ✓; free Cloudflare Worker relay ✓; config + SETUP ✓; Android POST_NOTIFICATIONS ✓.
- **Free-tier:** no Cloud Functions/Blaze; Firestore unchanged; OneSignal + Cloudflare both free; REST key only in the Worker.
- **Testability:** `HttpPushSender` is unit-tested; OneSignal wrapper + initializer are plugin/UI-bound (manual verification). Existing repos use `NoopPushSender` in tests (no HTTP).
- **Type consistency:** `PushSender.notify`, `oneSignalServiceProvider`/`pushSenderProvider`/`signOutProvider`, global keys, relay payload `{companyId, recipientRoles, title, body}` consistent across app + Worker.
- **No secret leakage:** OneSignal REST key never in app; only App ID + relay URL/token in `.env`.
```
