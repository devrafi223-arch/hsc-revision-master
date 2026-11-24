// POST /api/auth/verify-code — checks the 6-digit code, returns a JWT.
// Body: { "email": "...", "code": "123456" }
// Success: { ok: true, token, user } — token lives 7 days (Rafi's session rule).
// A code allows at most 5 wrong tries, then it is deleted.
const crypto = require('crypto');
const { query } = require('../db');
const { signToken } = require('../auth');
const { ok, fail, badRequest, method, readJson, serverError } = require('../http');

const MAX_TRIES = 5;

function codeHash(code) {
  return crypto.createHash('sha256').update(code).digest('hex');
}

function safeEqual(a, b) {
  const ba = Buffer.from(a);
  const bb = Buffer.from(b);
  return ba.length === bb.length && crypto.timingSafeEqual(ba, bb);
}

function publicUser(row) {
  return {
    id: row.id,
    email: row.email,
    display_name: row.display_name,
    photo_url: row.photo_url,
    cover_url: row.cover_url,
    bio: row.bio,
    privacy: row.privacy,
    photo_privacy: row.photo_privacy,
    is_admin: row.is_admin,
    streak: row.streak,
    chapters_done: row.chapters_done,
    created_at: row.created_at,
    last_seen_at: row.last_seen_at,
  };
}

module.exports = async (req, res) => {
  if (!method(res, req, ['POST'])) return;
  try {
    const body = await readJson(req);
    const email = typeof body.email === 'string' ? body.email.trim().toLowerCase() : '';
    const code = typeof body.code === 'string' ? body.code.trim() : '';
    if (!email || !/^\d{6}$/.test(code)) {
      return badRequest(res, 'Enter the 6-digit code sent to your email.');
    }

    const { rows } = await query('SELECT * FROM auth_codes WHERE email = $1', [email]);
    if (rows.length === 0) {
      return fail(res, 400, 'CODE_INVALID', 'No code was sent to this email, or it expired. Ask for a new one.');
    }
    const row = rows[0];
    if (new Date(row.expires_at).getTime() < Date.now()) {
      await query('DELETE FROM auth_codes WHERE email = $1', [email]);
      return fail(res, 400, 'CODE_EXPIRED', 'The code expired. Ask for a new one.');
    }
    if (row.attempts >= MAX_TRIES) {
      await query('DELETE FROM auth_codes WHERE email = $1', [email]);
      return fail(res, 400, 'CODE_LOCKED', 'Too many wrong tries. Ask for a new code.');
    }
    if (!safeEqual(row.code_hash, codeHash(code))) {
      await query('UPDATE auth_codes SET attempts = attempts + 1 WHERE email = $1', [email]);
      return fail(res, 400, 'CODE_INVALID', 'Wrong code. Try again.');
    }
    await query('DELETE FROM auth_codes WHERE email = $1', [email]);

    // Find or create the user for this email.
    let user = await query('SELECT * FROM users WHERE email = $1', [email]);
    if (user.rows.length === 0) {
      const displayName = email.split('@')[0].replace(/[._+]+/g, ' ').trim() || 'Student';
      user = await query(
        `INSERT INTO users (email, display_name, last_seen_at)
         VALUES ($1, $2, now()) RETURNING *`,
        [email, displayName],
      );
    } else {
      await query('UPDATE users SET last_seen_at = now() WHERE id = $1', [user.rows[0].id]);
    }
    const u = user.rows[0];
    if (u.is_banned) {
      return fail(res, 403, 'BANNED', 'This account is banned.');
    }
    ok(res, { token: signToken(u), user: publicUser(u) });
  } catch (err) {
    if (err && err.code === 'JWT_NOT_CONFIGURED') {
      return fail(res, 500, 'JWT_NOT_CONFIGURED', 'Log-in is not configured on the server (JWT_SECRET is missing).');
    }
    serverError(res, err);
  }
};
