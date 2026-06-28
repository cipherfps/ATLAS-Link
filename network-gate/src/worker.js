/**
 * ATLAS Network Gate — Cloudflare Worker
 * ======================================
 *
 * The "Connect with Discord" button in the launcher opens a browser at this
 * Worker. The Worker:
 *   1. sends the user to Discord to log in,
 *   2. confirms they are a real member of the ATLAS server (+ optional role and
 *      account-age checks, + a per-user rate limit),
 *   3. mints a SINGLE-USE, short-lived, ephemeral, tagged Tailscale auth key,
 *   4. bounces the browser back to the launcher's loopback listener with that
 *      key, so the launcher can run `tailscale up` and join the mesh.
 *
 * There is no shared key to leak anymore: a key is only ever created for a
 * verified Discord account, it works exactly once, it expires in minutes, and
 * the device it creates auto-removes itself when the user goes offline.
 *
 * This is serverless: it runs only while handling one login (tens of ms), then
 * sleeps. Nothing runs 24/7; nothing is hosted on your machines.
 *
 * All configuration comes from environment variables / secrets (see README).
 */

const DISCORD_API = 'https://discord.com/api';
const TAILSCALE_API = 'https://api.tailscale.com/api/v2';
const DISCORD_SCOPES = 'identify guilds.members.read';
const DISCORD_EPOCH = 1420070400000; // for snowflake -> account age

export default {
  async fetch(request, env, ctx) {
    const url = new URL(request.url);
    try {
      switch (url.pathname) {
        case '/':
        case '/health':
          return html(200, page('ATLAS Network Gate', 'This is the ATLAS login gate. Open it from the launcher.'));
        case '/login':
          return await handleLogin(url, env);
        case '/callback':
          return await handleCallback(url, env, ctx);
        default:
          return html(404, page('Not found', 'Nothing here.'));
      }
    } catch (err) {
      // Never leak internals to the browser; log for the dashboard tail.
      console.error('gate error:', err && err.stack ? err.stack : String(err));
      return html(500, page('Something went wrong', 'Please return to ATLAS and try again.'));
    }
  },
};

// --- /login: kick off the Discord OAuth flow -------------------------------

async function handleLogin(url, env) {
  const port = (url.searchParams.get('port') || '').trim();
  const launcherState = (url.searchParams.get('state') || '').trim();

  // The launcher tells us which 127.0.0.1 port its one-shot listener is on, and
  // a random state it will verify when we bounce back. We bind both into a
  // signed token so a third party can't drive arbitrary loopback ports or forge
  // a callback. Reject anything that doesn't look like a real loopback port.
  if (!/^\d{1,5}$/.test(port) || Number(port) < 1 || Number(port) > 65535) {
    return html(400, page('Bad request', 'Missing or invalid launcher port.'));
  }
  if (launcherState.length < 8 || launcherState.length > 200) {
    return html(400, page('Bad request', 'Missing or invalid launcher state.'));
  }

  const signed = await signState(env.STATE_SECRET, {
    p: port,
    s: launcherState,
    exp: Date.now() + 5 * 60 * 1000, // the user has 5 minutes to finish login
  });

  const authorize = new URL(`${DISCORD_API}/oauth2/authorize`);
  authorize.searchParams.set('client_id', env.DISCORD_CLIENT_ID);
  authorize.searchParams.set('response_type', 'code');
  authorize.searchParams.set('redirect_uri', `${env.WORKER_PUBLIC_URL}/callback`);
  authorize.searchParams.set('scope', DISCORD_SCOPES);
  authorize.searchParams.set('state', signed);
  return Response.redirect(authorize.toString(), 302);
}

// --- /callback: verify the user and mint a key -----------------------------

async function handleCallback(url, env, ctx) {
  const code = url.searchParams.get('code');
  const signed = url.searchParams.get('state') || '';

  const state = await verifyState(env.STATE_SECRET, signed);
  if (!state) {
    return html(400, page('Login expired', 'That login link is invalid or expired. Please try again from ATLAS.'));
  }
  // From here on we know the launcher's loopback port + state, so failures can
  // be reported back to the launcher instead of dead-ending in the browser.
  const fail = (reason) => loopbackRedirect(state.p, { status: 'error', reason, state: state.s });

  if (!code) return fail('discord_denied');

  // 1) Exchange the code for an access token (needs the confidential secret).
  const token = await discordExchangeCode(code, env);
  if (!token) return fail('discord_token');

  // 2) Confirm membership in the ATLAS guild and read roles + account age.
  const member = await discordGuildMember(token.access_token, env.DISCORD_GUILD_ID);
  if (member === 'not_member') return fail('not_member');
  if (!member) return fail('discord_member');

  const userId = member.user && member.user.id;
  if (!userId) return fail('discord_member');

  // Optional gates -----------------------------------------------------------
  const requiredRole = (env.DISCORD_REQUIRED_ROLE_ID || '').trim();
  if (requiredRole && !(member.roles || []).includes(requiredRole)) {
    return fail('missing_role');
  }
  const minAgeDays = Number(env.DISCORD_MIN_ACCOUNT_AGE_DAYS || '0');
  if (minAgeDays > 0 && accountAgeDays(userId) < minAgeDays) {
    return fail('account_too_new');
  }

  // 3) Per-user rate limit so one account can't mint a flood of keys.
  const windowSec = Number(env.RATE_LIMIT_SECONDS || '21600'); // default 6h
  if (env.RATE_LIMIT) {
    const seen = await env.RATE_LIMIT.get(`rl:${userId}`);
    if (seen) return fail('rate_limited');
  }

  // 4) Mint the one-time Tailscale key.
  const key = await mintTailscaleKey(env, userId);
  if (!key) return fail('tailscale_mint');

  // Record the rate-limit marker only after a successful mint.
  if (env.RATE_LIMIT) {
    ctx.waitUntil(
      env.RATE_LIMIT.put(`rl:${userId}`, String(Date.now()), { expirationTtl: Math.max(60, windowSec) }),
    );
  }

  return loopbackRedirect(state.p, { status: 'ok', key, state: state.s });
}

// --- Discord helpers --------------------------------------------------------

async function discordExchangeCode(code, env) {
  const body = new URLSearchParams({
    client_id: env.DISCORD_CLIENT_ID,
    client_secret: env.DISCORD_CLIENT_SECRET,
    grant_type: 'authorization_code',
    code,
    redirect_uri: `${env.WORKER_PUBLIC_URL}/callback`,
  });
  const res = await fetch(`${DISCORD_API}/oauth2/token`, {
    method: 'POST',
    headers: { 'content-type': 'application/x-www-form-urlencoded' },
    body,
  });
  if (!res.ok) {
    console.error('discord token exchange failed:', res.status, await safeText(res));
    return null;
  }
  return res.json();
}

/**
 * Returns the member object ({ user, roles, ... }) if the user is in the guild,
 * the string 'not_member' if Discord says they aren't (404), or null on error.
 */
async function discordGuildMember(accessToken, guildId) {
  const res = await fetch(`${DISCORD_API}/users/@me/guilds/${guildId}/member`, {
    headers: { authorization: `Bearer ${accessToken}` },
  });
  if (res.status === 404) return 'not_member';
  if (!res.ok) {
    console.error('discord member lookup failed:', res.status, await safeText(res));
    return null;
  }
  return res.json();
}

function accountAgeDays(userId) {
  try {
    const createdMs = Number((BigInt(userId) >> 22n)) + DISCORD_EPOCH;
    return (Date.now() - createdMs) / (1000 * 60 * 60 * 24);
  } catch {
    return 0;
  }
}

// --- Tailscale helpers ------------------------------------------------------

/**
 * Mints a single-use, ephemeral, pre-authorized, tagged auth key that expires
 * in minutes. Single-use + the short key expiry mean a leaked key is worthless;
 * ephemeral means the device cleans itself up when the user disconnects.
 */
async function mintTailscaleKey(env, userId) {
  const access = await tailscaleAccessToken(env);
  if (!access) return null;

  const tailnet = (env.TAILSCALE_TAILNET || '-').trim();
  const tag = (env.TAILSCALE_TAG || 'tag:atlas-mesh').trim();
  const expirySeconds = Number(env.KEY_EXPIRY_SECONDS || '300'); // 5 min default

  const res = await fetch(`${TAILSCALE_API}/tailnet/${encodeURIComponent(tailnet)}/keys`, {
    method: 'POST',
    headers: {
      authorization: `Bearer ${access}`,
      'content-type': 'application/json',
    },
    body: JSON.stringify({
      description: `atlas-discord-${userId}`,
      expirySeconds,
      capabilities: {
        devices: {
          create: {
            reusable: false,
            ephemeral: true,
            preauthorized: true,
            tags: [tag],
          },
        },
      },
    }),
  });
  if (!res.ok) {
    console.error('tailscale key mint failed:', res.status, await safeText(res));
    return null;
  }
  const data = await res.json();
  return data.key || null;
}

/**
 * Exchanges the Tailscale OAuth client credentials for a short-lived API access
 * token. Using an OAuth client (instead of a personal token) means nothing
 * expires every 90 days — there's no recurring rotation to remember.
 */
async function tailscaleAccessToken(env) {
  const body = new URLSearchParams({
    client_id: env.TAILSCALE_OAUTH_CLIENT_ID,
    client_secret: env.TAILSCALE_OAUTH_CLIENT_SECRET,
    grant_type: 'client_credentials',
  });
  const res = await fetch(`${TAILSCALE_API}/oauth/token`, {
    method: 'POST',
    headers: { 'content-type': 'application/x-www-form-urlencoded' },
    body,
  });
  if (!res.ok) {
    console.error('tailscale oauth token failed:', res.status, await safeText(res));
    return null;
  }
  const data = await res.json();
  return data.access_token || null;
}

// --- Signed state (HMAC, no storage needed) --------------------------------

async function signState(secret, payload) {
  const json = JSON.stringify(payload);
  const data = b64urlEncode(new TextEncoder().encode(json));
  const sig = await hmac(secret, data);
  return `${data}.${sig}`;
}

async function verifyState(secret, token) {
  if (!token || token.indexOf('.') === -1) return null;
  const [data, sig] = token.split('.', 2);
  const expected = await hmac(secret, data);
  if (!timingSafeEqual(sig, expected)) return null;
  let payload;
  try {
    payload = JSON.parse(new TextDecoder().decode(b64urlDecode(data)));
  } catch {
    return null;
  }
  if (!payload || typeof payload.exp !== 'number' || Date.now() > payload.exp) return null;
  return payload;
}

async function hmac(secret, data) {
  const key = await crypto.subtle.importKey(
    'raw',
    new TextEncoder().encode(secret),
    { name: 'HMAC', hash: 'SHA-256' },
    false,
    ['sign'],
  );
  const sig = await crypto.subtle.sign('HMAC', key, new TextEncoder().encode(data));
  return b64urlEncode(new Uint8Array(sig));
}

function timingSafeEqual(a, b) {
  if (typeof a !== 'string' || typeof b !== 'string' || a.length !== b.length) return false;
  let diff = 0;
  for (let i = 0; i < a.length; i++) diff |= a.charCodeAt(i) ^ b.charCodeAt(i);
  return diff === 0;
}

// --- Loopback redirect + small HTML helpers --------------------------------

function loopbackRedirect(port, params) {
  const target = new URL(`http://127.0.0.1:${port}/`);
  for (const [k, v] of Object.entries(params)) {
    if (v !== undefined && v !== null) target.searchParams.set(k, String(v));
  }
  // 302 so the browser hands the result to the launcher's local listener, which
  // then shows its own "you can return to ATLAS" page.
  return Response.redirect(target.toString(), 302);
}

function html(status, body) {
  return new Response(body, {
    status,
    headers: { 'content-type': 'text/html; charset=utf-8' },
  });
}

function page(title, message) {
  return `<!doctype html><html><head><meta charset="utf-8">
<meta name="viewport" content="width=device-width, initial-scale=1">
<title>${escapeHtml(title)}</title>
<style>
  body{margin:0;background:#0b1220;color:#e6edf6;font:15px/1.5 system-ui,Segoe UI,Roboto,sans-serif;
       display:flex;min-height:100vh;align-items:center;justify-content:center}
  .card{max-width:420px;padding:32px;text-align:center}
  h1{font-size:20px;margin:0 0 10px}
  p{opacity:.7;margin:0}
</style></head>
<body><div class="card"><h1>${escapeHtml(title)}</h1><p>${escapeHtml(message)}</p></div></body></html>`;
}

function escapeHtml(s) {
  return String(s).replace(/[&<>"']/g, (c) => (
    { '&': '&amp;', '<': '&lt;', '>': '&gt;', '"': '&quot;', "'": '&#39;' }[c]
  ));
}

async function safeText(res) {
  try { return await res.text(); } catch { return '<no body>'; }
}

// --- base64url ---------------------------------------------------------------

function b64urlEncode(bytes) {
  let bin = '';
  for (let i = 0; i < bytes.length; i++) bin += String.fromCharCode(bytes[i]);
  return btoa(bin).replace(/\+/g, '-').replace(/\//g, '_').replace(/=+$/, '');
}

function b64urlDecode(str) {
  const pad = str.length % 4 === 0 ? '' : '='.repeat(4 - (str.length % 4));
  const bin = atob(str.replace(/-/g, '+').replace(/_/g, '/') + pad);
  const out = new Uint8Array(bin.length);
  for (let i = 0; i < bin.length; i++) out[i] = bin.charCodeAt(i);
  return out;
}
