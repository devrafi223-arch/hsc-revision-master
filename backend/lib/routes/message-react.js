// POST /api/messages/:id/react — toggle one reaction for the signed-in user.
// Body: { "emoji": "❤️" } — reactions are stored as { emoji: [uid, ...] },
// so one user can only add one of each emoji; tapping again removes it.
const { query } = require('../db');
const { requireAuth } = require('../auth');
const { ok, badRequest, notFound, method, readJson, serverError } = require('../http');

module.exports = async (req, res) => {
  if (!method(res, req, ['POST'])) return;
  try {
    const user = await requireAuth(req, res);
    if (!user) return;
    const id = req.query.id;
    const body = await readJson(req);
    const emoji = typeof body.emoji === 'string' ? body.emoji.trim() : '';
    if (!emoji || emoji.length > 12) {
      return badRequest(res, 'An emoji is required.');
    }
    const found = await query('SELECT reactions FROM messages WHERE id = $1', [id]);
    if (found.rows.length === 0) return notFound(res, 'Message not found.');
    const reactions = found.rows[0].reactions || {};
    const list = Array.isArray(reactions[emoji]) ? [...reactions[emoji]] : [];
    const i = list.indexOf(user.id);
    const reacted = i === -1;
    if (reacted) list.push(user.id);
    else list.splice(i, 1);
    if (list.length === 0) delete reactions[emoji];
    else reactions[emoji] = list;
    await query('UPDATE messages SET reactions = $1 WHERE id = $2', [
      JSON.stringify(reactions),
      id,
    ]);
    ok(res, { reactions, reacted });
  } catch (err) {
    serverError(res, err);
  }
};
