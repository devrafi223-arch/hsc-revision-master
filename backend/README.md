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
| `GMAIL_APP_PASSWORD` | Gmail app password — **set 2026-11-24**; OTP mail verified live |

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

## Endpoints

Community is gone (Rafi, 2026-11-24): the messages/polls/groups/
leaderboard/presence endpoints were removed. The tables still exist
in Postgres (empty) but nothing routes to them.

| Method & path | Auth | Notes |
| --- | --- | --- |
| `GET /api/health` | — | liveness + DB check |
| `POST /api/auth/send-code` | — | email + 6-digit code |
| `POST /api/auth/verify-code` | — | returns JWT (7 days) |
| `GET /api/auth/me` | JWT | own profile |
| `GET /api/notes` · `POST /api/notes` | JWT | `{title, body, photo_url}` |
| `GET /api/users/:id` | JWT | email hidden unless self/admin |
| `POST /api/milestones` | JWT | `{chapter_id, subject}` — once per chapter |
| `GET /api/admin/users` | admin | paginated user list |
| `POST /api/upload?filename=&kind=profile\|note` | JWT | raw image body, max 4 MB; 501 if Blob not connected |

All responses: `{ok: true, ...}` or `{ok: false, error: CODE, message}`.

## Tables

`users, auth_codes, messages, polls, notes, groups, group_members,
reports, milestones` — see `scripts/schema.sql`.
