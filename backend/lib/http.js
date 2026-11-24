// Tiny HTTP helpers shared by every API route.
// Response shape: { ok: true, ...data } on success,
// { ok: false, error: CODE, message } on failure.
function send(res, status, body) {
  res.status(status).setHeader('Content-Type', 'application/json');
  res.end(JSON.stringify(body));
}

function ok(res, data = {}) {
  send(res, 200, { ok: true, ...data });
}

function created(res, data = {}) {
  send(res, 201, { ok: true, ...data });
}

function fail(res, status, code, message) {
  send(res, status, { ok: false, error: code, message });
}

function badRequest(res, message = 'Invalid request') {
  fail(res, 400, 'BAD_REQUEST', message);
}

function unauthorized(res, message = 'Missing or invalid token') {
  fail(res, 401, 'UNAUTHORIZED', message);
}

function forbidden(res, message = 'Forbidden') {
  fail(res, 403, 'FORBIDDEN', message);
}

function notFound(res, message = 'Not found') {
  fail(res, 404, 'NOT_FOUND', message);
}

function serverError(res, err) {
  console.error('[api]', err && err.message ? err.message : err);
  if (err && err.code === 'DB_NOT_CONFIGURED') {
    return fail(res, 500, 'DB_NOT_CONFIGURED', 'Database is not configured on the server.');
  }
  fail(res, 500, 'SERVER_ERROR', 'Something went wrong on the server.');
}

function method(res, req, allowed) {
  if (!allowed.includes(req.method)) {
    res.setHeader('Allow', allowed.join(', '));
    fail(res, 405, 'METHOD_NOT_ALLOWED', `Use ${allowed.join(' or ')}.`);
    return false;
  }
  return true;
}

// Reads a JSON body. Returns {} for an empty body.
async function readJson(req) {
  const chunks = [];
  for await (const chunk of req) chunks.push(chunk);
  const raw = Buffer.concat(chunks).toString('utf8').trim();
  if (!raw) return {};
  return JSON.parse(raw);
}

function isUuid(v) {
  return typeof v === 'string' && /^[0-9a-f]{8}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{12}$/i.test(v);
}

module.exports = {
  send,
  ok,
  created,
  fail,
  badRequest,
  unauthorized,
  forbidden,
  notFound,
  serverError,
  method,
  readJson,
  isUuid,
};
