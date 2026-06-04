# Push relay (Cloudflare Worker)

A tiny, free Cloudflare Worker that holds the OneSignal **REST API key** and
turns app requests into tag-filtered OneSignal pushes. The app's
`HttpPushSender` POSTs `{companyId, recipientRoles, title, body}` here; the
Worker sends one push per role, filtered by the device's `company_id` + `role`
tags.

This directory is **not** part of the Flutter build — it deploys separately to
Cloudflare's free Workers tier (100k requests/day). The OneSignal REST key lives
**only** here, never in the app.

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

## Request contract

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
