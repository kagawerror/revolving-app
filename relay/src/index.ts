// Free Cloudflare Worker. Two routes:
//   POST /                    -> OneSignal push relay (unchanged).
//   POST /admin/set-password  -> admin-only password set (see admin.ts).
// Secrets (wrangler secret put):
//   ONESIGNAL_APP_ID, ONESIGNAL_REST_KEY, RELAY_TOKEN (optional, push pre-filter)
//   FB_PROJECT_ID, FB_CLIENT_EMAIL, FB_PRIVATE_KEY (admin route service account)

import { AdminEnv, handleSetPassword } from './admin';

export interface Env extends AdminEnv {
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

async function handlePush(req: Request, env: Env): Promise<Response> {
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

  const ok = results.filter((r) => r.status === 'fulfilled' && r.value.ok).length;
  return new Response(JSON.stringify({ sent: ok, roles: recipientRoles.length }), {
    headers: { 'content-type': 'application/json' },
  });
}

export default {
  async fetch(req: Request, env: Env): Promise<Response> {
    const pathname = new URL(req.url).pathname;

    // Admin password route. Web origins must lock down CORS before exposing
    // this to a browser (see README TODO); mobile clients don't enforce CORS,
    // so no Access-Control-Allow-Origin is emitted here intentionally.
    if (pathname === '/admin/set-password') {
      return handleSetPassword(req, env);
    }

    // Existing push relay stays at root, behavior unchanged.
    if (pathname === '/' || pathname === '') {
      return handlePush(req, env);
    }

    return new Response('Not found', { status: 404 });
  },
};
