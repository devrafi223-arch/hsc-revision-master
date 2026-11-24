// GET /api/admin/users — list users for the admin panel (admin JWT required).
// ?limit=<1..200>&offset=<n>
const { query } = require('../db');
const { requireAuth } = require('../auth');
const { ok, forbidden, badRequest, notFound, method, serverError } = require('../http');

module.exports = async (req, res) => {
  if (!method(res, req, ['GET', 'DELETE'])) return;
  try {
    const user = await requireAuth(req, res);
    if (!user) return;
    if (!user.is_admin) return forbidden(res, 'Only an admin can list users.');
    if (req.method === 'DELETE') {
      const id = req.query.id;
      if (!id) return badRequest(res, '"id" query parameter is required.');
      if (id === user.id) return forbidden(res, 'You cannot delete your own account.');
      const r = await query('DELETE FROM users WHERE id = $1 RETURNING id', [id]);
      if (r.rows.length === 0) return notFound(res, 'User not found.');
      return ok(res, { deleted: id });
    }
    const limit = Math.min(200, Math.max(1, parseInt(req.query.limit || '100', 10) || 100));
    const offset = Math.max(0, parseInt(req.query.offset || '0', 10) || 0);
    const total = await query('SELECT count(*)::int AS n FROM users');
    const r = await query(
      `SELECT id, email, display_name, photo_url, is_admin, is_muted, is_banned,
              streak, chapters_done, created_at, last_seen_at
       FROM users ORDER BY created_at DESC LIMIT $1 OFFSET $2`,
      [limit, offset],
    );
    ok(res, { total: total.rows[0].n, users: r.rows });
  } catch (err) {
    serverError(res, err);
  }
};
