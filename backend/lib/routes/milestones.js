// POST /api/milestones — mark a chapter done (JWT required).
// Body: { "chapter_id": "phy-1", "subject": "Physics" }
// One milestone per user per chapter; re-posting the same chapter is a no-op
// and does not double-count chapters_done.
const { query } = require('../db');
const { requireAuth } = require('../auth');
const { ok, created, badRequest, method, readJson, serverError } = require('../http');

module.exports = async (req, res) => {
  if (!method(res, req, ['POST'])) return;
  try {
    const user = await requireAuth(req, res);
    if (!user) return;
    const body = await readJson(req);
    const chapterId = typeof body.chapter_id === 'string' ? body.chapter_id.trim() : '';
    const subject = typeof body.subject === 'string' ? body.subject.trim().slice(0, 120) : null;
    if (!chapterId || chapterId.length > 200) {
      return badRequest(res, '"chapter_id" is required.');
    }
    const r = await query(
      `INSERT INTO milestones (user_id, chapter_id, subject) VALUES ($1, $2, $3)
       ON CONFLICT (user_id, chapter_id) DO NOTHING RETURNING *`,
      [user.id, chapterId, subject],
    );
    if (r.rows.length === 0) {
      return ok(res, { milestone: null, already_done: true, chapters_done: user.chapters_done });
    }
    const updated = await query(
      `UPDATE users
       SET chapters_done = chapters_done + 1,
           milestone_ids = array_append(milestone_ids, $2)
       WHERE id = $1 RETURNING chapters_done`,
      [user.id, chapterId],
    );
    created(res, { milestone: r.rows[0], chapters_done: updated.rows[0].chapters_done });
  } catch (err) {
    serverError(res, err);
  }
};
