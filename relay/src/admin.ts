// Admin set-password endpoint logic for the Cloudflare Worker relay.
//
// SECURITY-CRITICAL trusted backend. Verifies a caller's Firebase ID token
// (RS256 via WebCrypto), re-checks server-side that the caller is an `admin`
// (Firestore `users/{uid}.role`), then uses a Firebase service account
// (OAuth2 -> Identity Toolkit) to set an arbitrary user's password.
//
// NEVER log the new password, the request body, any token, or the SA key.
// Only short codes/messages (and optionally caller/target uid) may be logged.

export interface AdminEnv {
  FB_PROJECT_ID: string;
  FB_CLIENT_EMAIL: string;
  FB_PRIVATE_KEY: string;
}

// ---------------------------------------------------------------------------
// base64url helpers
// ---------------------------------------------------------------------------

/**
 * Copy bytes into a fresh `ArrayBuffer`-backed view. WebCrypto's typed APIs
 * require `BufferSource` over a plain `ArrayBuffer` (not `SharedArrayBuffer`),
 * so we normalize here before every `crypto.subtle` call.
 */
export function asArrayBufferView(bytes: Uint8Array): Uint8Array<ArrayBuffer> {
  const copy = new Uint8Array(new ArrayBuffer(bytes.byteLength));
  copy.set(bytes);
  return copy as Uint8Array<ArrayBuffer>;
}

/** Decode a base64url string to bytes. Throws on malformed input. */
export function base64urlToBytes(input: string): Uint8Array {
  // Reject obviously-malformed input early.
  if (typeof input !== 'string' || input.length === 0) {
    throw new Error('empty base64url');
  }
  let b64 = input.replace(/-/g, '+').replace(/_/g, '/');
  const pad = b64.length % 4;
  if (pad === 1) throw new Error('bad base64url length');
  if (pad) b64 += '='.repeat(4 - pad);
  const bin = atob(b64);
  const bytes = new Uint8Array(bin.length);
  for (let i = 0; i < bin.length; i++) bytes[i] = bin.charCodeAt(i);
  return bytes;
}

/** Decode a base64url string to a UTF-8 string. */
export function base64urlToString(input: string): string {
  return new TextDecoder().decode(base64urlToBytes(input));
}

/** Encode bytes (or a string) as base64url with no padding. */
export function bytesToBase64url(input: Uint8Array | string): string {
  const bytes =
    typeof input === 'string' ? new TextEncoder().encode(input) : input;
  let bin = '';
  for (let i = 0; i < bytes.length; i++) bin += String.fromCharCode(bytes[i]);
  return btoa(bin).replace(/\+/g, '-').replace(/\//g, '_').replace(/=+$/, '');
}

// ---------------------------------------------------------------------------
// ID-token claim validation (pure)
// ---------------------------------------------------------------------------

export interface IdTokenClaims {
  aud?: unknown;
  iss?: unknown;
  exp?: unknown;
  iat?: unknown;
  sub?: unknown;
  [k: string]: unknown;
}

const CLOCK_SKEW_SECONDS = 60;

/**
 * Validate the standard Firebase ID-token claims against the expected project.
 * Returns the caller uid (`sub`) when valid, otherwise `null`. Pure: `now` is
 * injected (seconds since epoch) for deterministic testing. Signature
 * verification is performed separately (this only checks the claim values).
 */
export function validateIdTokenClaims(
  claims: IdTokenClaims,
  projectId: string,
  now: number,
): string | null {
  if (!projectId) return null;
  if (claims.aud !== projectId) return null;
  if (claims.iss !== `https://securetoken.google.com/${projectId}`) return null;

  const exp = claims.exp;
  const iat = claims.iat;
  if (typeof exp !== 'number' || typeof iat !== 'number') return null;
  // exp must be in the future (allow +skew so a just-expired token is rejected).
  if (exp <= now - CLOCK_SKEW_SECONDS) return null;
  // iat must not be unreasonably in the future.
  if (iat > now + CLOCK_SKEW_SECONDS) return null;

  const sub = claims.sub;
  if (typeof sub !== 'string' || sub.length === 0) return null;
  return sub;
}

// ---------------------------------------------------------------------------
// Firestore role parser (pure)
// ---------------------------------------------------------------------------

/**
 * Parse the `role` string from a Firestore REST `users/{uid}` document.
 * Returns the role string, or `null` if the doc/field is missing/malformed.
 */
export function parseFirestoreRole(doc: unknown): string | null {
  if (!doc || typeof doc !== 'object') return null;
  const fields = (doc as Record<string, unknown>).fields;
  if (!fields || typeof fields !== 'object') return null;
  const role = (fields as Record<string, unknown>).role;
  if (!role || typeof role !== 'object') return null;
  const sv = (role as Record<string, unknown>).stringValue;
  return typeof sv === 'string' ? sv : null;
}

// ---------------------------------------------------------------------------
// Identity Toolkit upstream-error -> status mapping (pure)
// ---------------------------------------------------------------------------

export type SetPasswordOutcome =
  | { status: 200 }
  | { status: 400 }
  | { status: 404 }
  | { status: 500 };

/**
 * Map an Identity Toolkit `accounts:update` response to our HTTP outcome.
 * `httpOk` is the upstream response's `ok`; `errorBody` is its raw text.
 */
export function mapIdentityToolkitResult(
  httpOk: boolean,
  errorBody: string,
): SetPasswordOutcome {
  if (httpOk) return { status: 200 };
  const body = errorBody || '';
  if (body.includes('USER_NOT_FOUND')) return { status: 404 };
  // 400 only for genuine password-input errors. Other `INVALID_*` codes
  // (e.g. INVALID_ID_TOKEN / INVALID_GRANT from a misconfigured service
  // account) are server-side faults and must surface as 500, not be
  // misreported to the admin as a weak/invalid password.
  if (body.includes('WEAK_PASSWORD') || body.includes('INVALID_PASSWORD')) {
    return { status: 400 };
  }
  return { status: 500 };
}

// ---------------------------------------------------------------------------
// Input validation (pure)
// ---------------------------------------------------------------------------

export const MIN_PASSWORD_LENGTH = 6;

export interface SetPasswordInput {
  uid: string;
  newPassword: string;
}

/** Validate the request body. Returns the typed input or `null` (=> 400). */
export function parseSetPasswordInput(raw: unknown): SetPasswordInput | null {
  if (!raw || typeof raw !== 'object') return null;
  const uid = (raw as Record<string, unknown>).uid;
  const newPassword = (raw as Record<string, unknown>).newPassword;
  if (typeof uid !== 'string' || uid.length === 0) return null;
  if (typeof newPassword !== 'string' || newPassword.length < MIN_PASSWORD_LENGTH) {
    return null;
  }
  return { uid, newPassword };
}

// ---------------------------------------------------------------------------
// JSON response helpers
// ---------------------------------------------------------------------------

function json(status: number, body: Record<string, unknown>): Response {
  return new Response(JSON.stringify(body), {
    status,
    headers: { 'content-type': 'application/json' },
  });
}

const errResp = (status: number, code: string) => json(status, { error: code });

// ---------------------------------------------------------------------------
// JWKS fetch + cache (Google secure-token public keys)
// ---------------------------------------------------------------------------

const JWKS_URL =
  'https://www.googleapis.com/service_accounts/v1/jwks/securetoken@system.gserviceaccount.com';

interface JwksCache {
  keys: Record<string, CryptoKey>; // keyed by `kid`
  expiresAt: number; // ms epoch
}

let jwksCache: JwksCache | null = null;

interface Jwk {
  kid?: string;
  [k: string]: unknown;
}

/** Parse a `Cache-Control: max-age=N` header into seconds (default fallback). */
export function parseMaxAge(cacheControl: string | null, fallback: number): number {
  if (!cacheControl) return fallback;
  const m = /max-age\s*=\s*(\d+)/i.exec(cacheControl);
  if (!m) return fallback;
  const n = parseInt(m[1], 10);
  return Number.isFinite(n) && n > 0 ? n : fallback;
}

async function getVerifyKey(kid: string): Promise<CryptoKey | null> {
  const now = Date.now();
  if (jwksCache && jwksCache.expiresAt > now && jwksCache.keys[kid]) {
    return jwksCache.keys[kid];
  }

  const resp = await fetch(JWKS_URL);
  if (!resp.ok) {
    // Stale cache is better than nothing if Google is briefly unreachable.
    return jwksCache?.keys[kid] ?? null;
  }
  const maxAge = parseMaxAge(resp.headers.get('cache-control'), 3600);
  const body = (await resp.json()) as { keys?: Jwk[] };
  const keys: Record<string, CryptoKey> = {};
  for (const jwk of body.keys ?? []) {
    if (!jwk.kid) continue;
    try {
      keys[jwk.kid] = await crypto.subtle.importKey(
        'jwk',
        jwk as JsonWebKey,
        { name: 'RSASSA-PKCS1-v1_5', hash: 'SHA-256' },
        false,
        ['verify'],
      );
    } catch {
      // Skip a single malformed key rather than failing the whole set.
    }
  }
  jwksCache = { keys, expiresAt: now + maxAge * 1000 };
  return keys[kid] ?? null;
}

// ---------------------------------------------------------------------------
// ID-token verification (signature + claims)
// ---------------------------------------------------------------------------

interface JwtParts {
  header: { alg?: string; kid?: string; typ?: string };
  payload: IdTokenClaims;
  signingInput: Uint8Array;
  signature: Uint8Array;
}

/** Split a compact JWS into its parts. Returns `null` if malformed. */
export function splitJwt(jwt: string): JwtParts | null {
  const segments = jwt.split('.');
  if (segments.length !== 3) return null;
  const [h, p, s] = segments;
  try {
    const header = JSON.parse(base64urlToString(h));
    const payload = JSON.parse(base64urlToString(p)) as IdTokenClaims;
    const signature = base64urlToBytes(s);
    const signingInput = new TextEncoder().encode(`${h}.${p}`);
    return { header, payload, signingInput, signature };
  } catch {
    return null;
  }
}

/**
 * Signature of the ID-token verifier used by {@link handleSetPassword}. The
 * production implementation is {@link verifyIdToken}; tests may inject a fake
 * to exercise the *downstream* authorization gates without forging a real
 * RS256 signature. The injected verifier MUST NOT weaken the real check used
 * in production — it is wired in only via an explicit test-only parameter.
 */
export type IdTokenVerifier = (
  jwt: string,
  projectId: string,
  now: number,
) => Promise<string | null>;

/**
 * Fully verify a Firebase ID token: signature against Google's JWKS + claims.
 * Returns the caller uid on success, `null` on any failure. No logging of the
 * token here.
 */
export async function verifyIdToken(
  jwt: string,
  projectId: string,
  now: number,
): Promise<string | null> {
  const parts = splitJwt(jwt);
  if (!parts) return null;
  if (parts.header.alg !== 'RS256') return null;
  if (!parts.header.kid) return null;

  const key = await getVerifyKey(parts.header.kid);
  if (!key) return null;

  const valid = await crypto.subtle.verify(
    { name: 'RSASSA-PKCS1-v1_5' },
    key,
    asArrayBufferView(parts.signature),
    asArrayBufferView(parts.signingInput),
  );
  if (!valid) return null;

  return validateIdTokenClaims(parts.payload, projectId, now);
}

// ---------------------------------------------------------------------------
// Service-account OAuth2 access token (mint + cache)
// ---------------------------------------------------------------------------

interface SaTokenCache {
  token: string;
  expiresAt: number; // ms epoch, already padded ~5min early
}

let saTokenCache: SaTokenCache | null = null;

/** Convert a PKCS8 PEM private key to a DER byte array. */
export function pkcs8PemToDer(pem: string): Uint8Array {
  const normalized = pem.replace(/\\n/g, '\n');
  const b64 = normalized
    .replace(/-----BEGIN PRIVATE KEY-----/g, '')
    .replace(/-----END PRIVATE KEY-----/g, '')
    .replace(/\s+/g, '');
  // Standard base64 (not url) for PEM bodies.
  const bin = atob(b64);
  const der = new Uint8Array(bin.length);
  for (let i = 0; i < bin.length; i++) der[i] = bin.charCodeAt(i);
  return der;
}

async function importSaKey(env: AdminEnv): Promise<CryptoKey> {
  const der = pkcs8PemToDer(env.FB_PRIVATE_KEY);
  return crypto.subtle.importKey(
    'pkcs8',
    asArrayBufferView(der),
    { name: 'RSASSA-PKCS1-v1_5', hash: 'SHA-256' },
    false,
    ['sign'],
  );
}

/**
 * Signature of the SA access-token minter used by {@link handleSetPassword}.
 * Production uses {@link mintSaAccessToken} (real RS256-signed JWT-bearer OAuth
 * exchange). Tests inject a fake to avoid importing a real PKCS8 key, while
 * still exercising the downstream Firestore role gate and the upstream
 * `accounts:update` ordering.
 */
export type SaTokenMinter = (env: AdminEnv) => Promise<string | null>;

async function mintSaAccessToken(env: AdminEnv): Promise<string | null> {
  const now = Math.floor(Date.now() / 1000);
  if (saTokenCache && saTokenCache.expiresAt > Date.now()) {
    return saTokenCache.token;
  }

  try {
    const header = { alg: 'RS256', typ: 'JWT' };
    const claims = {
      iss: env.FB_CLIENT_EMAIL,
      sub: env.FB_CLIENT_EMAIL,
      aud: 'https://oauth2.googleapis.com/token',
      scope:
        'https://www.googleapis.com/auth/identitytoolkit https://www.googleapis.com/auth/datastore',
      iat: now,
      exp: now + 3600,
    };
    const signingInput = `${bytesToBase64url(JSON.stringify(header))}.${bytesToBase64url(
      JSON.stringify(claims),
    )}`;
    const key = await importSaKey(env);
    const sig = new Uint8Array(
      await crypto.subtle.sign(
        { name: 'RSASSA-PKCS1-v1_5' },
        key,
        asArrayBufferView(new TextEncoder().encode(signingInput)),
      ),
    );
    const assertion = `${signingInput}.${bytesToBase64url(sig)}`;

    const resp = await fetch('https://oauth2.googleapis.com/token', {
      method: 'POST',
      headers: { 'content-type': 'application/x-www-form-urlencoded' },
      body: new URLSearchParams({
        grant_type: 'urn:ietf:params:oauth:grant-type:jwt-bearer',
        assertion,
      }).toString(),
    });
    if (!resp.ok) {
      console.error('sa_oauth_failed', resp.status);
      return null;
    }
    const body = (await resp.json()) as {
      access_token?: string;
      expires_in?: number;
    };
    if (!body.access_token) {
      console.error('sa_oauth_no_token');
      return null;
    }
    const ttl = typeof body.expires_in === 'number' ? body.expires_in : 3600;
    // Refresh ~5 min before actual expiry.
    saTokenCache = {
      token: body.access_token,
      expiresAt: Date.now() + Math.max(ttl - 300, 60) * 1000,
    };
    return body.access_token;
  } catch (e) {
    console.error('sa_oauth_exception', (e as Error)?.name ?? 'error');
    return null;
  }
}

// ---------------------------------------------------------------------------
// Firestore role re-read (server-side authorization)
// ---------------------------------------------------------------------------

async function fetchCallerRole(
  env: AdminEnv,
  accessToken: string,
  callerUid: string,
): Promise<string | null> {
  const url = `https://firestore.googleapis.com/v1/projects/${env.FB_PROJECT_ID}/databases/(default)/documents/users/${encodeURIComponent(
    callerUid,
  )}`;
  const resp = await fetch(url, {
    headers: { Authorization: `Bearer ${accessToken}` },
  });
  if (!resp.ok) return null; // missing doc (404) or any error -> not authorized
  const doc = await resp.json();
  return parseFirestoreRole(doc);
}

// ---------------------------------------------------------------------------
// Identity Toolkit: set password
// ---------------------------------------------------------------------------

async function setPasswordUpstream(
  accessToken: string,
  targetUid: string,
  newPassword: string,
): Promise<SetPasswordOutcome> {
  const resp = await fetch(
    'https://identitytoolkit.googleapis.com/v1/accounts:update',
    {
      method: 'POST',
      headers: {
        Authorization: `Bearer ${accessToken}`,
        'content-type': 'application/json',
      },
      // SECURITY: this body carries the plaintext password — never logged.
      body: JSON.stringify({ localId: targetUid, password: newPassword }),
    },
  );
  if (resp.ok) return { status: 200 };
  const text = await resp.text(); // error code only; not logged verbatim
  return mapIdentityToolkitResult(false, text);
}

// ---------------------------------------------------------------------------
// Route handler
// ---------------------------------------------------------------------------

/**
 * Handle `POST /admin/set-password`. The router has already matched the path.
 * Method enforcement (405) is handled here too for safety.
 *
 * `verify` and `mintToken` default to the real {@link verifyIdToken} (full
 * RS256 + claim verification) and {@link mintSaAccessToken}. They are
 * injectable seams used ONLY by unit tests to drive the downstream gates
 * (admin re-check, upstream call ordering) without forging an RS256 signature
 * or importing a real PKCS8 key. Production callers (see `index.ts`) pass two
 * args and therefore always get the real implementations. This does not weaken
 * production verification.
 */
export async function handleSetPassword(
  req: Request,
  env: AdminEnv,
  verify: IdTokenVerifier = verifyIdToken,
  mintToken: SaTokenMinter = mintSaAccessToken,
): Promise<Response> {
  if (req.method !== 'POST') {
    return new Response('Method not allowed', { status: 405 });
  }

  // --- Step 1: verify the caller's Firebase ID token ---------------------
  const authHeader = req.headers.get('authorization') ?? '';
  const m = /^Bearer\s+(.+)$/i.exec(authHeader);
  if (!m) return errResp(401, 'unauthorized');
  const idToken = m[1].trim();

  if (!env.FB_PROJECT_ID || !env.FB_CLIENT_EMAIL || !env.FB_PRIVATE_KEY) {
    console.error('admin_misconfigured');
    return errResp(500, 'server_error');
  }

  let callerUid: string | null;
  try {
    callerUid = await verify(
      idToken,
      env.FB_PROJECT_ID,
      Math.floor(Date.now() / 1000),
    );
  } catch (e) {
    console.error('idtoken_verify_exception', (e as Error)?.name ?? 'error');
    return errResp(401, 'unauthorized');
  }
  if (!callerUid) return errResp(401, 'unauthorized');

  // --- Step 5: validate input (before any upstream call) -----------------
  let parsed: SetPasswordInput | null;
  try {
    const raw = await req.json();
    parsed = parseSetPasswordInput(raw);
  } catch {
    return errResp(400, 'bad_input');
  }
  if (!parsed) return errResp(400, 'bad_input');

  // --- Step 3: mint a service-account access token -----------------------
  const accessToken = await mintToken(env);
  if (!accessToken) return errResp(500, 'server_error');

  // --- Step 2: re-check the caller's role server-side --------------------
  let role: string | null;
  try {
    role = await fetchCallerRole(env, accessToken, callerUid);
  } catch (e) {
    console.error('role_read_exception', (e as Error)?.name ?? 'error');
    return errResp(500, 'server_error');
  }
  if (role !== 'admin') {
    console.error('forbidden_non_admin', callerUid);
    return errResp(403, 'forbidden');
  }

  // --- Step 4: set the password ------------------------------------------
  let outcome: SetPasswordOutcome;
  try {
    outcome = await setPasswordUpstream(
      accessToken,
      parsed.uid,
      parsed.newPassword,
    );
  } catch (e) {
    console.error('set_password_exception', (e as Error)?.name ?? 'error');
    return errResp(500, 'server_error');
  }

  switch (outcome.status) {
    case 200:
      return json(200, { ok: true });
    case 400:
      return errResp(400, 'bad_input');
    case 404:
      return errResp(404, 'not_found');
    default:
      console.error('set_password_upstream_failed', callerUid, parsed.uid);
      return errResp(500, 'server_error');
  }
}
