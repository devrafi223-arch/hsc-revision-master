// GET /api/health — liveness + DB check. No auth.
const { query } = require('../db');
const { ok, method, serverError } = require('../http');

module.exports = async (req, res) => {
  if (!method(res, req, ['GET'])) return;
  try {
    const started = Date.now();
    const r = await query('SELECT 1 AS one');
    ok(res, {
      status: 'ok',
      db: r.rows.length === 1 ? 'up' : 'down',
      db_ms: Date.now() - started,
      time: new Date().toISOString(),
    });
  } catch (err) {
    serverError(res, err);
  }
};
