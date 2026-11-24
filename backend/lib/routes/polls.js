// /api/polls — Telegram-style polls (one vote per user).
// GET — list latest polls (public).
// POST { question, options: ["a", "b"] } — JWT required.
const { query } = require('../db');
const { requireAuth } = require('../auth');
const { ok, created, badRequest, method, readJson, serverError } = require('../http');

function publicPoll(row) {
  return {
    id: row.id,
    question: row.question,
    options: row.options || [],
    votes: row.votes || {},
    created_by: row.created_by,
    created_at: row.created_at,
  };
}

module.exports = async (req, res) => {
  try {
    if (req.method === 'GET') {
      const limit = Math.min(100, Math.max(1, parseInt(req.query.limit || '50', 10) || 50));
      const r = await query('SELECT * FROM polls ORDER BY created_at DESC LIMIT $1', [limit]);
      return ok(res, { polls: r.rows.map(publicPoll) });
    }
    if (req.method === 'POST') {
      const user = await requireAuth(req, res);
      if (!user) return;
      if (user.is_muted) {
        return ok(res, { ok: false, error: 'FORBIDDEN', message: 'You are muted.' });
      }
      const body = await readJson(req);
      const question = typeof body.question === 'string' ? body.question.trim() : '';
      const options = Array.isArray(body.options)
        ? body.options.filter((o) => typeof o === 'string' && o.trim()).map((o) => o.trim().slice(0, 200))
        : [];
      if (!question || options.length < 2 || options.length > 10) {
        return badRequest(res, 'A question and 2–10 options are required.');
      }
      const r = await query(
        `INSERT INTO polls (question, options, votes, created_by) VALUES ($1, $2, '{}', $3) RETURNING *`,
        [question, JSON.stringify(options), user.id],
      );
      return created(res, { poll: publicPoll(r.rows[0]) });
    }
    return method(res, req, ['GET', 'POST']);
  } catch (err) {
    serverError(res, err);
  }
};
