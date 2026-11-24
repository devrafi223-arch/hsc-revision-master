// /api/presence — who is online in the community (polling, no WebSocket).
// GET — public. Users seen in the last 5 minutes (last_seen_at).
// POST — JWT required. Heartbeat: marks this user seen right now.
// Typing is NOT tracked: there is no typing column, and the app shows
// online dots only (the typing line was dropped in the v3.0.11 client).
const { query } = require('../db');
const { requireAuth } = require('../auth');
const { ok, method, serverError } = require('../http');

const ONLINE_WINDOW_MINUTES = 5;

module.exports = async (req, res) => {
  try {
    if (req.method === 'GET') {
      const r = await query(
        `SELECT id, display_name, photo_url, last_seen_at FROM users
         WHERE last_seen_at > now() - interval '${ONLINE_WINDOW_MINUTES} minutes'
         ORDER BY display_name ASC LIMIT 50`,
      );
      return ok(res, { online: r.rows });
    }
    if (req.method === 'POST') {
      const user = await requireAuth(req, res);
      if (!user) return;
      await query('UPDATE users SET last_seen_at = now() WHERE id = $1', [
        user.id,
      ]);
      return ok(res, { seen: true });
    }
    return method(res, req, ['GET', 'POST']);
  } catch (err) {
    serverError(res, err);
  }
};
