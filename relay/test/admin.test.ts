import { describe, it, expect, vi, afterEach } from 'vitest';
import {
  base64urlToBytes,
  base64urlToString,
  bytesToBase64url,
  validateIdTokenClaims,
  parseFirestoreRole,
  mapIdentityToolkitResult,
  parseSetPasswordInput,
  parseMaxAge,
  splitJwt,
  handleSetPassword,
  type AdminEnv,
  type IdTokenVerifier,
  type SaTokenMinter,
} from '../src/admin';

const PROJECT = 'rev-app-demo';
const ISS = `https://securetoken.google.com/${PROJECT}`;
const NOW = 1_700_000_000;

describe('base64url', () => {
  it('round-trips a string', () => {
    const s = 'héllo, wörld! 你好';
    expect(base64urlToString(bytesToBase64url(s))).toBe(s);
  });

  it('decodes unpadded base64url', () => {
    // "foobar" -> base64 "Zm9vYmFy"
    expect(base64urlToString('Zm9vYmFy')).toBe('foobar');
  });

  it('handles url-safe chars and missing padding', () => {
    // bytes 0xfb 0xff -> base64 "+/8=" -> base64url "-_8"
    const bytes = base64urlToBytes('-_8');
    expect(Array.from(bytes)).toEqual([0xfb, 0xff]);
  });

  it('throws on malformed length', () => {
    expect(() => base64urlToBytes('A')).toThrow();
  });

  it('produces no padding in output', () => {
    expect(bytesToBase64url('any')).not.toContain('=');
  });
});

describe('validateIdTokenClaims', () => {
  const good = () => ({
    aud: PROJECT,
    iss: ISS,
    exp: NOW + 3600,
    iat: NOW - 10,
    sub: 'caller-uid-123',
  });

  it('accepts a valid token and returns sub', () => {
    expect(validateIdTokenClaims(good(), PROJECT, NOW)).toBe('caller-uid-123');
  });

  it('rejects wrong aud', () => {
    expect(validateIdTokenClaims({ ...good(), aud: 'other' }, PROJECT, NOW)).toBeNull();
  });

  it('rejects wrong iss', () => {
    expect(
      validateIdTokenClaims({ ...good(), iss: 'https://evil/' }, PROJECT, NOW),
    ).toBeNull();
  });

  it('rejects expired token (beyond skew)', () => {
    expect(validateIdTokenClaims({ ...good(), exp: NOW - 120 }, PROJECT, NOW)).toBeNull();
  });

  it('allows a just-expired token within +/-60s skew', () => {
    expect(validateIdTokenClaims({ ...good(), exp: NOW - 30 }, PROJECT, NOW)).toBe(
      'caller-uid-123',
    );
  });

  it('rejects iat too far in the future', () => {
    expect(validateIdTokenClaims({ ...good(), iat: NOW + 120 }, PROJECT, NOW)).toBeNull();
  });

  it('rejects empty sub', () => {
    expect(validateIdTokenClaims({ ...good(), sub: '' }, PROJECT, NOW)).toBeNull();
  });

  it('rejects non-numeric exp/iat', () => {
    expect(
      validateIdTokenClaims({ ...good(), exp: 'soon' as unknown as number }, PROJECT, NOW),
    ).toBeNull();
  });

  it('rejects empty projectId', () => {
    expect(validateIdTokenClaims(good(), '', NOW)).toBeNull();
  });
});

describe('parseFirestoreRole', () => {
  it('extracts an admin role', () => {
    const doc = { fields: { role: { stringValue: 'admin' } } };
    expect(parseFirestoreRole(doc)).toBe('admin');
  });

  it('returns non-admin role verbatim', () => {
    expect(parseFirestoreRole({ fields: { role: { stringValue: 'incharge' } } })).toBe(
      'incharge',
    );
  });

  it('returns null when fields missing', () => {
    expect(parseFirestoreRole({})).toBeNull();
  });

  it('returns null when role field missing', () => {
    expect(parseFirestoreRole({ fields: { name: { stringValue: 'x' } } })).toBeNull();
  });

  it('returns null on non-object input', () => {
    expect(parseFirestoreRole(null)).toBeNull();
    expect(parseFirestoreRole('admin')).toBeNull();
  });

  it('returns null when stringValue is wrong type', () => {
    expect(parseFirestoreRole({ fields: { role: { integerValue: 1 } } })).toBeNull();
  });
});

describe('mapIdentityToolkitResult', () => {
  it('maps ok -> 200', () => {
    expect(mapIdentityToolkitResult(true, '')).toEqual({ status: 200 });
  });

  it('maps USER_NOT_FOUND -> 404', () => {
    expect(
      mapIdentityToolkitResult(false, '{"error":{"message":"USER_NOT_FOUND"}}').status,
    ).toBe(404);
  });

  it('maps WEAK_PASSWORD -> 400', () => {
    expect(
      mapIdentityToolkitResult(false, '{"error":{"message":"WEAK_PASSWORD : ..."}}').status,
    ).toBe(400);
  });

  it('maps INVALID_PASSWORD -> 400', () => {
    expect(
      mapIdentityToolkitResult(false, '{"error":{"message":"INVALID_PASSWORD"}}').status,
    ).toBe(400);
  });

  it('maps INVALID_ID_TOKEN (misconfigured SA) -> 500, not 400', () => {
    expect(mapIdentityToolkitResult(false, 'INVALID_ID_TOKEN').status).toBe(500);
  });

  it('maps INVALID_GRANT -> 500, not 400', () => {
    expect(mapIdentityToolkitResult(false, 'INVALID_GRANT').status).toBe(500);
  });

  it('maps unknown error -> 500', () => {
    expect(mapIdentityToolkitResult(false, 'SOMETHING_ELSE').status).toBe(500);
  });
});

describe('parseSetPasswordInput', () => {
  it('accepts valid input', () => {
    expect(parseSetPasswordInput({ uid: 'u1', newPassword: 'secret6' })).toEqual({
      uid: 'u1',
      newPassword: 'secret6',
    });
  });

  it('rejects missing uid', () => {
    expect(parseSetPasswordInput({ newPassword: 'secret6' })).toBeNull();
  });

  it('rejects empty uid', () => {
    expect(parseSetPasswordInput({ uid: '', newPassword: 'secret6' })).toBeNull();
  });

  it('rejects short password (< 6)', () => {
    expect(parseSetPasswordInput({ uid: 'u1', newPassword: '12345' })).toBeNull();
  });

  it('accepts exactly 6-char password', () => {
    expect(parseSetPasswordInput({ uid: 'u1', newPassword: '123456' })).not.toBeNull();
  });

  it('rejects non-object / non-string fields', () => {
    expect(parseSetPasswordInput(null)).toBeNull();
    expect(parseSetPasswordInput({ uid: 1, newPassword: 'secret6' })).toBeNull();
    expect(parseSetPasswordInput({ uid: 'u1', newPassword: 123456 })).toBeNull();
  });
});

describe('parseMaxAge', () => {
  it('parses max-age', () => {
    expect(parseMaxAge('public, max-age=21600', 3600)).toBe(21600);
  });

  it('falls back when header missing', () => {
    expect(parseMaxAge(null, 3600)).toBe(3600);
  });

  it('falls back when no max-age directive', () => {
    expect(parseMaxAge('no-cache', 3600)).toBe(3600);
  });
});

describe('splitJwt', () => {
  it('splits a well-formed JWT into header/payload', () => {
    const header = bytesToBase64url(JSON.stringify({ alg: 'RS256', kid: 'k1' }));
    const payload = bytesToBase64url(JSON.stringify({ sub: 'u1' }));
    const sig = bytesToBase64url(new Uint8Array([1, 2, 3]));
    const parts = splitJwt(`${header}.${payload}.${sig}`);
    expect(parts?.header.alg).toBe('RS256');
    expect(parts?.header.kid).toBe('k1');
    expect(parts?.payload.sub).toBe('u1');
  });

  it('returns null when not 3 segments', () => {
    expect(splitJwt('a.b')).toBeNull();
  });

  it('returns null on non-JSON segment', () => {
    expect(splitJwt('!!!.@@@.###')).toBeNull();
  });
});

// ---------------------------------------------------------------------------
// handleSetPassword orchestration — security gate ordering
//
// These tests lock the ordering of the auth gates so that the privileged
// Identity Toolkit `accounts:update` call can NEVER run before the caller has
// been (a) authenticated and (b) confirmed to be an admin via a server-side
// role re-read. They mock global `fetch`, so any call to `accounts:update`
// would be observable; we assert it is absent.
//
// The ID-token verifier and the SA-token minter are injected via
// handleSetPassword's optional 3rd/4th params. Production code (index.ts)
// passes only (req, env) and therefore always uses the REAL RS256 + claim
// verification (`verifyIdToken`) and the REAL JWT-bearer OAuth mint
// (`mintSaAccessToken`). The injection here is strictly a test seam to avoid
// forging an RS256 signature / importing a real PKCS8 key, and does NOT weaken
// production verification.
// ---------------------------------------------------------------------------

describe('handleSetPassword gate ordering', () => {
  const ENV: AdminEnv = {
    FB_PROJECT_ID: PROJECT,
    FB_CLIENT_EMAIL: 'sa@example.iam.gserviceaccount.com',
    FB_PRIVATE_KEY: 'unused-because-the-minter-is-injected-in-tests',
  };

  const ACCOUNTS_UPDATE_URL =
    'https://identitytoolkit.googleapis.com/v1/accounts:update';

  function makeReq(authHeader?: string): Request {
    const headers: Record<string, string> = { 'content-type': 'application/json' };
    if (authHeader !== undefined) headers.authorization = authHeader;
    return new Request('https://relay.example/admin/set-password', {
      method: 'POST',
      headers,
      body: JSON.stringify({ uid: 'target-uid', newPassword: 'secret6' }),
    });
  }

  /**
   * Mock global `fetch`, recording every URL. Serves the Firestore role read
   * with `opts.role`; serves `accounts:update` with 200 (so that if the gate
   * EVER lets it through, the absence-assertion — not a thrown error — is what
   * catches the regression). Any other URL throws.
   */
  function installFetchMock(opts: { role: string }) {
    const urls: string[] = [];
    const mock = vi.fn(async (input: RequestInfo | URL) => {
      const url = typeof input === 'string' ? input : input.toString();
      urls.push(url);

      if (url.includes('/databases/(default)/documents/users/')) {
        return new Response(
          JSON.stringify({ fields: { role: { stringValue: opts.role } } }),
          { status: 200, headers: { 'content-type': 'application/json' } },
        );
      }
      if (url.startsWith(ACCOUNTS_UPDATE_URL)) {
        return new Response('{}', { status: 200 });
      }
      throw new Error(`unexpected fetch to ${url}`);
    });
    vi.stubGlobal('fetch', mock);
    return { urls, mock };
  }

  afterEach(() => {
    vi.unstubAllGlobals();
  });

  it('verified-but-NOT-admin caller -> 403 and never calls accounts:update', async () => {
    const { urls } = installFetchMock({ role: 'incharge' });
    // Injected seams: caller authenticates and the SA token mints fine, so the
    // ONLY thing standing between the request and accounts:update is the
    // server-side admin role re-check.
    const verify: IdTokenVerifier = async () => 'caller-uid-123';
    const mintToken: SaTokenMinter = async () => 'sa-access-token';

    const res = await handleSetPassword(
      makeReq('Bearer good.token.here'),
      ENV,
      verify,
      mintToken,
    );

    expect(res.status).toBe(403);
    await expect(res.json()).resolves.toEqual({ error: 'forbidden' });
    // The load-bearing assertion: the privileged endpoint was never hit.
    expect(urls.some((u) => u.startsWith(ACCOUNTS_UPDATE_URL))).toBe(false);
  });

  it('admin caller DOES reach accounts:update (proves the absence-assertion is meaningful)', async () => {
    // Control case: with an admin role, accounts:update IS reached through the
    // same mocked fetch. If gate ordering were broken in the test above, this
    // confirms the mock would have observed the call.
    const { urls } = installFetchMock({ role: 'admin' });
    const verify: IdTokenVerifier = async () => 'caller-uid-123';
    const mintToken: SaTokenMinter = async () => 'sa-access-token';

    const res = await handleSetPassword(
      makeReq('Bearer good.token.here'),
      ENV,
      verify,
      mintToken,
    );

    expect(res.status).toBe(200);
    await expect(res.json()).resolves.toEqual({ ok: true });
    expect(urls.some((u) => u.startsWith(ACCOUNTS_UPDATE_URL))).toBe(true);
  });

  it('missing Authorization header -> 401, never verifies, mints, or calls accounts:update', async () => {
    const { mock } = installFetchMock({ role: 'admin' });
    // The Bearer regex short-circuits first; supply seams anyway to prove they
    // are never invoked.
    const verify = vi.fn<IdTokenVerifier>(async () => 'caller-uid-123');
    const mintToken = vi.fn<SaTokenMinter>(async () => 'sa-access-token');

    const res = await handleSetPassword(makeReq(undefined), ENV, verify, mintToken);

    expect(res.status).toBe(401);
    await expect(res.json()).resolves.toEqual({ error: 'unauthorized' });
    expect(verify).not.toHaveBeenCalled();
    expect(mintToken).not.toHaveBeenCalled();
    // No upstream of any kind: no Firestore read, no accounts:update.
    expect(mock).not.toHaveBeenCalled();
  });

  it('invalid token (verifier returns null) -> 401, never mints SA token or calls accounts:update', async () => {
    const { mock } = installFetchMock({ role: 'admin' });
    const verify: IdTokenVerifier = async () => null; // signature/claims fail
    const mintToken = vi.fn<SaTokenMinter>(async () => 'sa-access-token');

    const res = await handleSetPassword(
      makeReq('Bearer bad.token.here'),
      ENV,
      verify,
      mintToken,
    );

    expect(res.status).toBe(401);
    await expect(res.json()).resolves.toEqual({ error: 'unauthorized' });
    // Auth gate fails before minting a token or any privileged fetch.
    expect(mintToken).not.toHaveBeenCalled();
    expect(mock).not.toHaveBeenCalled();
  });
});
