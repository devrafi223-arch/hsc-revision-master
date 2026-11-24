// Single-function router for the whole API.
//
// Vercel's Hobby plan allows at most 12 Serverless Functions per
// deployment, and this API has 19 endpoints — so every route lives in ONE
// function (api/[...path].js) and is dispatched here. Handlers live in
// lib/routes/ and are plain (req, res) functions; path params (e.g. :id)
// are merged into req.query so handlers read them exactly as they did
// under Vercel's file routing.
const { notFound } = require('./http');

const routes = [
  ['GET', ['api', 'health'], require('./routes/health')],
  ['POST', ['api', 'auth', 'send-code'], require('./routes/auth-send-code')],
  ['POST', ['api', 'auth', 'verify-code'], require('./routes/auth-verify-code')],
  ['GET', ['api', 'auth', 'me'], require('./routes/auth-me')],
  ['GET', ['api', 'messages'], require('./routes/messages')],
  ['POST', ['api', 'messages'], require('./routes/messages')],
  ['POST', ['api', 'messages', ':id', 'react'], require('./routes/message-react')],
  ['POST', ['api', 'messages', ':id', 'pin'], require('./routes/message-pin')],
  ['POST', ['api', 'messages', ':id', 'report'], require('./routes/message-report')],
  ['GET', ['api', 'polls'], require('./routes/polls')],
  ['POST', ['api', 'polls'], require('./routes/polls')],
  ['POST', ['api', 'polls', ':id', 'vote'], require('./routes/poll-vote')],
  ['GET', ['api', 'groups'], require('./routes/groups')],
  ['POST', ['api', 'groups'], require('./routes/groups')],
  ['POST', ['api', 'groups', 'join'], require('./routes/group-join')],
  ['GET', ['api', 'notes'], require('./routes/notes')],
  ['POST', ['api', 'notes'], require('./routes/notes')],
  ['GET', ['api', 'users', ':id'], require('./routes/user-get')],
  ['GET', ['api', 'leaderboard'], require('./routes/leaderboard')],
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
