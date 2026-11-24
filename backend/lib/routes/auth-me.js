// GET /api/auth/me — returns the signed-in user's profile (JWT required).
const { requireAuth } = require('../auth');
const { ok, method, serverError } = require('../http');

module.exports = async (req, res) => {
  if (!method(res, req, ['GET'])) return;
  try {
    const user = await requireAuth(req, res);
    if (!user) return;
    ok(res, {
      user: {
        id: user.id,
        email: user.email,
        display_name: user.display_name,
        photo_url: user.photo_url,
        cover_url: user.cover_url,
        bio: user.bio,
        privacy: user.privacy,
        photo_privacy: user.photo_privacy,
        is_admin: user.is_admin,
        streak: user.streak,
        chapters_done: user.chapters_done,
        created_at: user.created_at,
        last_seen_at: user.last_seen_at,
      },
    });
  } catch (err) {
    serverError(res, err);
  }
};
