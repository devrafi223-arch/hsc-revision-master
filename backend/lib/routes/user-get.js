// GET /api/users/:id — public profile (JWT required).
// Email is shown only to the user themselves or an admin.
const { query } = require('../db');
const { requireAuth } = require('../auth');
const { ok, notFound, method, serverError } = require('../http');

module.exports = async (req, res) => {
  if (!method(res, req, ['GET'])) return;
  try {
    const me = await requireAuth(req, res);
    if (!me) return;
    const r = await query('SELECT * FROM users WHERE id = $1', [req.query.id]);
    if (r.rows.length === 0) return notFound(res, 'User not found.');
    const u = r.rows[0];
    const isSelf = me.id === u.id;
    ok(res, {
      user: {
        id: u.id,
        email: isSelf || me.is_admin ? u.email : null,
        display_name: u.display_name,
        photo_url: u.photo_url,
        cover_url: u.cover_url,
        bio: u.bio,
        privacy: u.privacy,
        streak: u.streak,
        chapters_done: u.chapters_done,
        created_at: u.created_at,
        last_seen_at: u.last_seen_at,
      },
    });
  } catch (err) {
    serverError(res, err);
  }
};
