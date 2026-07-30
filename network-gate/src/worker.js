/**
 * ATLAS Network Gate — Cloudflare Worker
 * ======================================
 *
 * The "Connect with Discord" button in the launcher opens a browser at this
 * Worker. The Worker:
 *   1. sends the user to Discord to log in,
 *   2. confirms they are a real member of the ATLAS server (+ optional role and
 *      account-age checks, + a per-user rate limit, + a ban check),
 *   3. mints a SINGLE-USE, short-lived, ephemeral, tagged Tailscale auth key,
 *   4. bounces the browser back to the launcher's loopback listener with that
 *      key, so the launcher can run `tailscale up` and join the mesh.
 *
 * There is no shared key to leak anymore: a key is only ever created for a
 * verified Discord account, it works exactly once, it expires in minutes, and
 * the device it creates auto-removes itself when the user goes offline.
 *
 * It also hosts a Discord-gated admin panel at /admin. The panel has exactly
 * two verbs: KICK ends someone's session now and they may reconnect; BAN ends
 * it now AND stops them coming back, and is reversed by UNBAN. There are TWO
 * ways to ban someone:
 *   * BAN THE IP (the primary control). The operator sees the live device list
 *     and bans the 100.x address in front of them. The address comes from the
 *     Tailscale API, never from the client, so it cannot be spoofed by a
 *     hostname rename or an impostor picking someone else's display name.
 *     Tailscale's policy file is accept-only — there is no deny rule — so the
 *     ban is ENFORCED BY US: `sweepBannedIps` deletes any device holding a
 *     banned address, on a cron trigger, on every panel refresh, and instantly
 *     at ban time. Per Tailscale kb/1033 a node keeps its address for as long
 *     as it stays registered; ATLAS nodes are ephemeral, so a full disconnect
 *     can still yield a new one. The operator accepts that and bans again.
 *   * BAN THE ACCOUNT. The launcher declares its own display name at login
 *     (`?name=`), bound into the signed login state and recorded in the mint
 *     ledger server-side, so it is never inferred from the (client-controlled)
 *     Tailscale hostname. The ban is written against the DISCORD ACCOUNT and
 *     checked at the top of /callback, so that account cannot mint a key again.
 *
 * This is serverless: it runs only while handling one login (tens of ms) or one
 * cron tick, then sleeps. Nothing runs 24/7; nothing is hosted on your machines.
 *
 * All configuration comes from environment variables / secrets (see wrangler.toml).
 */

const DISCORD_API = 'https://discord.com/api';
const TAILSCALE_API = 'https://api.tailscale.com/api/v2';
const DISCORD_SCOPES = 'identify guilds.members.read';
const ADMIN_DISCORD_SCOPES = 'identify'; // admin login needs nothing but the user id
const DISCORD_EPOCH = 1420070400000; // for snowflake -> account age

/**
 * The ATLAS mark, inlined as a data URI (192x185 PNG, pre-optimized).
 *
 * The admin pages are strictly self-contained — they must make ZERO external
 * requests — so the logo travels in the document rather than as an <img src>
 * pointing at a CDN. Do not reformat or re-encode this line.
 */
const ATLAS_LOGO = 'data:image/png;base64,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';

/**
 * The official Discord mark, inlined for the same reason as ATLAS_LOGO: no
 * external URL, no icon font. The path data is the canonical simple-icons
 * `discord` entry, verbatim. `fill="currentColor"` so it always matches the
 * colour of the label it sits beside.
 */
function discordMark(size) {
  return `<svg class="dmark" viewBox="0 0 24 24" width="${size}" height="${size}" fill="currentColor" aria-hidden="true" focusable="false"><path d="M20.317 4.3698a19.7913 19.7913 0 00-4.8851-1.5152.0741.0741 0 00-.0785.0371c-.211.3753-.4447.8648-.6083 1.2495-1.8447-.2762-3.68-.2762-5.4868 0-.1636-.3933-.4058-.8742-.6177-1.2495a.077.077 0 00-.0785-.037 19.7363 19.7363 0 00-4.8852 1.515.0699.0699 0 00-.0321.0277C.5334 9.0458-.319 13.5799.0992 18.0578a.0824.0824 0 00.0312.0561c2.0528 1.5076 4.0413 2.4228 5.9929 3.0294a.0777.0777 0 00.0842-.0276c.4616-.6304.8731-1.2952 1.226-1.9942a.076.076 0 00-.0416-.1057c-.6528-.2476-1.2743-.5495-1.8722-.8923a.077.077 0 01-.0076-.1277c.1258-.0943.2517-.1923.3718-.2914a.0743.0743 0 01.0776-.0105c3.9278 1.7933 8.18 1.7933 12.0614 0a.0739.0739 0 01.0785.0095c.1202.099.246.1981.3728.2924a.077.077 0 01-.0066.1276 12.2986 12.2986 0 01-1.873.8914.0766.0766 0 00-.0407.1067c.3604.698.7719 1.3628 1.225 1.9932a.076.076 0 00.0842.0286c1.961-.6067 3.9495-1.5219 6.0023-3.0294a.077.077 0 00.0313-.0552c.5004-5.177-.8382-9.6739-3.5485-13.6604a.061.061 0 00-.0312-.0286zM8.02 15.3312c-1.1825 0-2.1569-1.0857-2.1569-2.419 0-1.3332.9555-2.4189 2.157-2.4189 1.2108 0 2.1757 1.0952 2.1568 2.419 0 1.3332-.9555 2.4189-2.1569 2.4189zm7.9748 0c-1.1825 0-2.1569-1.0857-2.1569-2.419 0-1.3332.9554-2.4189 2.1569-2.4189 1.2108 0 2.1757 1.0952 2.1568 2.419 0 1.3332-.946 2.4189-2.1568 2.4189Z"/></svg>`;
}

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
        case '/admin':
          return await handleAdmin(request, env);
        case '/admin/login':
          return await handleAdminLogin(env);
        case '/admin/callback':
          return await handleAdminCallback(url, env);
        case '/admin/logout':
          return handleAdminLogout();
        case '/admin/avatar':
          return await handleAdminAvatar(request, env);
        case '/admin/api/state':
        case '/admin/api/ban':
        case '/admin/api/unban':
        case '/admin/api/banip':
        case '/admin/api/unbanip':
        case '/admin/api/kick':
        case '/admin/api/kickuser':
        case '/admin/api/kickall':
          return await handleAdminApi(request, url, env);
        default:
          return html(404, page('Not found', 'Nothing here.'));
      }
    } catch (err) {
      // Never leak internals to the browser; log for the dashboard tail.
      console.error('gate error:', err && err.stack ? err.stack : String(err));
      if (url.pathname.startsWith('/admin/api/')) return json(500, { error: 'server' });
      return html(500, page('Something went wrong', 'Please return to ATLAS and try again.'));
    }
  },

  /**
   * Cron trigger — the standing enforcement of IP bans.
   *
   * Signature per Cloudflare's docs for the module-syntax scheduled handler:
   * `scheduled(controller: ScheduledController, env, ctx: ExecutionContext)`.
   * There is NO request here: nothing in this path may touch `request`, a
   * cookie, or an Origin header.
   *
   * Schedule: `* * * * *` (every minute). Verified against Cloudflare's docs —
   * Cron Triggers are available on the Workers FREE plan (limits page: "Number
   * of Cron Triggers per account" = 5 on Workers Free, 250 on Workers Paid),
   * and "* * * * *" / "At every minute" is a documented supported pattern, so
   * one minute IS the finest allowed granularity and we use it. The free plan's
   * CPU budget for a cron invocation is 10 ms, which this fits: the sweep is
   * almost entirely time spent waiting on the Tailscale API, and waiting on I/O
   * is not CPU time.
   */
  async scheduled(controller, env, ctx) {
    // No access token is minted here: sweepBannedIps reads the compact IP-ban
    // index first and returns without touching Tailscale when there is nothing
    // to enforce. Normal ticks use one inexpensive KV get(), never list().
    const kicked = await sweepBannedIps(env);
    if (kicked) console.log('sweep removed', kicked, 'banned device(s)');
  },
};

/** Longest launcher-declared name we record. Matches the launcher's own field. */
const MAX_NAME_LENGTH = 32;

// --- /login: kick off the Discord OAuth flow -------------------------------

async function handleLogin(url, env) {
  const port = (url.searchParams.get('port') || '').trim();
  const launcherState = (url.searchParams.get('state') || '').trim();
  // The display name the launcher is about to use in game and on the mesh. It
  // is bound into the SIGNED state, so the value that reaches the ledger is the
  // one the launcher declared at the start of this login and cannot be swapped
  // on the way back. Older launchers send nothing — that is allowed, and the
  // ledger row simply has no name.
  const name = (url.searchParams.get('name') || '').trim().slice(0, MAX_NAME_LENGTH);

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
    typ: 'login', // one secret signs three token shapes; every reader asserts typ
    p: port,
    s: launcherState,
    n: name || null,
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

  // typ pins this to a /login token: the same secret also signs admin-login and
  // admin-session tokens, and neither may be replayed into the player flow.
  const state = await verifyState(env.STATE_SECRET, signed);
  if (!state || state.typ !== 'login' || typeof state.p !== 'string' || typeof state.s !== 'string') {
    return html(400, page('Login expired', 'That login link is invalid or expired. Please try again from ATLAS.'));
  }
  // From here on we know the launcher's loopback port + state, so failures can
  // be reported back to the launcher instead of dead-ending in the browser.
  const fail = (reason) => loopbackRedirect(state.p, { status: 'error', reason, state: state.s });

  if (!code) return fail('discord_denied');

  // 1) Exchange the code for an access token (needs the confidential secret).
  const token = await discordExchangeCode(code, env, `${env.WORKER_PUBLIC_URL}/callback`);
  if (!token) return fail('discord_token');

  // 2) Confirm membership in the ATLAS guild and read roles + account age.
  const member = await discordGuildMember(token.access_token, env.DISCORD_GUILD_ID);
  if (member === 'not_member') return fail('not_member');
  if (!member) return fail('discord_member');

  const userId = member.user && member.user.id;
  if (!userId) return fail('discord_member');

  // Banned accounts stop here, before any other gate.
  if (env.DB && (await env.DB.get(`ban:${userId}`))) {
    return fail('banned');
  }

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
  if (env.DB) {
    const seen = await env.DB.get(`rl:${userId}`);
    if (seen) return fail('rate_limited');
  }

  // 4) Mint the one-time Tailscale key.
  const key = await mintTailscaleKey(env, userId);
  if (!key) return fail('tailscale_mint');

  // Record the rate-limit marker only after a successful mint.
  if (env.DB) {
    ctx.waitUntil(
      env.DB.put(`rl:${userId}`, String(Date.now()), { expirationTtl: Math.max(60, windowSec) }),
    );
  }

  // 5) Ledger: who connected, under what name, and when. This is what the admin
  // panel's Recent players list is built from, and where a ban or a player kick
  // gets the name to sweep
  // devices by. invTs makes KV list newest-first. The record goes into KV
  // METADATA as well as the value for the one-time legacy-index migration.
  if (env.DB) {
    const ts = Date.now();
    const invTs = String(9999999999999 - ts).padStart(13, '0');
    const record = {
      id: userId,
      // The launcher's declared name — authoritative, and what the operator sees.
      name: typeof state.n === 'string' ? state.n.trim().slice(0, MAX_NAME_LENGTH) || null : null,
      // Kept only as a tiebreaker when two players show the same name.
      discordName: member.user.global_name || member.user.username || null,
      ts,
    };
    ctx.waitUntil(
      Promise.all([
        env.DB.put(`mint:${invTs}:${userId}`, JSON.stringify(record), {
          expirationTtl: 7 * 86400,
          metadata: mintMetadata(record),
        }),
        upsertRecordIndex(env, MINT_INDEX, record, 200, 'id', 7 * 86400 * 1000),
      ]),
    );
  }

  return loopbackRedirect(state.p, {
    status: 'ok',
    key,
    state: state.s,
  });
}

// --- Admin auth --------------------------------------------------------------

/** ADMIN_DISCORD_IDS is a comma-separated allowlist; empty/unset = nobody. */
function isAdmin(env, userId) {
  if (!userId) return false;
  const ids = (env.ADMIN_DISCORD_IDS || '')
    .split(',')
    .map((s) => s.trim())
    .filter(Boolean);
  return ids.includes(String(userId));
}

/**
 * The atlas_admin cookie is the ONLY admin credential — the panel is a browser
 * app and nothing else calls this API, so there is no bearer-token path to
 * abuse. The cookie holds a signed state payload {uid, name, av, exp,
 * typ:'admin'}; the uid must STILL be in ADMIN_DISCORD_IDS and must NOT be
 * banned, so removing an id from the var — or banning the account — revokes
 * live sessions. Returns { uid, name, avatar } or null.
 */
async function requireAdmin(request, env) {
  const token = readCookie(request, 'atlas_admin');
  if (!token) return null;
  const payload = await verifyState(env.STATE_SECRET, token);
  if (!payload || payload.typ !== 'admin' || !isAdmin(env, payload.uid)) return null;
  // A banned account loses the panel too — otherwise an admin banned by another
  // admin could simply sign in and unban themselves.
  if (env.DB && (await env.DB.get(`ban:${payload.uid}`))) return null;
  // Re-validate the hash on the way OUT as well as on the way in: it is about to
  // be pasted into a URL, and a signed token is only as trustworthy as the code
  // that minted it (an older/looser version of this Worker, say).
  return {
    uid: payload.uid,
    name: payload.name || payload.uid,
    avatar: validAvatarHash(payload.av) ? payload.av : null,
  };
}

function readCookie(request, name) {
  const header = request.headers.get('cookie') || '';
  for (const part of header.split(';')) {
    const eq = part.indexOf('=');
    if (eq === -1) continue;
    if (part.slice(0, eq).trim() === name) return part.slice(eq + 1).trim();
  }
  return '';
}

// --- /admin: panel (or landing page when signed out) -----------------------

async function handleAdmin(request, env) {
  const session = await requireAdmin(request, env);
  if (session) return html(200, adminPanelPage());
  return html(200, adminLandingPage());
}

// --- /admin/login: Discord OAuth for admins (web cookie) --------------------

async function handleAdminLogin(env) {
  // Admin login is web-only: it always ends in a cookie on this origin, so the
  // token carries nothing but its type and expiry.
  const signed = await signState(env.STATE_SECRET, {
    typ: 'adminlogin',
    exp: Date.now() + 5 * 60 * 1000,
  });
  const authorize = new URL(`${DISCORD_API}/oauth2/authorize`);
  authorize.searchParams.set('client_id', env.DISCORD_CLIENT_ID);
  authorize.searchParams.set('response_type', 'code');
  authorize.searchParams.set('redirect_uri', `${env.WORKER_PUBLIC_URL}/admin/callback`);
  authorize.searchParams.set('scope', ADMIN_DISCORD_SCOPES);
  authorize.searchParams.set('state', signed);
  return Response.redirect(authorize.toString(), 302);
}

// --- /admin/callback: mint an admin session --------------------------------

async function handleAdminCallback(url, env) {
  const code = url.searchParams.get('code');
  // typ pins this to an /admin/login token (see handleCallback for why).
  const state = await verifyState(env.STATE_SECRET, url.searchParams.get('state') || '');
  if (!state || state.typ !== 'adminlogin') {
    return html(400, page('Login expired', 'That login link is invalid or expired. Please start over.'));
  }
  const fail = () => html(403, page('Login failed', 'Discord login did not complete. Please try again.'));

  if (!code) return fail();

  const token = await discordExchangeCode(code, env, `${env.WORKER_PUBLIC_URL}/admin/callback`);
  if (!token) return fail();

  const user = await discordUser(token.access_token);
  if (!user || !user.id) return fail();

  // A banned account is treated exactly like a non-admin, so a banned admin
  // can't sign in and lift their own ban.
  const banned = env.DB ? !!(await env.DB.get(`ban:${user.id}`)) : false;
  if (!isAdmin(env, user.id) || banned) {
    return html(403, page('Not an admin', 'This Discord account is not an ATLAS admin.'));
  }

  const name = user.global_name || user.username || user.id;
  // The avatar HASH (not a URL) rides in the session so /admin/avatar can rebuild
  // the CDN link server-side. It is ~33 characters, so it costs a cookie nothing
  // and needs no KV row. `avatar` is null for an account that never set one.
  const av = validAvatarHash(user.avatar) ? user.avatar : null;
  const session = await signState(env.STATE_SECRET, {
    uid: user.id,
    name,
    av,
    exp: Date.now() + 12 * 60 * 60 * 1000, // 12h admin session
    typ: 'admin',
  });

  return new Response(null, {
    status: 302,
    headers: {
      location: `${env.WORKER_PUBLIC_URL}/admin`,
      'set-cookie': `atlas_admin=${session}; HttpOnly; Secure; SameSite=Lax; Path=/admin; Max-Age=43200`,
    },
  });
}

// --- /admin/logout ----------------------------------------------------------

function handleAdminLogout() {
  return new Response(null, {
    status: 302,
    headers: {
      location: '/admin',
      'set-cookie': 'atlas_admin=; HttpOnly; Secure; SameSite=Lax; Path=/admin; Max-Age=0',
    },
  });
}

// --- /admin/avatar: the signed-in admin's Discord avatar, proxied ----------
//
// The panel is strictly self-contained: it makes ZERO third-party requests, and
// an <img src="https://cdn.discordapp.com/..."> would break that (and hand
// Discord a hit every time an operator opens the panel). So the browser asks
// THIS origin, and the Worker does the one fetch.
//
// Verified against Discord's official CDN endpoint reference:
//   user avatar     https://cdn.discordapp.com/avatars/<user_id>/<hash>.png
//   size            ?size=<power of two, 16..4096>
// (Animated avatars have an `a_` hash prefix and are also served as a static
// PNG at the same path, which is what we want for a 22px header chip.)

const DISCORD_CDN = 'https://cdn.discordapp.com';

/** Requested from Discord: the smallest power of two that covers a 22px @2x chip. */
const AVATAR_SIZE = 64;

/**
 * A Discord avatar hash is 32 lowercase hex characters, optionally prefixed
 * `a_` for an animated one. Anything else is refused rather than interpolated
 * into a URL — this is the ONE value in the session that becomes part of an
 * outbound path, so it gets a whitelist, not an escape.
 */
function validAvatarHash(hash) {
  return typeof hash === 'string' && /^(a_)?[0-9a-f]{32}$/.test(hash);
}

/**
 * The neutral silhouette shown whenever a real avatar is not available. Inline
 * bytes, so the fallback path itself makes no request either, and the header can
 * never render a broken-image icon.
 */
const AVATAR_FALLBACK =
  '<svg xmlns="http://www.w3.org/2000/svg" viewBox="0 0 64 64" width="64" height="64" role="img" aria-label="">' +
  '<circle cx="32" cy="32" r="32" fill="#1e2a44"/>' +
  '<circle cx="32" cy="25" r="11" fill="#54678c"/>' +
  '<path d="M32 39c-11.6 0-21 6.9-21 15.4V64h42v-9.6C53 45.9 43.6 39 32 39z" fill="#54678c"/></svg>';

function avatarFallback() {
  return new Response(AVATAR_FALLBACK, {
    status: 200,
    headers: {
      'content-type': 'image/svg+xml; charset=utf-8',
      // Deliberately SHORTER than the happy path: a fallback is often the result
      // of a transient Discord failure, and a day-long cache would freeze the
      // silhouette in place long after the real avatar came back.
      'cache-control': 'private, max-age=300',
    },
  });
}

async function handleAdminAvatar(request, env) {
  const session = await requireAdmin(request, env);
  if (!session) return json(401, { error: 'auth' });
  if (request.method !== 'GET' && request.method !== 'HEAD') return json(405, { error: 'method' });

  // No hash means the account never set an avatar and Discord shows one of its
  // stock silhouettes for it — ours is the same idea, and costs no request.
  if (!session.avatar || !/^\d{5,25}$/.test(String(session.uid))) return avatarFallback();

  try {
    const src = `${DISCORD_CDN}/avatars/${session.uid}/${session.avatar}.png?size=${AVATAR_SIZE}`;
    const res = await fetch(src, { cf: { cacheTtl: 86400, cacheEverything: true } });
    const type = res.headers.get('content-type') || '';
    if (!res.ok || !type.toLowerCase().startsWith('image/')) {
      console.error('avatar fetch failed:', res.status, type);
      return avatarFallback();
    }
    return new Response(res.body, {
      status: 200,
      headers: {
        'content-type': type,
        // One fetch per browser per day — the panel re-polls state every 10s and
        // must not drag an avatar request along with it.
        'cache-control': 'private, max-age=86400',
      },
    });
  } catch (err) {
    console.error('avatar proxy error:', err && err.stack ? err.stack : String(err));
    return avatarFallback();
  }
}

// --- /admin/api/*: JSON API behind requireAdmin ----------------------------

async function handleAdminApi(request, url, env) {
  const session = await requireAdmin(request, env);
  if (!session) return json(401, { error: 'auth' });

  if (url.pathname === '/admin/api/state') {
    if (request.method !== 'GET') return json(405, { error: 'method' });
    return handleAdminState(session, env);
  }

  // Everything below mutates, and auth is cookie-only, so EVERY mutating call
  // is a browser call and gets the full treatment: POST only, a custom header
  // an HTML form cannot set (blocks classic CSRF), and a same-origin Origin.
  if (request.method !== 'POST') return json(405, { error: 'method' });
  if (request.headers.get('x-atlas-admin') !== '1') return json(403, { error: 'csrf' });
  const origin = request.headers.get('origin') || '';
  if (origin !== new URL(env.WORKER_PUBLIC_URL).origin) return json(403, { error: 'csrf' });

  const body = (await readJson(request)) || {};
  switch (url.pathname) {
    case '/admin/api/ban':
      return handleAdminBan(session, env, body);
    case '/admin/api/unban':
      return handleAdminUnban(env, body);
    case '/admin/api/banip':
      return handleAdminBanIp(session, env, body);
    case '/admin/api/unbanip':
      return handleAdminUnbanIp(env, body);
    case '/admin/api/kick':
      return handleAdminKick(env, body);
    case '/admin/api/kickuser':
      return handleAdminKickUser(env, body);
    case '/admin/api/kickall':
      return handleAdminKickAll(env);
    default:
      return json(404, { error: 'not_found' });
  }
}

/** How many people the Players list shows. */
const MAX_PLAYERS = 100;

/**
 * Everything the panel draws: the admin's own identity, the live device list
 * (Online now — the panel's primary section), the Recent players list (one row
 * per person, newest login first), and both kinds of ban. The panel merges
 * `bans` and `bannedIps` into its single Bans section; they stay separate on
 * the wire because they are separate stores with separate unban routes.
 *
 * The sweep runs FIRST, before the device list is read, so the panel is
 * self-healing while it is open: a banned address that reappeared between cron
 * ticks is gone by the time the operator sees the list.
 */
async function handleAdminState(session, env) {
  const access = await tailscaleAccessToken(env);
  if (!access) return json(502, { error: 'tailscale' });

  await sweepBannedIps(env, access);

  const [rawDevices, mintState, banState, bannedIpState] = await Promise.all([
    tailscaleDevices(env, access),
    loadMintRecords(env, 200),
    loadBanRecords(env),
    loadBannedIpRecords(env),
  ]);
  if (!rawDevices) return json(502, { error: 'tailscale' });
  const mints = mintState.records;
  const bans = banState.records;
  const bannedIps = bannedIpState.records;

  // Devices are DISPLAY ONLY — the hostname is client-controlled, so a device's
  // name segment is a claim, never an identity. Kick works on the deviceId and
  // an IP ban works on the address, both of which come from Tailscale.
  const devices = rawDevices.map((d) => ({
    deviceId: d.nodeId || d.id,
    hostname: d.hostname || '',
    name: hostNameSegment(d.hostname),
    addresses: d.addresses || [],
    os: d.os || '',
    lastSeen: d.lastSeen ?? null,
    online: deviceOnline(d.lastSeen),
  }));

  // One row per Discord account, keeping their newest login (the ledger is
  // already newest-first, so the first row we see for an id wins).
  const players = [];
  const seen = new Set();
  for (const m of mints) {
    if (!m || !m.id || seen.has(m.id)) continue;
    seen.add(m.id);
    players.push({
      id: m.id,
      name: m.name ?? null,
      discordName: m.discordName ?? null,
      ts: m.ts,
      // Same `online` the device row shows — an unreaped node must not give a
      // player a green dot while its own device row says "last seen 20 min ago".
      online: devices.some((d) => d.online && hostMatchesName(d.hostname, m.name)),
    });
    if (players.length >= MAX_PLAYERS) break;
  }

  return json(200, {
    admin: { id: session.uid, name: session.name },
    players,
    devices,
    bans,
    bannedIps,
    storageLimited: mintState.degraded || banState.degraded || bannedIpState.degraded,
  });
}

/**
 * Is this device connected right now?
 *
 * ONE derivation, used for both the device row and the player dot, so the two
 * can never disagree. Tailscale may ALWAYS send `lastSeen` (including for a
 * node that is connected to control this second, and `0001-01-01T00:00:00Z` for
 * one that has never been seen), so absence alone is not a usable test —
 * RECENCY is. An unparseable timestamp is treated as offline: it is neither
 * absent nor recent, and a stale row is the safer thing to show.
 */
const ONLINE_WINDOW_MS = 5 * 60 * 1000;

function deviceOnline(lastSeen, now = Date.now()) {
  if (lastSeen === null || lastSeen === undefined || lastSeen === '') return true;
  const t = Date.parse(lastSeen);
  if (!Number.isFinite(t)) return false;
  return now - t <= ONLINE_WINDOW_MS;
}

/**
 * The player's newest ledger row, or null. ONE lookup shared by "ban the
 * account" and "kick the player" so both resolve the same person to the same
 * declared name. The ledger is already newest-first.
 */
async function newestMintFor(env, userId) {
  const mints = await listMintRecordsFast(env, 200);
  return mints.find((m) => m && m.id === userId) || null;
}

/**
 * THE device-matching path, shared by the account ban and the player kick so
 * the two can never diverge: remove every device currently wearing this
 * declared name. Returns how many were removed.
 *
 * Matching on the (client-controlled) hostname is deliberately over-inclusive:
 * an over-kicked innocent simply reconnects. Nothing durable hangs off it —
 * a BAN is written against the Discord account, and this only ends sessions.
 */
async function kickDevicesByName(env, access, declaredName) {
  if (!declaredName) return 0;
  const devices = await tailscaleDevices(env, access);
  let kicked = 0;
  for (const d of devices || []) {
    if (!hostMatchesName(d.hostname, declaredName)) continue;
    if (await tailscaleDeleteDevice(access, d.nodeId || d.id)) kicked++;
  }
  return kicked;
}

/**
 * Bans the Discord account, then kicks every device currently wearing that
 * player's name. The ban is what actually holds — the check at the top of
 * /callback stops the account reconnecting — so the kick only needs to end the
 * current session.
 */
async function handleAdminBan(session, env, body) {
  const userId = String(body.userId || '').trim();
  if (!/^\d{5,25}$/.test(userId)) return json(400, { error: 'bad_request' });
  const note = typeof body.note === 'string' ? body.note.trim().slice(0, 500) : '';

  const newest = await newestMintFor(env, userId);
  const name = (newest && (newest.name || newest.discordName)) || 'unknown';

  const ban = { id: userId, name, bannedBy: session.name, ts: Date.now() };
  if (note) ban.note = note;
  // No TTL — bans stick until unban. Metadata supports one-time migration from
  // deployments that predate the compact read index.
  await Promise.all([
    env.DB.put(`ban:${userId}`, JSON.stringify(ban), { metadata: banMetadata(ban) }),
    upsertRecordIndex(env, BAN_INDEX, ban, MAX_BANS, 'id'),
  ]);

  let kicked = 0;
  const declared = newest && newest.name;
  if (declared) {
    const access = await tailscaleAccessToken(env);
    if (access) kicked = await kickDevicesByName(env, access, declared);
  }

  const out = { ok: true, kicked };
  // Banning an admin works, but they keep panel access the moment they're
  // unbanned — only editing ADMIN_DISCORD_IDS is permanent.
  if (isAdmin(env, userId)) out.warning = 'target-is-admin';
  return json(200, out);
}

async function handleAdminUnban(env, body) {
  const userId = String(body.userId || '').trim();
  if (!/^\d{5,25}$/.test(userId)) return json(400, { error: 'bad_request' });
  await Promise.all([
    env.DB.delete(`ban:${userId}`),
    removeRecordFromIndex(env, BAN_INDEX, userId, MAX_BANS, 'id'),
  ]);
  return json(200, { ok: true });
}

// --- IP bans ----------------------------------------------------------------
//
// The address is the one thing on a device that the client does not choose:
// Tailscale assigns it and hands it to us over the API. Banning it sidesteps
// every defect of matching on a hostname (renames, case, impostors picking
// someone else's display name). Tailscale has no deny rule, so the ban is
// enforced by deleting the devices that hold the address — see sweepBannedIps.

/** Longest thing we will even consider an address (IPv6 + zone is well under). */
const MAX_IP_LENGTH = 64;

/** Lowercase + trim so a key, a ban record, and a device address all compare. */
function normalizeIp(value) {
  return String(value == null ? '' : value).trim().toLowerCase();
}

/**
 * Cheap shape gate, applied BEFORE the value is allowed near a KV key. It is
 * not the real check — that is "must be an address of a live device", below —
 * it only stops absurd input from becoming a key name.
 */
function looksLikeIp(ip) {
  return !!ip && ip.length <= MAX_IP_LENGTH && /^[0-9a-f.:%]+$/.test(ip) && /[.:]/.test(ip);
}

/**
 * Ban an address. The address MUST currently belong to a tagged device: free
 * text from the client is rejected with 400, so the operator can only ever ban
 * something the API just told us exists. Then sweep immediately — the ban is
 * worthless until the device holding it is gone, and waiting up to a minute for
 * the next cron tick is not acceptable when someone is being removed.
 */
async function handleAdminBanIp(session, env, body) {
  const ip = normalizeIp(body && body.ip);
  if (!looksLikeIp(ip)) return json(400, { error: 'bad_request' });
  const note = typeof (body && body.note) === 'string' ? body.note.trim().slice(0, 500) : '';

  const access = await tailscaleAccessToken(env);
  if (!access) return json(502, { error: 'tailscale' });
  const devices = await tailscaleDevices(env, access);
  if (!devices) return json(502, { error: 'tailscale' });

  const owner = devices.find((d) => deviceAddresses(d).includes(ip));
  if (!owner) return json(400, { error: 'unknown_ip' });

  // Display only — what the operator saw when they clicked, so the Bans list
  // reads as something other than a wall of numbers.
  const name = hostNameSegment(owner.hostname) || owner.hostname || owner.nodeId || owner.id || ip;
  const record = { ip, name: String(name), bannedBy: session.name, ts: Date.now() };
  if (note) record.note = note;
  // No TTL — an IP ban sticks until it is lifted. Metadata supports one-time
  // migration from deployments that predate the compact read index.
  await Promise.all([
    env.DB.put(`banip:${ip}`, JSON.stringify(record), { metadata: banIpMetadata(record) }),
    upsertRecordIndex(env, BAN_IP_INDEX, record, MAX_BANS, 'ip'),
  ]);

  // `devices` was read before the put, which is exactly the list we want to
  // sweep, and reusing it saves a subrequest.
  const kicked = await sweepBannedIps(env, access, devices);
  return json(200, { ok: true, kicked });
}

async function handleAdminUnbanIp(env, body) {
  const ip = normalizeIp(body && body.ip);
  if (!looksLikeIp(ip)) return json(400, { error: 'bad_request' });
  await Promise.all([
    env.DB.delete(`banip:${ip}`),
    removeRecordFromIndex(env, BAN_IP_INDEX, ip, MAX_BANS, 'ip'),
  ]);
  return json(200, { ok: true });
}

/** A device's addresses, normalized for comparison. */
function deviceAddresses(device) {
  const list = device && Array.isArray(device.addresses) ? device.addresses : [];
  return list.map(normalizeIp).filter(Boolean);
}

/**
 * THE enforcement mechanism for IP bans: delete every tagged device holding a
 * banned address. Returns how many devices were removed.
 *
 * Called from three places — the cron trigger (standing enforcement), the top
 * of /admin/api/state (self-healing while the panel is open), and immediately
 * after a ban (instant removal). Everything here is non-fatal: a failure is
 * logged and reported as 0 so it can never take down a panel refresh or a login.
 *
 * `access` and `devices` may be passed in by a caller that already has them;
 * both are fetched lazily otherwise, and NEITHER is fetched when the ban list
 * is empty — which is the common case on every cron tick.
 */
async function sweepBannedIps(env, access, devices) {
  try {
    if (!env || !env.DB) return 0;
    const banned = await listBannedIpAddresses(env);
    if (!banned.size) return 0;
    const token = access || (await tailscaleAccessToken(env));
    if (!token) {
      console.error('sweep: no tailscale access token');
      return 0;
    }
    const live = devices || (await tailscaleDevices(env, token));
    if (!live) return 0;
    let kicked = 0;
    for (const d of live) {
      if (!deviceAddresses(d).some((a) => banned.has(a))) continue;
      if (await tailscaleDeleteDevice(token, d.nodeId || d.id)) kicked++;
    }
    return kicked;
  } catch (err) {
    console.error('sweepBannedIps failed:', err && err.stack ? err.stack : String(err));
    return 0;
  }
}

async function handleAdminKick(env, body) {
  const deviceId = String(body.deviceId || '').trim();
  if (!deviceId || deviceId.length > 200) return json(400, { error: 'bad_request' });
  const access = await tailscaleAccessToken(env);
  if (!access) return json(502, { error: 'tailscale' });
  const ok = await tailscaleDeleteDevice(access, deviceId);
  return json(200, { ok });
}

/**
 * Kick a PLAYER (as opposed to /admin/api/kick, which kicks one device the
 * operator is looking at): remove every device currently wearing that player's
 * declared name, and nothing else. No ban is written, so they can reconnect —
 * that is the whole point of having Kick beside Ban on Recent players.
 *
 * It resolves the player and matches devices through the SAME two helpers the
 * account ban uses (newestMintFor + kickDevicesByName), so a kick and a ban can
 * never disagree about which devices belong to someone.
 *
 * A player with no ledger row, or one who never declared a name, is a clean
 * `{ ok: true, kicked: 0 }` — there is nothing to match on, and that costs no
 * Tailscale call at all.
 */
async function handleAdminKickUser(env, body) {
  const userId = String((body && body.userId) || '').trim();
  if (!/^\d{5,25}$/.test(userId)) return json(400, { error: 'bad_request' });

  const newest = await newestMintFor(env, userId);
  const declared = newest && newest.name;
  if (!declared) return json(200, { ok: true, kicked: 0 });

  const access = await tailscaleAccessToken(env);
  if (!access) return json(502, { error: 'tailscale' });
  const kicked = await kickDevicesByName(env, access, declared);
  return json(200, { ok: true, kicked });
}

async function handleAdminKickAll(env) {
  const access = await tailscaleAccessToken(env);
  if (!access) return json(502, { error: 'tailscale' });
  const devices = await tailscaleDevices(env, access);
  if (!devices) return json(502, { error: 'tailscale' });
  let kicked = 0;
  for (const d of devices) {
    if (await tailscaleDeleteDevice(access, d.nodeId || d.id)) kicked++;
  }
  return json(200, { ok: true, kicked });
}

// --- Hostname <-> name ------------------------------------------------------
//
// The launcher names its mesh device `atlas-lobby--<nameSlug>`, where nameSlug
// is the declared name run through the same slug rule below. That link is how
// the panel says "online" and how a ban ends the current session. It is a CLAIM,
// not proof: the hostname is client-controlled. Nothing that costs the listed
// user anything may depend on it — bans key on the Discord account.

/**
 * Lowercase a value into the DNS-label-safe slug the launcher builds hostnames
 * from (`[a-z0-9-]`, no leading/trailing or doubled hyphens). Mirrors
 * `slugify` in atlas_link_flutter/lib/tailscale_mesh.dart — keep them in step.
 */
function slugify(input, maxLen = 24) {
  let out = '';
  let lastHyphen = false;
  for (const ch of String(input == null ? '' : input).toLowerCase()) {
    if (ch >= 'a' && ch <= 'z') {
      out += ch;
      lastHyphen = false;
    } else if (ch >= '0' && ch <= '9') {
      out += ch;
      lastHyphen = false;
    } else if (!lastHyphen) {
      out += '-';
      lastHyphen = true;
    }
  }
  if (out.length > maxLen) out = out.slice(0, maxLen);
  return out.replace(/^-+|-+$/g, '');
}

/**
 * `atlas-lobby--<nameSlug>` -> the name segment, or null when the hostname is
 * not an ATLAS device. Tailscale's `-N` dedup tail is kept as-is so colliding
 * names stay distinguishable on screen.
 */
function hostNameSegment(hostname) {
  let host = String(hostname || '').trim().toLowerCase().replace(/\.$/, '');
  // MagicDNS names arrive as `<host>.<tailnet>.ts.net`; keep only the label.
  const dot = host.indexOf('.');
  if (dot !== -1) host = host.slice(0, dot);
  if (!host.startsWith('atlas-')) return null;
  const parts = host.slice('atlas-'.length).split('--');
  if (parts.length !== 2 || !parts[1]) return null;
  return parts[1];
}

/**
 * The slug the launcher would have put in the hostname for this declared name.
 *
 * Mirrors `buildAtlasHostname` in tailscale_mesh.dart, which substitutes
 * `player` when a name slugifies to empty — a fully non-ASCII name, for
 * instance. Without that fallback those players are permanently "offline" here
 * and their account-ban device sweep is a silent no-op.
 *
 * A name that was never declared (null/blank in the ledger) still yields '': we
 * do not know what the launcher used, and guessing `player` would attach some
 * stranger's device to that row.
 */
function nameSlug(name) {
  const raw = String(name == null ? '' : name).trim();
  if (!raw) return '';
  return slugify(raw) || 'player';
}

/** Whether this hostname's name segment is `name` (allowing Tailscale's -N tail). */
function hostMatchesName(hostname, name) {
  const slug = nameSlug(name);
  if (!slug) return false;
  const seg = hostNameSegment(hostname);
  if (!seg) return false;
  if (seg === slug) return true;
  const tail = seg.startsWith(`${slug}-`) ? seg.slice(slug.length + 1) : '';
  return /^\d+$/.test(tail);
}

// --- KV record listing -------------------------------------------------------

/** KV hard-caps metadata at 1024 bytes; leave headroom for the encoder. */
const MINT_METADATA_BUDGET = 900;

const TEXT_ENCODER = new TextEncoder();
const byteLen = (s) => TEXT_ENCODER.encode(String(s)).length;

/**
 * Truncate to at most maxBytes of UTF-8, counting BYTES and never splitting a
 * code point. Slicing by .length would cut multibyte names far harder than
 * needed (or mangle a surrogate pair) — a 4-byte emoji is one byte of budget
 * per `.length` unit but four on the wire.
 */
function trimToBytes(str, maxBytes) {
  const s = String(str);
  if (maxBytes <= 0) return '';
  if (byteLen(s) <= maxBytes) return s;
  let out = '';
  let used = 0;
  for (const ch of s) {
    const n = byteLen(ch);
    if (used + n > maxBytes) break;
    out += ch;
    used += n;
  }
  return out;
}

/**
 * Mirrors a record into KV metadata so listings can read it off a list() page
 * instead of paying one get per key.
 *
 * If metadata ever exceeded the cap KV would reject THE ENTIRE PUT (value
 * included, i.e. the record would simply not be stored), so the unbounded
 * fields get shaved until it fits. `trimOrder` names those fields, least
 * important first; `nullable` fields may be dropped to null, the others are
 * never reduced past one character — an empty name is worse than a short one,
 * since the panel displays it.
 *
 * The whole body is guarded: for mints this runs AFTER a key has already been
 * minted, so a malformed name must never turn a successful login into a 500.
 */
function fitMetadata(record, trimOrder) {
  try {
    const meta = { ...record };
    const size = () => byteLen(JSON.stringify(meta));
    for (let guard = 0; guard < 32 && size() > MINT_METADATA_BUDGET; guard++) {
      const excess = size() - MINT_METADATA_BUDGET;
      let trimmed = false;
      for (const { field, nullable } of trimOrder) {
        const value = meta[field];
        if (typeof value !== 'string' || !value) continue;
        const floor = nullable ? 0 : byteLen(Array.from(value)[0]);
        const target = Math.max(floor, byteLen(value) - excess);
        if (target >= byteLen(value)) continue; // can't shrink this one further
        const next = trimToBytes(value, target);
        meta[field] = nullable ? next || null : next || Array.from(value)[0];
        trimmed = true;
        break;
      }
      if (!trimmed) break; // nothing left to give; KV will reject the put
    }
    return meta;
  } catch (err) {
    console.error('metadata build failed, storing record as-is:', err && err.stack ? err.stack : String(err));
    return { ...record };
  }
}

/** Mint record -> metadata. Display names are the only unbounded fields. */
function mintMetadata(record) {
  return fitMetadata(record, [
    { field: 'discordName', nullable: true },
    { field: 'name', nullable: true },
  ]);
}

/** Ban record -> metadata. The operator-typed note is the biggest field. */
function banMetadata(record) {
  return fitMetadata(record, [
    { field: 'note', nullable: true },
    { field: 'bannedBy', nullable: false },
    { field: 'name', nullable: false },
  ]);
}

/** IP-ban record -> metadata. Same shape; `ip` is bounded and never trimmed. */
function banIpMetadata(record) {
  return fitMetadata(record, [
    { field: 'note', nullable: true },
    { field: 'bannedBy', nullable: false },
    { field: 'name', nullable: false },
  ]);
}

/** How many bans the panel will show. Bans have no TTL, so this is a real cap. */
const MAX_BANS = 500;

/**
 * Normal panel refreshes and cron ticks read these compact indexes with get().
 * list() is reserved for a one-time migration of the existing per-record keys.
 * This matters on Workers Free, where the daily list allowance is far smaller
 * than the read allowance.
 */
const MINT_INDEX = 'index:v1:mints';
const BAN_INDEX = 'index:v1:bans';
const BAN_IP_INDEX = 'index:v1:banips';

function emptyRecordIndex() {
  return { initialized: false, retryAfter: 0, records: [] };
}

async function readRecordIndex(env, key) {
  const raw = await env.DB.get(key);
  if (!raw) return emptyRecordIndex();
  try {
    const parsed = JSON.parse(raw);
    return {
      initialized: parsed && parsed.initialized === true,
      retryAfter: Number(parsed && parsed.retryAfter) || 0,
      records: parsed && Array.isArray(parsed.records) ? parsed.records : [],
    };
  } catch (err) {
    console.error('record index parse failed:', key, err && err.stack ? err.stack : String(err));
    return emptyRecordIndex();
  }
}

async function writeRecordIndex(env, key, state) {
  await env.DB.put(key, JSON.stringify({
    initialized: state.initialized === true,
    retryAfter: Number(state.retryAfter) || 0,
    records: state.records,
  }));
}

function normalizeIndexedRecords(records, cap, idField, maxAgeMs) {
  const cutoff = maxAgeMs ? Date.now() - maxAgeMs : 0;
  const valid = (records || []).filter((record) =>
    record && typeof record === 'object' && record[idField]
      && (!cutoff || (Number(record.ts) || 0) >= cutoff));
  valid.sort((a, b) => (Number(b.ts) || 0) - (Number(a.ts) || 0));
  const seen = new Set();
  const out = [];
  for (const record of valid) {
    const id = String(record[idField]);
    if (seen.has(id)) continue;
    seen.add(id);
    out.push(record);
    if (out.length >= cap) break;
  }
  return out;
}

function nextUtcReset() {
  const now = new Date();
  return Date.UTC(now.getUTCFullYear(), now.getUTCMonth(), now.getUTCDate() + 1, 0, 1);
}

function isDailyListLimit(err) {
  const message = String(err && err.message ? err.message : err).toLowerCase();
  return message.includes('list() limit exceeded') || message.includes('list limit exceeded');
}

/**
 * Read an index. Old deployments have no index, so the first successful read
 * imports their prefixed keys once. When the daily list allowance is already
 * exhausted, remember that until the UTC reset and serve whatever is indexed;
 * the live Tailscale device list must never fail with the history store.
 */
async function loadRecordIndex(env, key, cap, idField, maxAgeMs, legacyLoader) {
  const state = await readRecordIndex(env, key);
  state.records = normalizeIndexedRecords(state.records, cap, idField, maxAgeMs);
  if (state.initialized) return { records: state.records, degraded: false };
  if (state.retryAfter > Date.now()) return { records: state.records, degraded: true };

  try {
    const legacy = await legacyLoader();
    state.records = normalizeIndexedRecords([...state.records, ...legacy], cap, idField, maxAgeMs);
    state.initialized = true;
    state.retryAfter = 0;
    await writeRecordIndex(env, key, state);
    return { records: state.records, degraded: false };
  } catch (err) {
    console.error('record index migration deferred:', key, err && err.stack ? err.stack : String(err));
    state.retryAfter = isDailyListLimit(err) ? nextUtcReset() : Date.now() + 5 * 60 * 1000;
    try {
      await writeRecordIndex(env, key, state);
    } catch (writeErr) {
      console.error('record index retry marker failed:', key,
        writeErr && writeErr.stack ? writeErr.stack : String(writeErr));
    }
    return { records: state.records, degraded: true };
  }
}

async function upsertRecordIndex(env, key, record, cap, idField, maxAgeMs) {
  const state = await readRecordIndex(env, key);
  state.records = normalizeIndexedRecords([record, ...state.records], cap, idField, maxAgeMs);
  await writeRecordIndex(env, key, state);
}

async function removeRecordFromIndex(env, key, id, cap, idField) {
  const state = await readRecordIndex(env, key);
  state.records = normalizeIndexedRecords(
    state.records.filter((record) => String(record && record[idField]) !== String(id)),
    cap,
    idField,
  );
  await writeRecordIndex(env, key, state);
}

async function loadMintRecords(env, cap) {
  return loadRecordIndex(
    env,
    MINT_INDEX,
    cap,
    'id',
    7 * 86400 * 1000,
    () => listMintRecordsLegacy(env, cap),
  );
}

async function listMintRecordsFast(env, cap) {
  return (await loadMintRecords(env, cap)).records;
}

async function listMintRecordsLegacy(env, cap) {
  const records = [];
  let cursor;
  for (;;) {
    const remaining = cap - records.length;
    if (remaining <= 0) return records;
    const page = await env.DB.list({
      prefix: 'mint:',
      ...(cursor ? { cursor } : {}),
      limit: Math.min(1000, Math.max(10, remaining)),
    });
    for (const k of page.keys) {
      if (!k.metadata || !k.metadata.id) continue;
      records.push(k.metadata);
      if (records.length >= cap) return records;
    }
    if (page.list_complete) return records;
    cursor = page.cursor;
  }
}

/**
 * How many legacy (pre-metadata) records a single listing may fall back to
 * fetching. Every DB.get is a subrequest and the free tier caps ONE request at
 * 50 of them, so this stays small: without it, an operator with a few dozen
 * bans blew the ceiling and /admin/api/state 500'd — the panel died exactly
 * when they had been banning people. New records all carry metadata, so this
 * budget only ever covers the tail of old ones.
 */
const LEGACY_GET_BUDGET = 20;

async function listBanRecords(env) {
  return (await loadBanRecords(env)).records;
}

async function listBannedIpRecords(env) {
  return (await loadBannedIpRecords(env)).records;
}

async function loadBanRecords(env) {
  return loadRecordIndex(
    env,
    BAN_INDEX,
    MAX_BANS,
    'id',
    0,
    () => listRecordsLegacy(env, 'ban:', MAX_BANS, 'id'),
  );
}

async function loadBannedIpRecords(env) {
  return loadRecordIndex(
    env,
    BAN_IP_INDEX,
    MAX_BANS,
    'ip',
    0,
    () => listRecordsLegacy(env, 'banip:', MAX_BANS, 'ip'),
  );
}

/**
 * Records read off KV list pages via the metadata mirror — ONE subrequest per
 * page instead of one get per key. `idField` is the field that proves a
 * metadata blob is a real record of this kind.
 *
 * Newest first: both ban kinds carry `ts`, so the result is sorted at the end
 * rather than relying on key order (ban keys sort by id/address, not by time).
 */
async function listRecordsLegacy(env, prefix, cap, idField) {
  const records = [];
  let legacyBudget = LEGACY_GET_BUDGET;
  let cursor;
  for (;;) {
    const remaining = cap - records.length;
    if (remaining <= 0) break;
    // KV list pages can be EMPTY with more remaining — keep looping on
    // list_complete/cursor, not on keys.length. (limit floor is 10.)
    const page = await env.DB.list({
      prefix,
      ...(cursor ? { cursor } : {}),
      limit: Math.min(1000, Math.max(10, remaining)),
    });
    const legacy = [];
    for (const k of page.keys) {
      if (records.length + legacy.length >= cap) break;
      if (k.metadata && k.metadata[idField]) {
        records.push(k.metadata);
      } else if (legacyBudget > 0) {
        legacyBudget--;
        legacy.push(k.name);
      }
      // Beyond the budget a legacy record is simply not shown, which is far
      // better than 500-ing the whole panel.
    }
    if (legacy.length) {
      const values = await Promise.all(legacy.map((name) => env.DB.get(name)));
      for (const raw of values) {
        if (!raw) continue;
        try {
          records.push(JSON.parse(raw));
        } catch {
          // ignore a corrupt record rather than failing the whole listing
        }
      }
    }
    if (page.list_complete) break;
    cursor = page.cursor;
  }
  records.sort((a, b) => (Number(b && b.ts) || 0) - (Number(a && a.ts) || 0));
  return records.slice(0, cap);
}

/**
 * Just the banned addresses, for the sweep. The address IS the key suffix, so
 * this needs neither a get nor the metadata mirror — it works even for a record
 * written before metadata existed, which matters because this list is what
 * actually removes people.
 */
async function listBannedIpAddresses(env) {
  const state = await loadBannedIpRecords(env);
  return new Set(state.records.map((record) => normalizeIp(record.ip)).filter(Boolean));
}

// --- Discord helpers --------------------------------------------------------

async function discordExchangeCode(code, env, redirectUri) {
  const body = new URLSearchParams({
    client_id: env.DISCORD_CLIENT_ID,
    client_secret: env.DISCORD_CLIENT_SECRET,
    grant_type: 'authorization_code',
    code,
    redirect_uri: redirectUri,
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

/** Returns { id, username, global_name, ... } or null on error. */
async function discordUser(accessToken) {
  const res = await fetch(`${DISCORD_API}/users/@me`, {
    headers: { authorization: `Bearer ${accessToken}` },
  });
  if (!res.ok) {
    console.error('discord user lookup failed:', res.status, await safeText(res));
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
 * Returns the key string or null.
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

/** Lists the tailnet's devices, filtered down to the ATLAS mesh tag. */
async function tailscaleDevices(env, access) {
  const tailnet = (env.TAILSCALE_TAILNET || '-').trim();
  const tag = (env.TAILSCALE_TAG || 'tag:atlas-mesh').trim();
  const res = await fetch(`${TAILSCALE_API}/tailnet/${encodeURIComponent(tailnet)}/devices`, {
    headers: { authorization: `Bearer ${access}` },
  });
  if (!res.ok) {
    console.error('tailscale device list failed:', res.status, await safeText(res));
    return null;
  }
  const data = await res.json();
  const all = Array.isArray(data.devices) ? data.devices : [];
  return all.filter((d) => Array.isArray(d.tags) && d.tags.includes(tag));
}

/**
 * Removes one device from the tailnet. Note the endpoint is /device/<id>, NOT
 * nested under /tailnet/. A failed delete is logged and reported as false so
 * bulk operations can keep going.
 */
async function tailscaleDeleteDevice(access, deviceId) {
  const res = await fetch(`${TAILSCALE_API}/device/${encodeURIComponent(deviceId)}`, {
    method: 'DELETE',
    headers: { authorization: `Bearer ${access}` },
  });
  if (!res.ok) {
    console.error('tailscale device delete failed:', deviceId, res.status, await safeText(res));
    return false;
  }
  return true;
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

// --- Loopback redirect + small HTML/JSON helpers ---------------------------

function loopbackRedirect(port, params) {
  // The port reaches us inside a signed token, but re-validate anyway: a bad
  // value would otherwise make new URL() throw deep inside a handler and turn a
  // clean error report into a generic 500.
  const p = String(port == null ? '' : port).trim();
  if (!/^\d{1,5}$/.test(p) || Number(p) < 1 || Number(p) > 65535) {
    return html(400, page('Bad request', 'Missing or invalid launcher port.'));
  }
  const target = new URL(`http://127.0.0.1:${p}/`);
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

function json(status, body) {
  return new Response(JSON.stringify(body), {
    status,
    headers: { 'content-type': 'application/json; charset=utf-8' },
  });
}

async function readJson(request) {
  try {
    return await request.json();
  } catch {
    return null;
  }
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

// --- Admin pages (static — all data arrives via /admin/api/state) -----------

function adminLandingPage() {
  return `<!doctype html><html><head><meta charset="utf-8">
<meta name="viewport" content="width=device-width, initial-scale=1">
<title>ATLAS Network Admin Panel</title>
<link rel="icon" href="${ATLAS_LOGO}">
<style>
  body{margin:0;background:#0b1220;color:#e6edf6;font:15px/1.5 system-ui,Segoe UI,Roboto,sans-serif;
       display:flex;min-height:100vh;align-items:center;justify-content:center}
  .card{max-width:420px;padding:32px;text-align:center}
  .logo{display:block;width:88px;max-width:100%;height:auto;margin:0 auto 18px}
  h1{font-size:20px;margin:0 0 10px}
  p{opacity:.7;margin:0 0 22px}
  a{display:inline-flex;align-items:center;justify-content:center;gap:9px;background:#5865f2;color:#fff;
    text-decoration:none;font-weight:600;padding:10px 22px;border-radius:999px}
  a .dmark{flex:none}
</style></head>
<body><div class="card">
<img class="logo" src="${ATLAS_LOGO}" width="192" height="185" alt="ATLAS">
<h1>ATLAS Network Admin Panel</h1>
<p>Only admins are allowed past this point. Sign in with a Discord account on the whitelist to have network management privileges.</p>
<a href="/admin/login">${discordMark(19)}<span>Log in with Discord</span></a></div></body></html>`;
}

/**
 * The panel itself. Deliberately static + self-contained (inline CSS/JS, zero
 * external requests); every piece of dynamic content is inserted through
 * createElement/textContent, never innerHTML, so API data can't inject markup.
 *
 * Sections run live -> history -> enforcement -> nuclear, which is the order
 * the operator works in mid-event:
 *   1. Online now      — who is on the mesh this second. The primary list.
 *   2. Recent players  — the login ledger (people, not devices).
 *   3. Bans            — ONE list holding banned players AND banned addresses.
 *   4. Danger zone     — kick everyone.
 *
 * There are exactly two verbs anywhere in this page, and they mean one thing
 * each: KICK removes someone now and they can reconnect; BAN removes them now
 * and stops them coming back, reversed by UNBAN. Nothing is called "blocking".
 */
function adminPanelPage() {
  return `<!doctype html><html><head><meta charset="utf-8">
<meta name="viewport" content="width=device-width, initial-scale=1">
<title>ATLAS Network Admin Panel</title>
<link rel="icon" href="${ATLAS_LOGO}">
<style>
  *{box-sizing:border-box}
  body{margin:0;background:#0b1220;color:#e6edf6;font:15px/1.5 system-ui,Segoe UI,Roboto,sans-serif;
       -webkit-text-size-adjust:100%}
  .wrap{max-width:760px;margin:0 auto;padding:24px 16px 64px}

  /* Header ---------------------------------------------------------------- */
  header{display:flex;align-items:center;justify-content:space-between;gap:10px 16px;
         margin-bottom:20px;flex-wrap:wrap}
  h1{font-size:19px;font-weight:600;margin:0;display:flex;align-items:center;gap:10px;min-width:0}
  h1 .logo{width:34px;height:auto;flex:none}
  h1 span{min-width:0;overflow-wrap:anywhere}
  .hright{display:flex;align-items:center;gap:8px 12px;flex-wrap:wrap;font-size:13px;min-width:0}
  /* Avatar + name are ONE unit: they wrap together and stay vertically centred
     against each other, so the face never detaches from the name it labels. */
  .whobox{display:flex;align-items:center;gap:8px;min-width:0}
  /* Hidden until the bytes actually decode. /admin/avatar always answers with an
     image, but a session that expired between page load and this request answers
     401 — and a broken-image icon in the header is worse than no avatar. */
  #avatar{display:none;width:22px;height:22px;border-radius:50%;flex:none;
          background:#1e2a44;object-fit:cover}
  #avatar.ok{display:block}
  #who{opacity:.7;min-width:0;overflow-wrap:anywhere}
  #who b{font-weight:600;opacity:1;color:#e6edf6}
  /* The log-out control reads as a button, not a stray link, so the header has
     one obvious affordance instead of a word floating next to the admin name. */
  header a.btnlink{color:#e6edf6;text-decoration:none;flex:none;font-size:13px;
        padding:6px 14px;border-radius:999px;border:1px solid #2b3b5e;background:#182338}
  header a.btnlink:hover{background:#20304e;border-color:#3b4f78}

  /* Sections -------------------------------------------------------------- */
  .card{background:#121a2c;border:1px solid #1e2a44;border-radius:12px;padding:14px 18px 4px;
        margin-bottom:14px}
  .card.plain{padding-bottom:18px}
  .shead{display:flex;align-items:baseline;justify-content:space-between;gap:12px;
         padding-bottom:10px;border-bottom:1px solid #1e2a44}
  h2{font-size:15px;font-weight:600;margin:0;min-width:0;overflow-wrap:anywhere}
  .count{font-size:13px;color:#8ab4ff;opacity:.7;font-variant-numeric:tabular-nums;flex:none}

  /* Rows ------------------------------------------------------------------ */
  .row{display:flex;flex-wrap:wrap;align-items:center;gap:10px 12px;padding:12px 0;
       border-top:1px solid #1e2a44}
  .row:first-child{border-top:0}
  /* The basis is the knob that decides when a row wraps: at ~390px there is
     still room for the text and the buttons side by side, and below that the
     button group drops beneath the text rather than being squeezed. */
  .grow{flex:1 1 150px;min-width:0}
  .name{font-size:16px;font-weight:600;line-height:1.35;display:flex;align-items:center;
        flex-wrap:wrap;gap:6px 8px;overflow-wrap:anywhere}
  .dot{width:8px;height:8px;border-radius:50%;background:#4ade80;flex:none}
  .sub{opacity:.55;font-size:13px;overflow-wrap:anywhere}
  .sub.tie{opacity:.95;color:#fbbf24}
  .mono{font-family:ui-monospace,SFMono-Regular,Menlo,Consolas,monospace}
  .chip{font-size:10px;font-weight:700;letter-spacing:.08em;text-transform:uppercase;
        color:#8ab4ff;background:#16223a;border:1px solid #24334f;border-radius:999px;
        padding:2px 8px;white-space:nowrap;flex:none}

  /* Actions --------------------------------------------------------------- */
  .btns{display:flex;gap:8px;flex:none;margin-left:auto}
  button{font:inherit;font-size:13px;font-weight:600;line-height:1;padding:9px 16px;
         border-radius:999px;border:1px solid #2b3b5e;background:#182338;color:#e6edf6;
         cursor:pointer;white-space:nowrap;flex:none}
  button:hover:enabled{background:#20304e;border-color:#3a4f7a}
  button.danger{color:#ff6b6b;border-color:#5c1d27;background:#2a1218}
  /* Hover brightens the outline as well as the fill — a destructive control
     should announce itself before it is clicked, not just tint slightly. */
  button.danger:hover:enabled{background:#3a1720;border-color:#ff6b6b}
  button:disabled{opacity:.35;cursor:not-allowed}

  .empty{opacity:.5;font-size:13px;padding:12px 0}
  .note{opacity:.55;font-size:13px;margin:12px 0 14px}
  .card a{color:#8ab4ff}
  #status{position:fixed;left:50%;bottom:18px;transform:translateX(-50%);background:#182338;
          border:1px solid #2b3b5e;padding:8px 16px;border-radius:999px;font-size:13px;
          opacity:0;transition:opacity .2s;pointer-events:none;max-width:calc(100vw - 32px)}
  #status.show{opacity:1}

  /* Modal ----------------------------------------------------------------- */
  /* ONE dialog serves every destructive action, so there is exactly one place
     where a confirmation can be styled, focused or mis-worded. Same card
     surface, border and radius as the sections behind it. */
  #backdrop{position:fixed;inset:0;background:rgba(4,9,20,.68);display:none;
            align-items:center;justify-content:center;padding:16px;z-index:10}
  #backdrop.open{display:flex}
  .modal{background:#121a2c;border:1px solid #1e2a44;border-radius:12px;
         padding:18px;width:100%;max-width:420px;max-height:calc(100vh - 32px);
         overflow-y:auto;box-shadow:0 18px 50px rgba(0,0,0,.55)}
  .modal h3{font-size:16px;font-weight:600;margin:0 0 8px;overflow-wrap:anywhere}
  .mbody p{font-size:13px;opacity:.7;margin:0 0 6px;overflow-wrap:anywhere}
  /* The identity detail that used to live in the Recent Players sub-line: shown
     only when it is load-bearing, i.e. two rows share a name. */
  .mbody p.detail{opacity:.95;color:#fbbf24}
  .modal label{display:block;font-size:13px;opacity:.7;margin:12px 0 6px}
  .modal input{font:inherit;font-size:13px;width:100%;padding:9px 12px;border-radius:8px;
               border:1px solid #2b3b5e;background:#0f1626;color:#e6edf6}
  .modal input:focus{outline:2px solid #8ab4ff;outline-offset:1px;border-color:#3a4f7a}
  /* Wraps rather than overflows: at 320px the two buttons stack instead of
     pushing the dialog wider than the viewport. */
  .mbtns{display:flex;flex-wrap:wrap;justify-content:flex-end;gap:8px;margin-top:16px}
</style></head>
<body>
<div class="wrap">
  <header>
    <h1><img class="logo" src="${ATLAS_LOGO}" width="192" height="185" alt=""><span>ATLAS Network Admin Panel</span></h1>
    <div class="hright">
      <span class="whobox"><img id="avatar" src="/admin/avatar" width="22" height="22" alt=""><span id="who"></span></span><a class="btnlink" href="/admin/logout">Log Out</a>
    </div>
  </header>
  <main id="main">
    <section class="card">
      <div class="shead"><h2>Online Now</h2><span class="count" id="devices-count"></span></div>
      <div id="devices"></div>
    </section>
    <section class="card">
      <div class="shead"><h2>Recent Players</h2><span class="count" id="players-count"></span></div>
      <div id="players"></div>
    </section>
    <section class="card">
      <div class="shead"><h2>Bans</h2><span class="count" id="bans-count"></span></div>
      <div id="bans"></div>
    </section>
    <section class="card plain">
      <div class="shead"><h2>Danger Zone</h2></div>
      <p class="note">Removes every ATLAS device from the mesh at once.</p>
      <button class="danger" id="kickall">Kick Everyone</button>
    </section>
  </main>
</div>
<div id="status"></div>
<div id="backdrop"></div>
<script>
(function () {
  'use strict';
  var timer = null;
  var busy = false;
  var statusTimer = null;

  function $(id) { return document.getElementById(id); }

  function el(tag, cls, text) {
    var n = document.createElement(tag);
    if (cls) n.className = cls;
    if (text !== undefined && text !== null) n.textContent = text;
    return n;
  }

  function clear(node) { while (node.firstChild) node.removeChild(node.firstChild); }

  // THE relative-time formatter — the only one on the page. Takes epoch ms (ban
  // and login timestamps) or an ISO string (Tailscale's lastSeen), so no caller
  // has to pre-parse and invent a second format on the way.
  // Tailscale reports the OS lower-cased ("windows", "macOS", "ios"). Present it
  // the way the platform spells itself rather than blindly capitalising.
  var OS_NAMES = { windows: 'Windows', linux: 'Linux', macos: 'macOS', ios: 'iOS',
                   android: 'Android', freebsd: 'FreeBSD', openbsd: 'OpenBSD' };
  function osLabel(os) {
    var key = String(os || '').toLowerCase();
    if (OS_NAMES[key]) return OS_NAMES[key];
    return key ? key.charAt(0).toUpperCase() + key.slice(1) : '';
  }

  function ago(value) {
    var t = typeof value === 'number' ? value : Date.parse(value);
    if (!isFinite(t) || t <= 0) return 'a while ago';
    var s = Math.round((Date.now() - t) / 1000);
    if (s < 90) return 'just now';
    var m = Math.round(s / 60);
    if (m < 60) return m + ' min ago';
    var h = Math.round(m / 60);
    if (h < 36) return h + (h === 1 ? ' hour ago' : ' hours ago');
    var d = Math.round(h / 24);
    return d + (d === 1 ? ' day ago' : ' days ago');
  }

  // Every toast that reports a removal counts devices the same way.
  function nDevices(n) {
    var c = Number(n) || 0;
    return c + (c === 1 ? ' device' : ' devices');
  }

  function displayName(p) { return p.name || p.discordName || p.id; }

  // Duplicate-name detection compares NORMALIZED names, so "Cipher" and
  // "cipher " are recognised as the same person trying to be two rows.
  function nameKey(s) { return String(s === null || s === undefined ? '' : s).trim().toLowerCase(); }

  function setStatus(msg) {
    var s = $('status');
    s.textContent = msg;
    s.className = 'show';
    clearTimeout(statusTimer);
    statusTimer = setTimeout(function () { s.className = ''; }, 4000);
  }

  // --- THE confirmation dialog ---------------------------------------------
  //
  // One component, every destructive action. There is no confirm() and no
  // prompt() anywhere on this page: the note is a field INSIDE this dialog, so
  // a ban is one decision on one screen instead of two stacked browser popups.
  //
  // It is assembled with createElement/textContent like everything else here,
  // so a player who names themselves after a <script> tag gets a title, not an
  // injection.

  var openDialog = null; // the live dialog's handle, or null when none is open

  /** Every control the operator can reach inside the dialog, in tab order. */
  function dialogFocusables(root) {
    return Array.prototype.filter.call(
      root.querySelectorAll('input, button'),
      function (n) { return !n.disabled; },
    );
  }

  function closeDialog(confirmed, note) {
    var d = openDialog;
    if (!d) return;
    openDialog = null;
    document.removeEventListener('keydown', d.onKeydown, true);
    var back = $('backdrop');
    back.onclick = null;
    back.className = '';
    clear(back);
    // Focus goes back where it came from, so a cancelled action leaves the
    // operator exactly where they were in the list.
    if (d.trigger && d.trigger.isConnected) d.trigger.focus();
    if (confirmed && d.onConfirm) d.onConfirm(note);
  }

  /**
   * Open the dialog.
   *   title      heading text ("Ban someone?")
   *   lines      [{ text, cls }] body paragraphs
   *   confirm    label for the confirm button
   *   danger     true -> confirm button wears the destructive styling
   *   note       true -> optional note field (ban actions only)
   *   typed      word the operator must type before confirm enables
   *   trigger    the button that opened this; focus returns to it on close
   *   onConfirm  function(note)
   */
  function openDialogWith(o) {
    if (openDialog) return; // never two at once
    var back = $('backdrop');
    clear(back);

    var root = el('div', 'modal');
    root.setAttribute('role', 'dialog');
    root.setAttribute('aria-modal', 'true');
    root.setAttribute('aria-labelledby', 'mtitle');
    root.setAttribute('aria-describedby', 'mbody');

    var heading = el('h3', null, o.title);
    heading.id = 'mtitle';
    root.appendChild(heading);

    var body = el('div', 'mbody');
    body.id = 'mbody';
    (o.lines || []).forEach(function (line) {
      if (line && line.text) body.appendChild(el('p', line.cls || null, line.text));
    });
    root.appendChild(body);

    var noteInput = null;
    if (o.note) {
      var noteLabel = el('label', null, 'Note (optional)');
      noteLabel.htmlFor = 'mnote';
      root.appendChild(noteLabel);
      noteInput = el('input');
      noteInput.id = 'mnote';
      noteInput.type = 'text';
      noteInput.maxLength = 500;
      noteInput.autocomplete = 'off';
      root.appendChild(noteInput);
    }

    var typedInput = null;
    if (o.typed) {
      var typedLabel = el('label', null, 'Type ' + o.typed + ' to confirm');
      typedLabel.htmlFor = 'mtype';
      root.appendChild(typedLabel);
      typedInput = el('input');
      typedInput.id = 'mtype';
      typedInput.type = 'text';
      typedInput.autocomplete = 'off';
      typedInput.spellcheck = false;
      root.appendChild(typedInput);
    }

    var btns = el('div', 'mbtns');
    var cancel = el('button', null, 'Cancel');
    cancel.type = 'button';
    cancel.onclick = function () { closeDialog(false); };
    btns.appendChild(cancel);
    var ok = el('button', o.danger ? 'danger' : null, o.confirm);
    ok.type = 'button';
    btns.appendChild(ok);
    root.appendChild(btns);

    function submit() {
      if (ok.disabled) return;
      closeDialog(true, noteInput ? noteInput.value.trim() : '');
    }
    ok.onclick = submit;

    // The typed safeguard: the confirm button is genuinely inert (not merely
    // grey) until the exact word is present.
    if (typedInput) {
      ok.disabled = true;
      typedInput.oninput = function () { ok.disabled = typedInput.value.trim() !== o.typed; };
    }

    function onKeydown(e) {
      if (e.key === 'Escape') { e.preventDefault(); closeDialog(false); return; }
      if (e.key === 'Enter') {
        // A focused button already activates on Enter; intercepting here as well
        // would fire Cancel and then confirm the action it just cancelled.
        if (e.target && e.target.tagName === 'BUTTON') return;
        if (ok.disabled) return;
        e.preventDefault();
        submit();
        return;
      }
      if (e.key !== 'Tab') return;
      // Focus trap: Tab cycles inside the dialog and cannot reach the page
      // behind it, which is still there and still scrollable to a screen reader
      // otherwise.
      var list = dialogFocusables(root);
      if (!list.length) return;
      var first = list[0];
      var last = list[list.length - 1];
      var active = document.activeElement;
      if (!root.contains(active)) {
        e.preventDefault();
        (e.shiftKey ? last : first).focus();
      } else if (e.shiftKey && active === first) {
        e.preventDefault();
        last.focus();
      } else if (!e.shiftKey && active === last) {
        e.preventDefault();
        first.focus();
      }
    }

    back.appendChild(root);
    back.className = 'open';
    // Clicking the dimmed page outside the card cancels, like Esc.
    back.onclick = function (e) { if (e.target === back) closeDialog(false); };
    openDialog = { trigger: o.trigger || null, onConfirm: o.onConfirm, onKeydown: onKeydown };
    document.addEventListener('keydown', onKeydown, true);
    var firstControl = dialogFocusables(root)[0];
    if (firstControl) firstControl.focus();
  }

  function request(path, body) {
    var opts = { credentials: 'same-origin', headers: { 'x-atlas-admin': '1' } };
    if (body !== undefined) {
      opts.method = 'POST';
      opts.headers['content-type'] = 'application/json';
      opts.body = JSON.stringify(body);
    }
    return fetch(path, opts).then(function (res) {
      if (res.status === 401) { loggedOut(); throw new Error('auth'); }
      return res.json();
    });
  }

  function loggedOut() {
    if (timer) { clearInterval(timer); timer = null; }
    // Nothing is refreshing any more, so stop claiming it is.
    var live = $('live');
    if (live) live.style.display = 'none';
    var main = $('main');
    clear(main);
    var card = el('section', 'card plain');
    var head = el('div', 'shead');
    head.appendChild(el('h2', null, 'Signed Out'));
    card.appendChild(head);
    card.appendChild(el('p', 'note', 'Your session expired or was revoked.'));
    var a = el('a', null, 'Log in with Discord');
    a.href = '/admin/login';
    card.appendChild(a);
    main.appendChild(card);
  }

  // --- Row + button construction (every list is built from these) -----------

  function newRow() {
    var row = el('div', 'row');
    var grow = el('div', 'grow');
    var head = el('div', 'name');
    var sub = el('div', 'sub');
    grow.appendChild(head);
    grow.appendChild(sub);
    row.appendChild(grow);
    var btns = el('div', 'btns');
    row.appendChild(btns);
    return { row: row, head: head, sub: sub, btns: btns };
  }

  /**
   * One button shape everywhere. A non-empty reason means the action does not
   * apply right now: the button is greyed and genuinely inert (a disabled
   * <button> fires no click at all) and says why on hover, rather than
   * vanishing and leaving the operator wondering where it went.
   */
  function addButton(btns, label, cls, reason, onclick) {
    var b = el('button', cls || null, label);
    if (reason) {
      b.disabled = true;
      b.title = reason;
    } else {
      b.onclick = onclick;
    }
    btns.appendChild(b);
    return b;
  }

  function setSection(boxId, countId, count) {
    var box = $(boxId);
    clear(box);
    $(countId).textContent = String(count);
    return box;
  }

  function act(path, body, done) {
    if (busy) return;
    busy = true;
    request(path, body).then(function (out) {
      busy = false;
      if (out && out.ok) setStatus(done(out)); else setStatus('Action failed.');
      refresh();
    }, function (err) {
      busy = false;
      if (String(err && err.message) !== 'auth') { setStatus('Request failed.'); refresh(); }
    });
  }

  // --- The two verbs -------------------------------------------------------
  //
  // Every confirmation names its subject and says what happens next; every toast
  // reads "<Verb>ed <subject><detail>." Kick and Ban are asked for the same way
  // whether the subject is a device, a player or an address — through the one
  // dialog above.

  function kickDevice(d, label, trigger) {
    openDialogWith({
      title: 'Kick ' + label + '?',
      lines: [{ text: 'They can reconnect right away.' }],
      confirm: 'Kick',
      danger: true,
      trigger: trigger,
      onConfirm: function () {
        act('/admin/api/kick', { deviceId: d.deviceId }, function () {
          return 'Kicked ' + label + ' (' + nDevices(1) + ').';
        });
      },
    });
  }

  function kickPlayer(p, name, trigger) {
    openDialogWith({
      title: 'Kick ' + name + '?',
      lines: [{ text: 'They can reconnect right away.' }],
      confirm: 'Kick',
      danger: true,
      trigger: trigger,
      onConfirm: function () {
        act('/admin/api/kickuser', { userId: p.id }, function (out) {
          return 'Kicked ' + name + ' (' + nDevices(out.kicked) + ').';
        });
      },
    });
  }

  /**
   * The duplicate flag says this name is on more than one row. That is the moment the
   * Discord account name and the login time earn their place on screen — not in
   * the list, where they were noise on every row, but here, where the operator
   * is one click from removing the wrong person.
   */
  function banPlayer(p, name, duplicate, trigger) {
    var lines = [{ text: 'They will be removed now and blocked from rejoining the ATLAS Network.' }];
    if (duplicate) {
      lines.push({ cls: 'detail', text: 'More than one player in the list uses this name.' });
      var detail = [];
      if (p.discordName) detail.push('Discord account: ' + p.discordName);
      detail.push((p.online ? 'Connected ' : 'Last seen ') + ago(p.ts));
      lines.push({ cls: 'detail', text: detail.join(' · ') });
    }
    openDialogWith({
      title: 'Ban ' + name + '?',
      lines: lines,
      confirm: 'Ban',
      danger: true,
      note: true,
      trigger: trigger,
      onConfirm: function (note) {
        var body = { userId: p.id };
        if (note) body.note = note;
        act('/admin/api/ban', body, function (out) {
          var msg = 'Banned ' + name + ' (' + nDevices(out.kicked) + ' removed).';
          if (out.warning === 'target-is-admin') {
            msg += ' Heads up: this account is on the admin list — remove it from ADMIN_DISCORD_IDS to make that stick.';
          }
          return msg;
        });
      },
    });
  }

  function banIp(ip, trigger) {
    openDialogWith({
      title: 'Ban ' + ip + '?',
      lines: [{ text: 'This address will be removed now and blocked from rejoining.' }],
      confirm: 'Ban',
      danger: true,
      note: true,
      trigger: trigger,
      onConfirm: function (note) {
        var body = { ip: ip };
        if (note) body.note = note;
        act('/admin/api/banip', body, function (out) {
          return 'Banned ' + ip + ' (' + nDevices(out.kicked) + ' removed).';
        });
      },
    });
  }

  function unban(subject, path, body, trigger) {
    openDialogWith({
      title: 'Unban ' + subject + '?',
      lines: [{ text: 'They will be able to join again.' }],
      confirm: 'Unban',
      trigger: trigger,
      onConfirm: function () {
        act(path, body, function () { return 'Unbanned ' + subject + '.'; });
      },
    });
  }

  // --- 1. Online now: who is on the mesh this second -----------------------

  function renderDevices(list) {
    var box = setSection('devices', 'devices-count', list.length);
    if (!list.length) { box.appendChild(el('div', 'empty', 'Nobody is connected right now.')); return; }
    list.forEach(function (d) {
      var label = d.name || d.hostname || d.deviceId;
      var ip = (d.addresses && d.addresses.length) ? d.addresses[0] : '';
      var r = newRow();
      if (d.online) r.head.appendChild(el('span', 'dot'));
      r.head.appendChild(el('span', null, label));
      if (ip) {
        r.sub.appendChild(el('span', 'mono', ip));
        r.sub.appendChild(el('span', null, ' · '));
      }
      var bits = [];
      if (d.os) bits.push(osLabel(d.os));
      bits.push(d.online ? 'Online Now' : 'Last seen ' + ago(d.lastSeen));
      r.sub.appendChild(el('span', null, bits.join(' · ')));
      addButton(r.btns, 'Kick', null, '', function () { kickDevice(d, label, this); });
      // The address is what a ban here keys on, so with no address there is
      // nothing to ban — say so rather than dropping the button.
      addButton(r.btns, 'Ban', 'danger', ip ? '' : 'This device has no address to ban.',
        function () { banIp(ip, this); });
      box.appendChild(r.row);
    });
  }

  // --- 2. Recent players: the login ledger ---------------------------------

  function renderPlayers(players) {
    var box = setSection('players', 'players-count', players.length);
    if (!players.length) { box.appendChild(el('div', 'empty', 'No logins recorded yet.')); return; }
    // A Map, not an object: a player named __proto__ defeats a plain-object
    // counter. Duplicates still get flagged, but the identity detail that used to
    // sit on every sub-line now waits for the ban dialog — see banPlayer.
    var counts = new Map();
    players.forEach(function (p) {
      var k = nameKey(displayName(p));
      counts.set(k, (counts.get(k) || 0) + 1);
    });
    players.forEach(function (p) {
      var name = displayName(p);
      var duplicate = (counts.get(nameKey(name)) || 0) > 1;
      var r = newRow();
      if (p.online) r.head.appendChild(el('span', 'dot'));
      r.head.appendChild(el('span', null, name));
      // Time, and nothing else — plus, when it is true, the reason the row is
      // highlighted. An amber sub-line that explained nothing was worse than no
      // highlight at all.
      var bits = [(p.online ? 'Connected ' : 'Last seen ') + ago(p.ts)];
      if (duplicate) bits.push('Duplicate name');
      r.sub.textContent = bits.join(' · ');
      if (duplicate) r.sub.className = 'sub tie';
      addButton(r.btns, 'Kick', null,
        p.online ? '' : name + ' is not connected right now.',
        function () { kickPlayer(p, name, this); });
      addButton(r.btns, 'Ban', 'danger', '',
        function () { banPlayer(p, name, duplicate, this); });
      box.appendChild(r.row);
    });
  }

  // --- 3. Bans: players AND addresses, one list ----------------------------
  //
  // Two stores on the wire (separate unban routes), one list on screen, because
  // to the operator there is only one question: who is banned? A chip keeps the
  // two kinds apart; both are lifted with the same Unban button.

  function renderBans(bans, bannedIps) {
    var rows = [];
    (bans || []).forEach(function (b) { rows.push({ ip: false, rec: b }); });
    (bannedIps || []).forEach(function (b) { rows.push({ ip: true, rec: b }); });
    rows.sort(function (a, b) { return (Number(b.rec.ts) || 0) - (Number(a.rec.ts) || 0); });

    var box = setSection('bans', 'bans-count', rows.length);
    if (!rows.length) {
      box.appendChild(el('div', 'empty', 'No bans. Nobody is blocked from the network.'));
      return;
    }
    rows.forEach(function (item) {
      var b = item.rec;
      var isIp = item.ip;
      var subject = isIp ? String(b.ip || '') : (b.name || b.id);
      var r = newRow();
      r.head.appendChild(el('span', isIp ? 'mono' : null, subject));
      r.head.appendChild(el('span', 'chip', isIp ? 'IP Address' : 'Player'));
      var bits = [];
      if (isIp && b.name) bits.push(b.name);
      bits.push('banned ' + ago(b.ts) + ' by ' + (b.bannedBy || 'an admin'));
      if (b.note) bits.push(b.note);
      r.sub.textContent = bits.join(' · ');
      addButton(r.btns, 'Unban', null, '', function () {
        if (isIp) unban(subject, '/admin/api/unbanip', { ip: b.ip });
        else unban(subject, '/admin/api/unban', { userId: b.id });
      });
      box.appendChild(r.row);
    });
  }

  function refresh() {
    request('/admin/api/state').then(function (data) {
      if (!data || !data.players) { setStatus('Could not load state.'); return; }
      var who = $('who');
      who.textContent = '';
      if (data.admin) {
        who.appendChild(document.createTextNode('Signed in as: '));
        who.appendChild(el('b', null, data.admin.name || data.admin.id));
      }
      renderDevices(data.devices || []);
      renderPlayers(data.players || []);
      renderBans(data.bans || [], data.bannedIps || []);
      if (data.storageLimited) {
        setStatus('Live controls are available. History will finish recovering after the KV quota resets.');
      }
    }, function (err) {
      if (String(err && err.message) !== 'auth') setStatus('Could not load state.');
    });
  }

  // --- 4. Danger zone ------------------------------------------------------

  $('kickall').onclick = function (ev) {
    openDialogWith({
      title: 'Kick everyone?',
      lines: [{ text: 'Every device is removed from the mesh at once. Anyone not banned can reconnect straight away.' }],
      confirm: 'Kick Everyone',
      danger: true,
      typed: 'KICK',
      trigger: ev && ev.currentTarget,
      onConfirm: function () {
        act('/admin/api/kickall', {}, function (out) {
          return 'Kicked everyone (' + nDevices(out.kicked) + ').';
        });
      },
    });
  };

  timer = setInterval(refresh, 30000);
  refresh();
})();
</script>
</body></html>`;
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
