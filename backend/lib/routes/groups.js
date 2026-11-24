// /api/groups — study groups with a 6-character join code.
// GET — groups the signed-in user belongs to (JWT required).
// POST { name } — create a group (JWT required), returns the join code.
const { query } = require('../db');
const { requireAuth } = require('../auth');
const { ok, created, badRequest, method, readJson, serverError } = require('../http');

const CODE_CHARS = 'ABCDEFGHJKLMNPQRSTUVWXYZ23456789'; // no 0/O/1/I

function randomCode() {
  let code = '';
  for (let i = 0; i < 6; i++) {
    code += CODE_CHARS[Math.floor(Math.random() * CODE_CHARS.length)];
  }
  return code;
}

module.exports = async (req, res) => {
  try {
    if (req.method === 'GET') {
      const user = await requireAuth(req, res);
      if (!user) return;
      const r = await query(
        `SELECT g.* FROM groups g
         JOIN group_members m ON m.group_id = g.id
         WHERE m.user_id = $1 ORDER BY g.created_at DESC`,
        [user.id],
      );
      return ok(res, { groups: r.rows });
    }
    if (req.method === 'POST') {
      const user = await requireAuth(req, res);
      if (!user) return;
      const body = await readJson(req);
      const name = typeof body.name === 'string' ? body.name.trim() : '';
      if (!name || name.length > 120) {
        return badRequest(res, 'A group name is required (max 120 characters).');
      }
      // Retry on the (rare) code collision.
      let group = null;
      for (let attempt = 0; attempt < 5 && !group; attempt++) {
        try {
          const r = await query(
            `INSERT INTO groups (name, code, created_by) VALUES ($1, $2, $3) RETURNING *`,
            [name, randomCode(), user.id],
          );
          group = r.rows[0];
        } catch (err) {
          if (err.code !== '23505') throw err; // not a code collision
        }
      }
      if (!group) return badRequest(res, 'Could not create the group. Try again.');
      await query(
        'INSERT INTO group_members (group_id, user_id) VALUES ($1, $2) ON CONFLICT DO NOTHING',
        [group.id, user.id],
      );
      return created(res, { group });
    }
    return method(res, req, ['GET', 'POST']);
  } catch (err) {
    serverError(res, err);
  }
};
