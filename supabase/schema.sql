-- ==========================================================================
-- HSC Revision Master — Supabase schema (v3, migrated from Firebase)
-- ==========================================================================
-- HOW TO APPLY: paste this whole file into the Supabase dashboard
-- (SQL Editor → New query → Run), or run it with the Supabase CLI:
--   supabase db push   (after `supabase link` + placing this file under
--   supabase/migrations/)
--
-- MANUAL STEP (not SQL): in the Supabase dashboard go to
-- Storage → New bucket → name it exactly `notes` → make it PUBLIC.
-- Note photos (per-chapter notes) and community photos/voice messages are
-- uploaded to that bucket by the app. Without the bucket, photo/voice
-- upload fails and the app keeps the local file only (see
-- lib/services/notes_repository.dart and lib/services/community_service.dart).
--
-- ==========================================================================
-- ⚠️  TEST-ONLY ROW LEVEL SECURITY — READ THIS BEFORE PUBLIC LAUNCH  ⚠️
-- ==========================================================================
-- Every table below has RLS enabled, but the policies in this file are
-- PERMISSIVE (allow all operations to both `anon` and `authenticated`).
-- They exist ONLY so the app works during testing while the real policies
-- are written. BEFORE PUBLIC LAUNCH they MUST be replaced with restrictive
-- policies, e.g.:
--   * users:   a user can update only their own row; anyone can read
--              public profiles (privacy = 'public'), restricted/locked
--              profiles only for the owner / followers.
--   * messages: only signed-in users can insert; only the author or an
--              admin can update/delete their own message.
--   * polls:   only signed-in users can vote; votes keyed by auth.uid().
--   * notes:   a user can read/write only rows where user_id = auth.uid().
--   * groups / group_members: only members can read; only the owner can
--              delete the group.
--   * reports: only signed-in users can insert; only admins can read.
--   * milestones: a user can read/write only their own rows.
-- NEVER ship the permissive policies below to real users.
-- ==========================================================================

-- --------------------------------------------------------------------------
-- users — one row per account, id = Supabase Auth user id
-- --------------------------------------------------------------------------
CREATE TABLE IF NOT EXISTS users (
  id uuid PRIMARY KEY REFERENCES auth.users (id) ON DELETE CASCADE,
  email text,
  display_name text,
  photo_url text,
  cover_url text,
  bio text,
  privacy text DEFAULT 'public',
  photo_privacy text DEFAULT 'all',
  is_admin boolean DEFAULT false,
  is_muted boolean DEFAULT false,
  is_banned boolean DEFAULT false,
  streak int DEFAULT 0,
  chapters_done int DEFAULT 0,
  created_at timestamptz DEFAULT now(),
  -- Extra columns carried over from the old Firestore user documents
  -- (not in the migration brief's core list, but the app model uses them):
  -- following_ids / blocked_ids / milestone_ids were Firestore arrays;
  -- last_seen_at powers the admin "active today" count.
  following_ids jsonb DEFAULT '[]'::jsonb,
  blocked_ids jsonb DEFAULT '[]'::jsonb,
  milestone_ids jsonb DEFAULT '[]'::jsonb,
  last_seen_at timestamptz
);

-- --------------------------------------------------------------------------
-- messages — universal community (group_id null) + group chats
-- --------------------------------------------------------------------------
CREATE TABLE IF NOT EXISTS messages (
  id uuid PRIMARY KEY DEFAULT gen_random_uuid(),
  group_id text,
  author_id uuid,
  author_name text,
  is_anonymous boolean DEFAULT false,
  body text,
  photo_url text,
  voice_url text,
  reply_to uuid,
  poll_id uuid,
  reactions jsonb DEFAULT '{}'::jsonb,
  pinned boolean DEFAULT false,
  created_at timestamptz DEFAULT now(),
  -- Extra columns carried over from the old Firestore message documents:
  -- type ('text' | 'photo' | 'poll' | 'voice'), flagged / flag_reason
  -- (auto-moderation), and reply_to_text (the quoted message text).
  type text DEFAULT 'text',
  flagged boolean DEFAULT false,
  flag_reason text,
  reply_to_text text
);

-- --------------------------------------------------------------------------
-- polls — one row per poll message; votes is userId -> optionIndex
-- (one vote per user, enforced in app code — re-voting overwrites).
-- --------------------------------------------------------------------------
CREATE TABLE IF NOT EXISTS polls (
  id uuid PRIMARY KEY DEFAULT gen_random_uuid(),
  message_id uuid,
  question text,
  options jsonb,
  votes jsonb DEFAULT '{}'::jsonb
);

-- --------------------------------------------------------------------------
-- notes — per-chapter special notes (text and/or photo).
-- unique(user_id, chapter_id): one note per user per chapter; the app
-- upserts on this key, so re-saving a note overwrites it.
-- --------------------------------------------------------------------------
CREATE TABLE IF NOT EXISTS notes (
  id uuid PRIMARY KEY DEFAULT gen_random_uuid(),
  user_id uuid,
  chapter_id text,
  text text,
  photo_url text,
  local_path text,
  updated_at timestamptz DEFAULT now(),
  UNIQUE (user_id, chapter_id)
);

-- --------------------------------------------------------------------------
-- groups — study groups joined by a 6-character code
-- --------------------------------------------------------------------------
CREATE TABLE IF NOT EXISTS groups (
  id uuid PRIMARY KEY DEFAULT gen_random_uuid(),
  code text UNIQUE,
  name text,
  owner_id uuid,
  created_at timestamptz DEFAULT now()
);

-- --------------------------------------------------------------------------
-- group_members — membership join table (replaces the old Firestore
-- `members` array on the group document)
-- --------------------------------------------------------------------------
CREATE TABLE IF NOT EXISTS group_members (
  group_id uuid,
  user_id uuid,
  PRIMARY KEY (group_id, user_id)
);

-- --------------------------------------------------------------------------
-- reports — user reports of bad messages, seen by admins
-- --------------------------------------------------------------------------
CREATE TABLE IF NOT EXISTS reports (
  id uuid PRIMARY KEY DEFAULT gen_random_uuid(),
  reporter_id uuid,
  message_id uuid,
  reason text,
  created_at timestamptz DEFAULT now()
);

-- --------------------------------------------------------------------------
-- milestones — one row per chapter a user finished fully
-- (unique per user + chapter; the display name comes from
-- lib/milestones.dart, not from this table).
-- --------------------------------------------------------------------------
CREATE TABLE IF NOT EXISTS milestones (
  id uuid PRIMARY KEY DEFAULT gen_random_uuid(),
  user_id uuid,
  subject text,
  chapter_id text,
  name text,
  unlocked_at timestamptz DEFAULT now(),
  UNIQUE (user_id, chapter_id)
);

-- --------------------------------------------------------------------------
-- Row Level Security — TEST-ONLY permissive policies (see header warning)
-- --------------------------------------------------------------------------
ALTER TABLE users ENABLE ROW LEVEL SECURITY;
ALTER TABLE messages ENABLE ROW LEVEL SECURITY;
ALTER TABLE polls ENABLE ROW LEVEL SECURITY;
ALTER TABLE notes ENABLE ROW LEVEL SECURITY;
ALTER TABLE groups ENABLE ROW LEVEL SECURITY;
ALTER TABLE group_members ENABLE ROW LEVEL SECURITY;
ALTER TABLE reports ENABLE ROW LEVEL SECURITY;
ALTER TABLE milestones ENABLE ROW LEVEL SECURITY;

-- TEST-ONLY: allow everything to anon + authenticated. Replace before launch.
DO $$
DECLARE
  t text;
BEGIN
  FOREACH t IN ARRAY ARRAY[
    'users', 'messages', 'polls', 'notes',
    'groups', 'group_members', 'reports', 'milestones'
  ] LOOP
    EXECUTE format(
      'DROP POLICY IF EXISTS "test_only_allow_all" ON %I', t
    );
    EXECUTE format(
      'CREATE POLICY "test_only_allow_all" ON %I '
      'FOR ALL TO anon, authenticated USING (true) WITH CHECK (true)',
      t
    );
  END LOOP;
END $$;

-- --------------------------------------------------------------------------
-- Realtime — the app subscribes to postgres changes on these tables
-- (community feed, profiles, reports, groups, notes). Adding them to the
-- publication is idempotent: already-added tables are skipped.
-- --------------------------------------------------------------------------
DO $$
DECLARE
  t text;
BEGIN
  FOREACH t IN ARRAY ARRAY[
    'users', 'messages', 'polls', 'notes',
    'groups', 'group_members', 'reports', 'milestones'
  ] LOOP
    BEGIN
      EXECUTE format(
        'ALTER PUBLICATION supabase_realtime ADD TABLE %I', t
      );
    EXCEPTION WHEN duplicate_object THEN
      NULL; -- already in the publication
    END;
  END LOOP;
END $$;
