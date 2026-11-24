// Email (OTP codes) via Gmail SMTP.
// Env: GMAIL_USER (rafixbo34@gmail.com), GMAIL_APP_PASSWORD (app password).
// The app password is NEVER in this repo; it lives only as a Vercel env var.
// If it is missing, sendCode throws EMAIL_NOT_CONFIGURED with a clear message.
const nodemailer = require('nodemailer');

let transporter = null;

function getTransporter() {
  if (transporter) return transporter;
  const user = process.env.GMAIL_USER;
  const pass = process.env.GMAIL_APP_PASSWORD;
  if (!user || !pass) {
    throw Object.assign(
      new Error(
        'Email is not configured on the server (GMAIL_USER / GMAIL_APP_PASSWORD missing).',
      ),
      { code: 'EMAIL_NOT_CONFIGURED' },
    );
  }
  transporter = nodemailer.createTransport({
    host: 'smtp.gmail.com',
    port: 587,
    secure: false,
    auth: { user, pass },
  });
  return transporter;
}

async function sendMail({ to, subject, text, html }) {
  const t = getTransporter();
  const from = `"HSC Revision Master" <${process.env.GMAIL_USER}>`;
  return t.sendMail({ from, to, subject, text, html });
}

module.exports = { sendMail };
