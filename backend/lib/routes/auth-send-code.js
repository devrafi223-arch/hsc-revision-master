// POST /api/auth/send-code — email + 6-digit login code via Gmail SMTP.
// Body: { "email": "user@gmail.com" }
// Allowed domains (Rafi's standing rule): gmail, googlemail, hotmail,
// outlook, yahoo (incl. .co.uk variants). Code is valid 10 minutes.
const crypto = require('crypto');
const { query } = require('../db');
const { sendMail } = require('../mail');
const {
  ok,
  fail,
  badRequest,
  method,
  readJson,
  serverError,
} = require('../http');

const ALLOWED_DOMAINS = new Set([
  'gmail.com',
  'googlemail.com',
  'hotmail.com',
  'hotmail.co.uk',
  'outlook.com',
  'yahoo.com',
  'yahoo.co.uk',
]);

const CODE_TTL_SECONDS = 10 * 60;
const RESEND_WAIT_SECONDS = 60;

function codeHash(code) {
  return crypto.createHash('sha256').update(code).digest('hex');
}

module.exports = async (req, res) => {
  if (!method(res, req, ['POST'])) return;
  try {
    const body = await readJson(req);
    const email = typeof body.email === 'string' ? body.email.trim().toLowerCase() : '';
    if (!/^[^\s@]+@[^\s@]+\.[^\s@]+$/.test(email)) {
      return badRequest(res, 'Enter a valid email address.');
    }
    const domain = email.split('@').pop();
    if (!ALLOWED_DOMAINS.has(domain)) {
      return fail(
        res,
        400,
        'EMAIL_DOMAIN_NOT_ALLOWED',
        'Only Gmail, Hotmail, Outlook, and Yahoo emails are allowed.',
      );
    }

    // Resend guard: one code per minute per email.
    const existing = await query('SELECT created_at FROM auth_codes WHERE email = $1', [email]);
    if (existing.rows.length > 0) {
      const ageMs = Date.now() - new Date(existing.rows[0].created_at).getTime();
      if (ageMs < RESEND_WAIT_SECONDS * 1000) {
        return fail(res, 429, 'TOO_SOON', `Wait ${RESEND_WAIT_SECONDS} seconds before asking again.`);
      }
    }

    const code = String(Math.floor(100000 + Math.random() * 900000));
    const expiresAt = new Date(Date.now() + CODE_TTL_SECONDS * 1000).toISOString();
    await query(
      `INSERT INTO auth_codes (email, code_hash, expires_at, attempts)
       VALUES ($1, $2, $3, 0)
       ON CONFLICT (email) DO UPDATE
         SET code_hash = EXCLUDED.code_hash,
             expires_at = EXCLUDED.expires_at,
             attempts = 0,
             created_at = now()`,
      [email, codeHash(code), expiresAt],
    );

    try {
      await sendMail({
        to: email,
        subject: 'Your HSC Revision Master login code',
        text: `Your HSC Revision Master login code is ${code}. It is valid for 10 minutes. If you did not ask for this, ignore this email.`,
        html: `<div style="font-family:sans-serif;max-width:480px;margin:0 auto;padding:24px;background:#FAF8F4;color:#1C1A17;border-radius:16px">
          <h2 style="color:#A9716B;margin:0 0 8px">HSC Revision Master</h2>
          <p>Your login code is:</p>
          <p style="font-size:32px;letter-spacing:6px;font-weight:700;margin:8px 0">${code}</p>
          <p style="color:#6b6560">Valid for 10 minutes. If you did not ask for this, ignore this email.</p>
        </div>`,
      });
    } catch (err) {
      if (err && err.code === 'EMAIL_NOT_CONFIGURED') {
        return fail(
          res,
          500,
          'EMAIL_NOT_CONFIGURED',
          'Email sending is not set up on the server yet (GMAIL_APP_PASSWORD is missing). Ask the admin to set it.',
        );
      }
      throw err;
    }

    ok(res, { sent: true, expires_in_seconds: CODE_TTL_SECONDS });
  } catch (err) {
    serverError(res, err);
  }
};
