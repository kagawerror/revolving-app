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

    const ok = results.filter((r) => r.status === 'fulfilled' && r.value.ok).length;
    return new Response(JSON.stringify({ sent: ok, roles: recipientRoles.length }), {
      headers: { 'content-type': 'application/json' },
    });
  },
};
