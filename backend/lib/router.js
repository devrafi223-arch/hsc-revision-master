// Single-function router for the whole API.
//
// Vercel's Hobby plan allows at most 12 Serverless Functions per
// deployment — so every route lives in ONE function
// (api/[...path].js) and is dispatched here. Handlers live in
// lib/routes/ and are plain (req, res) functions; path params (e.g. :id)
// are merged into req.query so handlers read them exactly as they did
// under Vercel's file routing.
//
// Community is gone (Rafi, 2026-11-24): the messages/polls/groups/
// leaderboard/presence routes were deleted with it. The tables still
// exist in Postgres (empty) but nothing routes to them.
const { notFound } = require('./http');

const routes = [
  ['GET', ['api', 'health'], require('./routes/health')],
  ['POST', ['api', 'auth', 'send-code'], require('./routes/auth-send-code')],
  ['POST', ['api', 'auth', 'verify-code'], require('./routes/auth-verify-code')],
  ['GET', ['api', 'auth', 'me'], require('./routes/auth-me')],
  ['GET', ['api', 'notes'], require('./routes/notes')],
  ['POST', ['api', 'notes'], require('./routes/notes')],
  ['GET', ['api', 'users', ':id'], require('./routes/user-get')],
  ['POST', ['api', 'milestones'], require('./routes/milestones')],
  ['GET', ['api', 'admin', 'users'], require('./routes/admin-users')],
  ['DELETE', ['api', 'admin', 'users'], require('./routes/admin-users')],
  ['POST', ['api', 'upload'], require('./routes/upload')],
];

function match(method, segments) {
  for (const [m, pattern, handler] of routes) {
    if (m !== method || pattern.length !== segments.length) continue;
    const params = {};
    let good = true;
    for (let i = 0; i < pattern.length; i++) {
      if (pattern[i].startsWith(':')) {
        params[pattern[i].slice(1)] = decodeURIComponent(segments[i]);
      } else if (pattern[i] !== segments[i]) {
        good = false;
        break;
      }
    }
    if (good) return { handler, params };
  }
  return null;
}

module.exports = function route(req, res) {
  // CORS: the Flutter web app calls this API from the browser, so every
  // response must carry Access-Control headers or the browser blocks the
  // call outright (the app then reports it as "No internet connection").
  // Auth is via Bearer token (no cookies), so `*` is safe here.
  res.setHeader('Access-Control-Allow-Origin', '*');
  res.setHeader('Access-Control-Allow-Methods', 'GET, POST, PUT, PATCH, DELETE, OPTIONS');
  res.setHeader('Access-Control-Allow-Headers', 'Content-Type, Authorization');
  // Preflight: the browser sends OPTIONS before POSTs with a JSON body
  // or an Authorization header. Answer it here, before route matching.
  if (req.method === 'OPTIONS') {
    return res.status(204).end();
  }
  const url = new URL(req.url, 'http://localhost');
  const segments = url.pathname.split('/').filter(Boolean);
  const found = match(req.method, segments);
  if (!found) {
    return notFound(res, `No route for ${req.method} ${url.pathname}.`);
  }
  // Merge URL query params + path params into req.query (handlers read
  // req.query.since / .limit / .id / .key / .filename / .kind ...).
  req.query = { ...Object.fromEntries(url.searchParams.entries()), ...found.params };
  return found.handler(req, res);
};
