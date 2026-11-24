// POST /api/messages/:id/pin — pin or unpin a message. Admin only.
// Body: { "pinned": true }
const { query } = require('../db');
const { requireAuth } = require('../auth');
const { ok, badRequest, notFound, forbidden, method, readJson, serverError } = require('../http');

module.exports = async (req, res) => {
  if (!method(res, req, ['POST'])) return;
  try {
    const user = await requireAuth(req, res);
    if (!user) return;
    if (!user.is_admin) return forbidden(res, 'Only an admin can pin messages.');
    const id = req.query.id;
    const body = await readJson(req);
    if (typeof body.pinned !== 'boolean') {
      return badRequest(res, '"pinned" must be true or false.');
    }
    const r = await query('UPDATE messages SET is_pinned = $1 WHERE id = $2 RETURNING id', [
      body.pinned,
      id,
    ]);
    if (r.rows.length === 0) return notFound(res, 'Message not found.');
    ok(res, { id, pinned: body.pinned });
  } catch (err) {
    serverError(res, err);
  }
};
