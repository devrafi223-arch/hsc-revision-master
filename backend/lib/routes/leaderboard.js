// GET /api/leaderboard — top students (public).
// ?range=all (default): by chapters_done. ?range=weekly: milestones in the
// last 7 days. Returns up to 50 rows.
const { query } = require('../db');
const { ok, method, serverError } = require('../http');

module.exports = async (req, res) => {
  if (!method(res, req, ['GET'])) return;
  try {
    const range = req.query.range === 'weekly' ? 'weekly' : 'all';
    let rows;
    if (range === 'weekly') {
      const r = await query(
        `SELECT u.id, u.display_name, u.photo_url, COUNT(m.id)::int AS score
         FROM users u
         JOIN milestones m ON m.user_id = u.id
         WHERE m.created_at >= now() - interval '7 days'
         GROUP BY u.id, u.display_name, u.photo_url
         ORDER BY score DESC, u.display_name ASC
         LIMIT 50`,
      );
      rows = r.rows;
    } else {
      const r = await query(
        `SELECT id, display_name, photo_url, chapters_done AS score, streak
         FROM users ORDER BY chapters_done DESC, streak DESC LIMIT 50`,
      );
      rows = r.rows;
    }
    ok(res, { range, leaderboard: rows });
  } catch (err) {
    serverError(res, err);
  }
};
