// POST /api/polls/:id/vote — one vote per user (JWT required).
// Body: { "option_index": 0 } — the user is removed from every other
// option first, so a re-vote moves their vote instead of doubling it.
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
    const optionIndex = body.option_index;
    if (!Number.isInteger(optionIndex) || optionIndex < 0) {
      return badRequest(res, '"option_index" must be a non-negative integer.');
    }
    const found = await query('SELECT options, votes FROM polls WHERE id = $1', [id]);
    if (found.rows.length === 0) return notFound(res, 'Poll not found.');
    const options = found.rows[0].options || [];
    if (optionIndex >= options.length) {
      return badRequest(res, 'That option does not exist.');
    }
    const votes = found.rows[0].votes || {};
    for (const key of Object.keys(votes)) {
      if (Array.isArray(votes[key])) {
        votes[key] = votes[key].filter((uid) => uid !== user.id);
        if (votes[key].length === 0) delete votes[key];
      }
    }
    const key = String(optionIndex);
    if (!Array.isArray(votes[key])) votes[key] = [];
    votes[key].push(user.id);
    await query('UPDATE polls SET votes = $1 WHERE id = $2', [JSON.stringify(votes), id]);
    ok(res, { votes });
  } catch (err) {
    serverError(res, err);
  }
};
