# HSC Revision Master — custom backend (Phase 1)

Custom Node.js API on Vercel (serverless functions) + Vercel Postgres
(Prisma Postgres) + Vercel Blob. **No Supabase anywhere** — Rafi ordered
Supabase fully dropped (2026-11-24).

- Vercel project: `hsc-revision-master-api` (team `rafi36012s-projects`,
  root directory `backend`)
- Postgres store: `hsc-revision-master-db` (Prisma Postgres, free plan,
  region `sin1` Singapore)
- Blob store: `hsc-revision-master-blob` (public, `sin1`)

## Deploy

```sh
cd backend
npm install
# link once (writes .vercel/project.json, git-ignored):
VERCEL_TOKEN=<token> npx -y vercel@latest link --project hsc-revision-master-api --scope rafi36012s-projects --yes
VERCEL_TOKEN=<token> npx -y vercel@latest deploy --prod --yes
```

Env vars are set on the Vercel project (never in this repo):

| Var | Purpose |
| --- | --- |
| `POSTGRES_URL` / `DATABASE_URL` / `DATABASE_URL_POOLED` | Injected by connecting the Postgres store |
| `BLOB_READ_WRITE_TOKEN` | Injected by connecting the Blob store |
| `JWT_SECRET` | Random 32-byte hex; signs login tokens (7-day sessions) |
| `GMAIL_USER` | `rafixbo34@gmail.com` |
| `GMAIL_APP_PASSWORD` | Gmail app password — **NOT SET yet** (blocker for OTP mail; see below) |

Schema: `npm run schema` (needs `POSTGRES_URL` in env) — applies
`scripts/schema.sql` (idempotent) and prints table counts.

## Auth

Email + 6-digit code (no passwords, no Supabase Auth):

1. `POST /api/auth/send-code` `{email}` — code valid 10 min, 1 resend/min,
   max 5 wrong tries. Allowed domains: gmail, googlemail, hotmail,
   outlook, yahoo (+ .co.uk variants).
2. `POST /api/auth/verify-code` `{email, code}` — returns `{token, user}`.
   JWT lives 7 days (Rafi's session rule).
3. `GET /api/auth/me` — `Authorization: Bearer <token>`.

**Blocker:** `GMAIL_APP_PASSWORD` is not set (the password is not stored
anywhere). Until Rafi provides it as a Vercel env var, `send-code` returns
`500 EMAIL_NOT_CONFIGURED` with a clear message instead of crashing.

## Live updates (polling — no WebSocket on Vercel serverless)

`GET /api/messages?since=<ISO timestamp>&limit=100` returns messages with
`created_at > since` (newest last) plus `server_time`. The client polls
every 2–3 s with `since` = newest `created_at` it has. First load (no
`since`): pinned messages first, then the latest `limit` messages.

## Endpoints

| Method & path | Auth | Notes |
| --- | --- | --- |
| `GET /api/health` | — | liveness + DB check |
| `POST /api/auth/send-code` | — | email + 6-digit code |
| `POST /api/auth/verify-code` | — | returns JWT (7 days) |
| `GET /api/auth/me` | JWT | own profile |
| `GET /api/messages?since=&limit=` | — | polling contract above |
| `POST /api/messages` | JWT | `{text, reply_to_id?, reply_to_text?, poll_id?}` |
| `POST /api/messages/:id/react` | JWT | `{emoji}` — per-user toggle |
| `POST /api/messages/:id/pin` | admin | `{pinned: bool}` |
| `POST /api/messages/:id/report` | JWT | `{reason}` — also flags message |
| `GET /api/polls` · `POST /api/polls` | — / JWT | `{question, options[]}` |
| `POST /api/polls/:id/vote` | JWT | `{option_index}` — one vote/user |
| `GET /api/groups` · `POST /api/groups` | JWT | create returns 6-char code |
| `POST /api/groups/join` | JWT | `{code}` |
| `GET /api/notes` · `POST /api/notes` | JWT | `{title, body, photo_url}` |
| `GET /api/users/:id` | JWT | email hidden unless self/admin |
| `GET /api/leaderboard?range=all\|weekly` | — | top 50 |
| `POST /api/milestones` | JWT | `{chapter_id, subject}` — once per chapter |
| `GET /api/admin/users` | admin | paginated user list |
| `POST /api/upload?filename=&kind=profile\|note` | JWT | raw image body, max 4 MB; 501 if Blob not connected |
| `GET /api/presence` | — | users seen in the last 5 min (`{online: [...]}`) |
| `POST /api/presence` | JWT | heartbeat — marks this user seen now |

All responses: `{ok: true, ...}` or `{ok: false, error: CODE, message}`.

## Tables

`users, auth_codes, messages, polls, notes, groups, group_members,
reports, milestones` — see `scripts/schema.sql`.
