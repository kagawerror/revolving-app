# Relay (Cloudflare Worker)

A tiny, free Cloudflare Worker with two routes:

- `POST /` — **push relay**: holds the OneSignal **REST API key** and turns app
  requests into tag-filtered OneSignal pushes. The app's `HttpPushSender` POSTs
  `{companyId, recipientRoles, title, body}` here; the Worker sends one push per
  role, filtered by the device's `company_id` + `role` tags.
- `POST /admin/set-password` — **admin set-password**: a security-critical
  trusted backend that verifies a Firebase admin's ID token, re-checks the
  caller's `admin` role server-side, then uses a Firebase **service account** to
  set an arbitrary user's password via the Identity Toolkit. See
  [Admin set-password endpoint](#admin-set-password-endpoint).

This directory is **not** part of the Flutter build — it deploys separately to
Cloudflare's free Workers tier (100k requests/day). The OneSignal REST key and
the Firebase service-account key live **only** here, never in the app.

## Develop / test

```sh
npm install
npm test          # vitest unit tests (pure logic: JWT claims, parsers, mappers)
npm run typecheck # tsc --noEmit
```

## Prerequisites

- A free [Cloudflare](https://dash.cloudflare.com/sign-up) account.
- A free [OneSignal](https://onesignal.com) app with the **App ID** and
  **REST API Key** (see the repo's `SETUP.md` push section).
- Node + the Wrangler CLI:

  ```sh
  npm i -g wrangler
  wrangler login
  ```

## Configure secrets

From this `relay/` directory, set the Worker secrets (you'll be prompted to
paste each value):

```sh
wrangler secret put ONESIGNAL_APP_ID
wrangler secret put ONESIGNAL_REST_KEY
wrangler secret put RELAY_TOKEN        # optional shared token; if set, the app must send it as x-relay-token
```

`RELAY_TOKEN` is optional. If you set it, the Worker rejects any request whose
`x-relay-token` header doesn't match — set the same value as `PUSH_RELAY_TOKEN`
in the app's `.env`.

## Deploy

```sh
wrangler deploy
```

Wrangler prints the Worker URL (e.g.
`https://rev-app-push-relay.<subdomain>.workers.dev`). Copy it into the app's
`.env`:

```
PUSH_RELAY_URL=https://rev-app-push-relay.<subdomain>.workers.dev
PUSH_RELAY_TOKEN=<the RELAY_TOKEN you set, if any>
```

Then run the app with `--dart-define-from-file=.env`.

## Push request contract

`POST /` with JSON body:

```json
{
  "companyId": "abc123",
  "recipientRoles": ["incharge"],
  "title": "Fund X is low",
  "body": "A fund has reached its low-balance threshold. Replenish soon."
}
```

- `405` if not POST.
- `401` if `RELAY_TOKEN` is configured and the `x-relay-token` header doesn't match.
- `400` on bad JSON or missing `companyId` / empty `recipientRoles`.
- `200` with `{ "sent": <ok-count>, "roles": <role-count> }` otherwise.

---

## Admin set-password endpoint

`POST /admin/set-password` lets a signed-in **admin** reset another user's
password without knowing the old one. It is the trusted half of the Flutter
`HttpAdminPasswordRepository`. The flow is:

1. **Verify** the caller's Firebase **ID token** (RS256, against Google's public
   JWKS). Bad/expired/forged token → `401`.
2. **Authorize**: re-read `users/{callerUid}.role` from Firestore *server-side*
   using the service account. If it isn't `"admin"` → `403`. The client's claim
   is never trusted.
3. **Set the password** via the Identity Toolkit `accounts:update` admin call
   using a short-lived service-account OAuth2 access token.

### Why a dedicated service account

This Worker can set **any** user's password, so the service account is a
high-value secret. Create a **dedicated** SA used only by this relay, scoped to
exactly two roles:

- **Firebase Authentication Admin** (`roles/firebaseauth.admin`) — to call
  Identity Toolkit `accounts:update`.
- **Cloud Datastore User** (`roles/datastore.user`) — to read the caller's
  `users/{uid}` doc for the role re-check.

Do not reuse a broad/owner service account.

### Get the service-account key

Firebase console → **Project settings** → **Service accounts** →
**Generate new private key**. This downloads a JSON file containing
`project_id`, `client_email`, and `private_key`.

> **The SA JSON is NEVER committed.** `relay/.gitignore` and the repo-root
> `.gitignore` both ignore `service-account*.json`. Keep it out of the repo and
> off shared drives. If it ever leaks, rotate immediately (see
> [Rotating the key](#rotating-the-key)).

### Configure the three secrets

From this `relay/` directory, paste each value from the SA JSON when prompted:

```sh
wrangler secret put FB_PROJECT_ID     # JSON "project_id"
wrangler secret put FB_CLIENT_EMAIL   # JSON "client_email"
wrangler secret put FB_PRIVATE_KEY    # JSON "private_key" — paste the WHOLE PEM
```

`FB_PRIVATE_KEY` is a multi-line PEM. **Keep its newlines.** Two safe options:

- Paste the value exactly as it appears in the JSON, including the literal `\n`
  escape sequences — the Worker normalizes `\n` → real newlines before importing
  the key.
- Or paste the real multi-line PEM (`-----BEGIN PRIVATE KEY-----` … `-----END
  PRIVATE KEY-----`). Either form works.

These secrets are in addition to the push secrets (`ONESIGNAL_APP_ID`,
`ONESIGNAL_REST_KEY`, optional `RELAY_TOKEN`). Deploy as usual with
`wrangler deploy`.

### Endpoint contract

Request:

```
POST /admin/set-password
Authorization: Bearer <admin Firebase ID token>
Content-Type: application/json

{ "uid": "<targetUid>", "newPassword": "<plaintext, >= 6 chars>" }
```

| Status | Body                      | When                                                        |
| ------ | ------------------------- | ----------------------------------------------------------- |
| `200`  | `{"ok":true}`             | Password set. **Only 200 is success** for the client.       |
| `400`  | `{"error":"bad_input"}`   | Invalid JSON, missing/empty `uid`, `newPassword` < 6, weak/invalid password upstream. |
| `401`  | `{"error":"unauthorized"}`| Missing/malformed/invalid/expired ID token.                 |
| `403`  | `{"error":"forbidden"}`   | Caller verified but `users/{callerUid}.role != "admin"`.    |
| `404`  | `{"error":"not_found"}`   | Target `uid` not found (Identity Toolkit `USER_NOT_FOUND`). |
| `405`  | `Method not allowed`      | Method is not POST.                                         |
| `500`  | `{"error":"server_error"}`| Service-account / OAuth / upstream failure or misconfig.    |

### curl smoke test

You need a **real admin ID token**. Easiest source: sign in as an admin in the
app and grab the token, or use the Firebase Auth REST
`accounts:signInWithPassword` endpoint with your web API key:

```sh
ADMIN_TOKEN=$(curl -s \
  "https://identitytoolkit.googleapis.com/v1/accounts:signInWithPassword?key=$WEB_API_KEY" \
  -H 'content-type: application/json' \
  -d '{"email":"admin@example.com","password":"<admin-pw>","returnSecureToken":true}' \
  | python3 -c 'import sys,json;print(json.load(sys.stdin)["idToken"])')

# Success — expect HTTP 200 {"ok":true}
curl -i -X POST "$RELAY_URL/admin/set-password" \
  -H "authorization: Bearer $ADMIN_TOKEN" \
  -H 'content-type: application/json' \
  -d '{"uid":"<targetUid>","newPassword":"newpass123"}'

# Bad input — expect 400 {"error":"bad_input"}
curl -i -X POST "$RELAY_URL/admin/set-password" \
  -H "authorization: Bearer $ADMIN_TOKEN" \
  -H 'content-type: application/json' \
  -d '{"uid":"<targetUid>","newPassword":"12345"}'

# No token — expect 401 {"error":"unauthorized"}
curl -i -X POST "$RELAY_URL/admin/set-password" \
  -H 'content-type: application/json' \
  -d '{"uid":"x","newPassword":"newpass123"}'

# Non-admin token — expect 403 {"error":"forbidden"}
# (repeat the success call with a non-admin user's ID token)

# Unknown target — expect 404 {"error":"not_found"}
curl -i -X POST "$RELAY_URL/admin/set-password" \
  -H "authorization: Bearer $ADMIN_TOKEN" \
  -H 'content-type: application/json' \
  -d '{"uid":"does-not-exist","newPassword":"newpass123"}'
```

### Security notes

- The Worker **never logs** the new password, the request body, the bearer
  token, or the SA private key. Only short error codes and (at most) the
  caller/target uid may be logged.
- Admin enforcement is two independent checks: ID-token **signature** + claims,
  *and* a server-side **Firestore role re-read**. Neither is skipped.
- `RELAY_TOKEN` (`x-relay-token`) remains an optional cheap pre-filter for the
  **push** route; it is **not** the security boundary for the admin route — the
  ID-token verification is.
- **CORS / web TODO:** this route emits **no** `Access-Control-Allow-Origin`.
  Mobile clients don't enforce CORS, so this is fine for the Flutter app. If you
  ever call this route from a browser, do **not** add `*`; lock the
  `Access-Control-Allow-Origin` down to your exact trusted web origin and add an
  explicit `OPTIONS` preflight handler before exposing it to the web.

### Rotating the key

If the SA JSON leaks (or on a routine schedule):

1. Firebase console → Project settings → Service accounts → generate a **new**
   private key for the dedicated SA.
2. Re-run `wrangler secret put FB_CLIENT_EMAIL` and `FB_PRIVATE_KEY` (and
   `FB_PROJECT_ID` if it changed), then `wrangler deploy`.
3. In Google Cloud IAM, **delete/disable the old key** for that SA so the leaked
   credential can no longer mint tokens.
