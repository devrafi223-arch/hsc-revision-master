// JWT auth for the custom backend.
// Tokens live 7 days from login (Rafi's standing session rule).
// JWT_SECRET must be set as a Vercel env var (never committed).
const jwt = require('jsonwebtoken');
const { query } = require('./db');
const { unauthorized } = require('./http');

const SESSION_DAYS = 7;

function getSecret() {
  const secret = process.env.JWT_SECRET;
  if (!secret) {
    throw Object.assign(new Error('JWT_SECRET is not set'), {
      code: 'JWT_NOT_CONFIGURED',
    });
  }
  return secret;
}

function signToken(user) {
  return jwt.sign(
    { uid: user.id, email: user.email || null },
    getSecret(),
    { expiresIn: `${SESSION_DAYS}d` },
  );
}

function verifyToken(token) {
  return jwt.verify(token, getSecret());
}

// Returns the authenticated user row, or sends 401 and returns null.
// Attaches nothing to req; callers use the returned row.
async function requireAuth(req, res) {
  try {
    const header = req.headers.authorization || '';
    const token = header.startsWith('Bearer ') ? header.slice(7) : null;
    if (!token) {
      unauthorized(res, 'Log in to continue.');
      return null;
    }
    const payload = verifyToken(token);
    const { rows } = await query('SELECT * FROM users WHERE id = $1', [payload.uid]);
    if (rows.length === 0) {
      unauthorized(res, 'Account not found. Log in again.');
      return null;
    }
    const user = rows[0];
    if (user.is_banned) {
      unauthorized(res, 'This account is banned.');
      return null;
    }
    return user;
  } catch (err) {
    if (err && err.code === 'JWT_NOT_CONFIGURED') {
      console.error('[auth] JWT_SECRET missing');
      res.status(500);
      res.setHeader('Content-Type', 'application/json');
      res.end(
        JSON.stringify({
          ok: false,
          error: 'JWT_NOT_CONFIGURED',
          message: 'Log-in is not configured on the server.',
        }),
      );
      return null;
    }
    unauthorized(res, 'Session expired. Log in again.');
    return null;
  }
}

module.exports = { signToken, verifyToken, requireAuth, SESSION_DAYS };
