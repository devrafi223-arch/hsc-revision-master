// POST /api/messages/:id/report — report a message (JWT required).
// Body: { "reason": "..." } — flags the message for admin review.
const { query } = require('../db');
const { requireAuth } = require('../auth');
const { ok, created, badRequest, notFound, method, readJson, serverError } = require('../http');

module.exports = async (req, res) => {
  if (!method(res, req, ['POST'])) return;
  try {
    const user = await requireAuth(req, res);
    if (!user) return;
    const id = req.query.id;
    const body = await readJson(req);
    const reason = typeof body.reason === 'string' ? body.reason.trim().slice(0, 500) : '';
    if (!reason) return badRequest(res, 'A reason is required.');
    const found = await query('SELECT id FROM messages WHERE id = $1', [id]);
    if (found.rows.length === 0) return notFound(res, 'Message not found.');
    const r = await query(
      `INSERT INTO reports (reporter_id, message_id, reason) VALUES ($1, $2, $3) RETURNING id, created_at`,
      [user.id, id, reason],
    );
    await query('UPDATE messages SET is_flagged = true WHERE id = $1', [id]);
    created(res, { report: r.rows[0] });
  } catch (err) {
    serverError(res, err);
  }
};
