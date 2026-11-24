// /api/messages — community chat.
// GET  ?since=<ISO timestamp>&limit=<1..200> — public.
//   Polling contract (no WebSocket on Vercel serverless): the client polls
//   every few seconds with `since` = created_at of the newest message it has.
//   The server returns messages with created_at > since, newest last, plus
//   `server_time`. First load (no `since`): the latest `limit` messages.
//   Pinned messages are always included first (is_pinned, newest first).
// POST { text, reply_to_id?, reply_to_text?, poll_id? } — JWT required.
const { query } = require('../db');
const { requireAuth } = require('../auth');
const {
  ok,
  created,
  badRequest,
  notFound,
  forbidden,
  method,
  readJson,
  serverError,
  isUuid,
} = require('../http');

function publicMessage(row) {
  return {
    id: row.id,
    author_id: row.author_id,
    author_name: row.author_name || 'Student',
    text: row.text,
    created_at: row.created_at,
    reactions: row.reactions || {},
    reply_to_id: row.reply_to_id,
    reply_to_text: row.reply_to_text,
    is_pinned: row.is_pinned,
    is_flagged: row.is_flagged,
    poll_id: row.poll_id,
  };
}

module.exports = async (req, res) => {
  try {
    if (req.method === 'GET') {
      const since = typeof req.query.since === 'string' ? req.query.since : null;
      const limit = Math.min(
        200,
        Math.max(1, parseInt(req.query.limit || '100', 10) || 100),
      );
      let rows;
      if (since && !Number.isNaN(Date.parse(since))) {
        const r = await query(
          `SELECT * FROM messages WHERE created_at > $1 ORDER BY created_at ASC LIMIT $2`,
          [since, limit],
        );
        rows = r.rows;
      } else {
        const r = await query(
          `SELECT * FROM (
             SELECT * FROM messages WHERE is_pinned = true ORDER BY created_at DESC LIMIT 20
           ) pinned
           UNION ALL
           SELECT * FROM (
             SELECT * FROM messages WHERE is_pinned = false ORDER BY created_at DESC LIMIT $1
           ) recent
           ORDER BY created_at ASC`,
          [limit],
        );
        rows = r.rows;
      }
      return ok(res, {
        messages: rows.map(publicMessage),
        server_time: new Date().toISOString(),
      });
    }

    if (req.method === 'POST') {
      const user = await requireAuth(req, res);
      if (!user) return;
      if (user.is_muted) {
        return forbidden(res, 'You are muted and cannot send messages.');
      }
      const body = await readJson(req);
      const text = typeof body.text === 'string' ? body.text.trim() : '';
      if (!text || text.length > 4000) {
        return badRequest(res, 'Message text is required (max 4000 characters).');
      }
      const replyToId =
        typeof body.reply_to_id === 'string' && isUuid(body.reply_to_id)
          ? body.reply_to_id
          : null;
      const replyToText =
        typeof body.reply_to_text === 'string' ? body.reply_to_text.slice(0, 200) : null;
      const pollId =
        typeof body.poll_id === 'string' && isUuid(body.poll_id) ? body.poll_id : null;
      const authorName =
        user.display_name || (user.email ? user.email.split('@')[0] : 'Student');
      const r = await query(
        `INSERT INTO messages (author_id, author_name, text, reply_to_id, reply_to_text, poll_id)
         VALUES ($1, $2, $3, $4, $5, $6) RETURNING *`,
        [user.id, authorName, text, replyToId, replyToText, pollId],
      );
      return created(res, { message: publicMessage(r.rows[0]) });
    }

    return method(res, req, ['GET', 'POST']);
  } catch (err) {
    serverError(res, err);
  }
};
