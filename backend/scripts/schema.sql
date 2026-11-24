-- HSC Revision Master — custom backend schema (Vercel Postgres / Prisma Postgres).
-- Mirrors the old Supabase tables. Safe to re-run (IF NOT EXISTS).
-- No Supabase anywhere: auth is email + 6-digit code (auth_codes table) + JWT.

CREATE TABLE IF NOT EXISTS users (
  id UUID PRIMARY KEY DEFAULT gen_random_uuid(),
  email TEXT UNIQUE,
  display_name TEXT,
  photo_url TEXT,
  cover_url TEXT,
  bio TEXT,
  privacy TEXT NOT NULL DEFAULT 'public',
  photo_privacy TEXT NOT NULL DEFAULT 'public',
  is_admin BOOLEAN NOT NULL DEFAULT FALSE,
  is_muted BOOLEAN NOT NULL DEFAULT FALSE,
  is_banned BOOLEAN NOT NULL DEFAULT FALSE,
  streak INTEGER NOT NULL DEFAULT 0,
  chapters_done INTEGER NOT NULL DEFAULT 0,
  created_at TIMESTAMPTZ NOT NULL DEFAULT now(),
  following_ids UUID[] NOT NULL DEFAULT '{}',
  blocked_ids UUID[] NOT NULL DEFAULT '{}',
  milestone_ids TEXT[] NOT NULL DEFAULT '{}',
  last_seen_at TIMESTAMPTZ
);

-- One-time login codes (email + 6-digit code, 10-minute expiry, max 5 tries).
CREATE TABLE IF NOT EXISTS auth_codes (
  email TEXT PRIMARY KEY,
  code_hash TEXT NOT NULL,
  expires_at TIMESTAMPTZ NOT NULL,
  attempts INTEGER NOT NULL DEFAULT 0,
  created_at TIMESTAMPTZ NOT NULL DEFAULT now()
);

CREATE TABLE IF NOT EXISTS messages (
  id UUID PRIMARY KEY DEFAULT gen_random_uuid(),
  author_id UUID,
  author_name TEXT,
  text TEXT,
  created_at TIMESTAMPTZ NOT NULL DEFAULT now(),
  reactions JSONB NOT NULL DEFAULT '{}',
  reply_to_id UUID,
  reply_to_text TEXT,
  is_pinned BOOLEAN NOT NULL DEFAULT FALSE,
  is_flagged BOOLEAN NOT NULL DEFAULT FALSE,
  poll_id UUID
);
CREATE INDEX IF NOT EXISTS idx_messages_created_at ON messages (created_at DESC);
CREATE INDEX IF NOT EXISTS idx_messages_pinned ON messages (is_pinned, created_at DESC);

CREATE TABLE IF NOT EXISTS polls (
  id UUID PRIMARY KEY DEFAULT gen_random_uuid(),
  question TEXT NOT NULL,
  options JSONB NOT NULL DEFAULT '[]',
  votes JSONB NOT NULL DEFAULT '{}',
  created_by UUID,
  created_at TIMESTAMPTZ NOT NULL DEFAULT now()
);

CREATE TABLE IF NOT EXISTS notes (
  id UUID PRIMARY KEY DEFAULT gen_random_uuid(),
  user_id UUID,
  title TEXT,
  body TEXT,
  photo_url TEXT,
  created_at TIMESTAMPTZ NOT NULL DEFAULT now()
);
CREATE INDEX IF NOT EXISTS idx_notes_user ON notes (user_id, created_at DESC);

CREATE TABLE IF NOT EXISTS groups (
  id UUID PRIMARY KEY DEFAULT gen_random_uuid(),
  name TEXT NOT NULL,
  code TEXT UNIQUE NOT NULL,
  created_by UUID,
  created_at TIMESTAMPTZ NOT NULL DEFAULT now()
);

CREATE TABLE IF NOT EXISTS group_members (
  group_id UUID NOT NULL,
  user_id UUID NOT NULL,
  joined_at TIMESTAMPTZ NOT NULL DEFAULT now(),
  PRIMARY KEY (group_id, user_id)
);
CREATE INDEX IF NOT EXISTS idx_group_members_user ON group_members (user_id);

CREATE TABLE IF NOT EXISTS reports (
  id UUID PRIMARY KEY DEFAULT gen_random_uuid(),
  reporter_id UUID,
  message_id UUID,
  reason TEXT,
  created_at TIMESTAMPTZ NOT NULL DEFAULT now()
);
CREATE INDEX IF NOT EXISTS idx_reports_message ON reports (message_id);

CREATE TABLE IF NOT EXISTS milestones (
  id UUID PRIMARY KEY DEFAULT gen_random_uuid(),
  user_id UUID NOT NULL,
  chapter_id TEXT NOT NULL,
  subject TEXT,
  created_at TIMESTAMPTZ NOT NULL DEFAULT now(),
  UNIQUE (user_id, chapter_id)
);
CREATE INDEX IF NOT EXISTS idx_milestones_user ON milestones (user_id, created_at DESC);
CREATE INDEX IF NOT EXISTS idx_milestones_week ON milestones (created_at DESC);
