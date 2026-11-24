// /api/notes — per-chapter special notes (text / photo / both), JWT required.
// GET — my notes, newest first. POST { title, body, photo_url }.
const { query } = require('../db');
const { requireAuth } = require('../auth');
const { ok, created, badRequest, method, readJson, serverError } = require('../http');

module.exports = async (req, res) => {
  try {
    if (req.method === 'GET') {
      const user = await requireAuth(req, res);
      if (!user) return;
      const limit = Math.min(200, Math.max(1, parseInt(req.query.limit || '100', 10) || 100));
      const r = await query(
        'SELECT * FROM notes WHERE user_id = $1 ORDER BY created_at DESC LIMIT $2',
        [user.id, limit],
      );
      return ok(res, { notes: r.rows });
    }
    if (req.method === 'POST') {
      const user = await requireAuth(req, res);
      if (!user) return;
      const body = await readJson(req);
      const title = typeof body.title === 'string' ? body.title.trim().slice(0, 200) : '';
      const noteBody = typeof body.body === 'string' ? body.body.trim().slice(0, 10000) : '';
      const photoUrl =
        typeof body.photo_url === 'string' ? body.photo_url.trim().slice(0, 1000) : null;
      if (!title && !noteBody && !photoUrl) {
        return badRequest(res, 'A note needs a title, text, or a photo.');
      }
      const r = await query(
        `INSERT INTO notes (user_id, title, body, photo_url) VALUES ($1, $2, $3, $4) RETURNING *`,
        [user.id, title || null, noteBody || null, photoUrl],
      );
      return created(res, { note: r.rows[0] });
    }
    return method(res, req, ['GET', 'POST']);
  } catch (err) {
    serverError(res, err);
  }
};
