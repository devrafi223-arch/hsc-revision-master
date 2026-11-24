// POST /api/upload — upload a profile or note photo to Vercel Blob.
// Query: ?filename=<name>&kind=profile|note — raw image bytes in the body.
// JWT required. Max ~4 MB (Vercel serverless request limit).
// Needs BLOB_READ_WRITE_TOKEN (injected when the Blob store is connected to
// the project). If it is missing, this returns 501 with a clear note.
const { put } = require('@vercel/blob');
const { query } = require('../db');
const { requireAuth } = require('../auth');
const { ok, created, fail, badRequest, method, serverError } = require('../http');

const MAX_BYTES = 4 * 1024 * 1024;

module.exports = async (req, res) => {
  if (!method(res, req, ['POST'])) return;
  try {
    const user = await requireAuth(req, res);
    if (!user) return;
    // On Vercel the Blob SDK authenticates with OIDC automatically (the
    // store is connected to this project); BLOB_READ_WRITE_TOKEN is only
    // needed when calling from outside Vercel, so pass it only if set.
    const token = process.env.BLOB_READ_WRITE_TOKEN;
    const kind = req.query.kind === 'note' ? 'note' : 'profile';
    const rawName =
      typeof req.query.filename === 'string' && req.query.filename.trim()
        ? req.query.filename.trim().replace(/[^A-Za-z0-9._-]/g, '_')
        : 'photo.jpg';
    const ext = rawName.includes('.') ? rawName.split('.').pop().toLowerCase() : 'jpg';
    if (!['jpg', 'jpeg', 'png', 'webp'].includes(ext)) {
      return badRequest(res, 'Only jpg, png, or webp photos are allowed.');
    }
    const contentType = req.headers['content-type'] || '';
    if (!contentType.startsWith('image/')) {
      return badRequest(res, 'Send the photo as the raw image body.');
    }
    const chunks = [];
    let size = 0;
    for await (const chunk of req) {
      size += chunk.length;
      if (size > MAX_BYTES) {
        return badRequest(res, 'Photo is too large (max 4 MB).');
      }
      chunks.push(chunk);
    }
    if (size === 0) return badRequest(res, 'Empty upload.');
    const body = Buffer.concat(chunks);
    const pathname = `${kind}/${user.id}/${Date.now()}_${rawName}`;
    let blob;
    try {
      blob = await put(pathname, body, {
        access: 'public',
        ...(token ? { token } : {}),
      });
    } catch (err) {
      console.error('[upload] blob put failed:', err.message);
      return fail(
        res,
        501,
        'BLOB_NOT_CONFIGURED',
        'Photo upload is not set up yet: the Blob store is not connected to this project.',
      );
    }
    if (kind === 'profile') {
      await query('UPDATE users SET photo_url = $1 WHERE id = $2', [blob.url, user.id]);
    }
    created(res, { url: blob.url, pathname: blob.pathname });
  } catch (err) {
    serverError(res, err);
  }
};
