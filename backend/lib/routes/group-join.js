// POST /api/groups/join — join a group with its 6-character code (JWT required).
// Body: { "code": "ABC123" }
const { query } = require('../db');
const { requireAuth } = require('../auth');
const { ok, badRequest, notFound, method, readJson, serverError } = require('../http');

module.exports = async (req, res) => {
  if (!method(res, req, ['POST'])) return;
  try {
    const user = await requireAuth(req, res);
    if (!user) return;
    const body = await readJson(req);
    const code = typeof body.code === 'string' ? body.code.trim().toUpperCase() : '';
    if (!/^[A-Z0-9]{6}$/.test(code)) {
      return badRequest(res, 'Enter the 6-character group code.');
    }
    const found = await query('SELECT * FROM groups WHERE code = $1', [code]);
    if (found.rows.length === 0) return notFound(res, 'No group has that code.');
    const group = found.rows[0];
    await query(
      'INSERT INTO group_members (group_id, user_id) VALUES ($1, $2) ON CONFLICT DO NOTHING',
      [group.id, user.id],
    );
    ok(res, { group });
  } catch (err) {
    serverError(res, err);
  }
};
