# Electronic Signature — Cloudinary Setup

How the recipient e-signature (captured at cash release) is stored, and **exactly what you
provide**. Two phases: Phase 1 ships in this PR (unsigned, same posture as proof photos);
Phase 2 upgrades to true authenticated/signed delivery via the Cloudflare Worker relay.

> **Security rule that drives all of this:** the Flutter app must **never** hold the Cloudinary
> **API secret** — it would be extractable from the shipped binary. Unsigned uploads need no
> secret (safe in-app). *Authenticated* uploads + signed view URLs **do** need the secret, so
> that work happens only in the Worker relay (`relay/`), never in the app.

---

## Phase 1 — Unsigned (ready in this PR)

Signatures upload directly from the app with an **unsigned** preset, into their **own folder**
(kept separate from regular proof photos because a signature is biometric-adjacent PII). Access
is controlled exactly like every proof photo today: the URL only ever lives inside a
`companyId`-scoped Firestore request document, and Firestore rules let only same-company users
read that doc.

### What you provide — Cloudinary dashboard
1. **Cloud name** — already set (`CLOUDINARY_CLOUD_NAME`). No change.
2. **Signature folder** — no dashboard action needed; Cloudinary creates
   `rev_app/signatures` on first upload. (Override with `CLOUDINARY_SIGNATURE_FOLDER`.)
3. *(Optional)* **A separate unsigned preset for signatures** — Settings → Upload →
   *Upload presets* → **Add** → Signing mode **Unsigned**. If you want, enable
   *Strip metadata* and lock *Allowed formats* to `png`. Copy its name into
   `CLOUDINARY_SIGNATURE_PRESET`. **Leave blank to reuse `CLOUDINARY_UPLOAD_PRESET`.**

### What you provide — `.env` (already scaffolded)
```env
CLOUDINARY_SIGNATURE_FOLDER=rev_app/signatures   # default is fine
CLOUDINARY_SIGNATURE_PRESET=                      # blank = reuse the proof preset
SIGNATURE_RELAY_URL=                              # leave blank in Phase 1
```
That's all for Phase 1. Run the app as usual: `flutter run --dart-define-from-file=.env`.

---

## Phase 2 — Authenticated / signed (deferred upgrade)

Goal: store each signature as a Cloudinary **`authenticated`** asset (not publicly fetchable even
if the URL leaks) and serve it only through **time-limited signed URLs**. Because both steps need
the API secret, they run in the **Worker relay**. When you set `SIGNATURE_RELAY_URL`, the app
stops uploading signatures directly and instead calls the Worker; everything else (the model
field, the immutable rule, the UI tile) is unchanged.

```
App ──signature PNG──▶  Worker /signature/upload  ──signed authenticated upload──▶ Cloudinary
App ──asset id──────▶  Worker /signature/view-url ──signed delivery URL (TTL)────▶ App shows it
```

### What you provide — Cloudinary
1. **API Key** + **API Secret** — Dashboard → *Settings → Access Keys*. These go into the
   **Worker** as secrets (next section). **Never** put the secret in `.env` or the app.
2. *(Recommended)* An **authenticated** upload preset — Settings → Upload → *Upload presets* →
   **Add** → Signing mode **Signed**, **Delivery type `authenticated`**, folder
   `rev_app/signatures`, *Strip metadata* on, *Allowed formats* `png`. Note its name.

### What you provide — Cloudflare Worker (`relay/`)
The relay already holds server-only secrets (OneSignal key, Firebase service account); the
Cloudinary secret joins them the same way. From `relay/`:
```sh
wrangler secret put CLOUDINARY_API_KEY
wrangler secret put CLOUDINARY_API_SECRET
wrangler secret put CLOUDINARY_CLOUD_NAME     # or hard-code in wrangler.toml [vars]
# optional, if you made the preset above:
wrangler secret put CLOUDINARY_SIGNATURE_PRESET
```
Then add two routes to the Worker (engineering task, tracked separately — the relay is its own
deploy, not part of the Flutter build):
- `POST /signature/upload` — verifies the caller's Firebase ID token + `incharge`/`admin` role,
  signs an `authenticated` upload to `rev_app/signatures`, returns the `public_id`.
- `POST /signature/view-url` — verifies the token + same-company scope, returns a short-TTL
  signed delivery URL for a given `public_id`.

Deploy: `wrangler deploy`. Copy the Worker URL.

### What you provide — `.env` (Phase 2 switch-on)
```env
SIGNATURE_RELAY_URL=https://<your-worker>.workers.dev    # flips the app to authenticated mode
```
With this set, the app routes signature upload + display through the relay automatically. No app
rebuild logic changes beyond the env value.

---

## Quick checklist (what you supply)

| Item | Phase | Where it goes | Who holds the secret |
|---|---|---|---|
| Cloud name | 1 | `.env` `CLOUDINARY_CLOUD_NAME` | public, safe in app |
| Signature folder | 1 | `.env` `CLOUDINARY_SIGNATURE_FOLDER` (default ok) | n/a |
| Unsigned signature preset *(opt.)* | 1 | `.env` `CLOUDINARY_SIGNATURE_PRESET` | public, safe in app |
| Cloudinary **API key + secret** | 2 | `wrangler secret put …` in `relay/` | **Worker only** |
| Authenticated preset *(opt.)* | 2 | Worker var/secret | Worker only |
| Worker URL | 2 | `.env` `SIGNATURE_RELAY_URL` | public URL, safe in app |
