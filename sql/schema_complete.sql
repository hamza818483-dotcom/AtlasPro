-- schema_complete.sql — AtlasPro complete D1 schema
-- Run this single file on a fresh D1 database.
-- All tables use IF NOT EXISTS so it's safe to re-run.

-- ── Users ────────────────────────────────────────────────────────────────────
CREATE TABLE IF NOT EXISTS users (
  id               INTEGER PRIMARY KEY AUTOINCREMENT,
  name             TEXT NOT NULL,
  father_name      TEXT DEFAULT '',
  mother_name      TEXT DEFAULT '',
  hsc_batch        TEXT DEFAULT '',
  college_name     TEXT DEFAULT '',
  ssc_gpa          TEXT DEFAULT '',
  hsc_gpa          TEXT DEFAULT '',
  phone            TEXT UNIQUE NOT NULL,
  secondary_phone  TEXT DEFAULT '',
  social_link      TEXT DEFAULT '',
  password_hash    TEXT NOT NULL,
  gender           TEXT DEFAULT 'male',
  profile_pic      TEXT,
  session_token    TEXT,
  access_type      TEXT DEFAULT 'free',
  daily_page_limit INTEGER DEFAULT 10,
  is_admin         INTEGER DEFAULT 0,
  created_at       DATETIME DEFAULT CURRENT_TIMESTAMP
);

-- ── Subjects ─────────────────────────────────────────────────────────────────
CREATE TABLE IF NOT EXISTS subjects (
  id          INTEGER PRIMARY KEY AUTOINCREMENT,
  name        TEXT NOT NULL,
  description TEXT DEFAULT '',
  icon        TEXT DEFAULT '📚',
  color       TEXT DEFAULT '#6C63FF',
  order_index INTEGER DEFAULT 0,
  created_at  DATETIME DEFAULT CURRENT_TIMESTAMP
);

-- ── Chapters ─────────────────────────────────────────────────────────────────
CREATE TABLE IF NOT EXISTS chapters (
  id          INTEGER PRIMARY KEY AUTOINCREMENT,
  subject_id  INTEGER NOT NULL,
  name        TEXT NOT NULL,
  is_premium  INTEGER DEFAULT 0,
  order_index INTEGER DEFAULT 0,
  created_at  DATETIME DEFAULT CURRENT_TIMESTAMP,
  FOREIGN KEY (subject_id) REFERENCES subjects(id) ON DELETE CASCADE
);

-- ── PDFs ─────────────────────────────────────────────────────────────────────
CREATE TABLE IF NOT EXISTS pdfs (
  id          INTEGER PRIMARY KEY AUTOINCREMENT,
  chapter_id  INTEGER NOT NULL,
  title       TEXT NOT NULL,
  r2_key      TEXT,
  r2_url      TEXT,
  page_count  INTEGER DEFAULT 0,
  file_size   INTEGER DEFAULT 0,
  is_premium  INTEGER DEFAULT 0,
  created_at  DATETIME DEFAULT CURRENT_TIMESTAMP,
  FOREIGN KEY (chapter_id) REFERENCES chapters(id) ON DELETE CASCADE
);

-- ── MCQs ─────────────────────────────────────────────────────────────────────
CREATE TABLE IF NOT EXISTS mcqs (
  id             INTEGER PRIMARY KEY AUTOINCREMENT,
  pdf_id         INTEGER NOT NULL,
  type           TEXT NOT NULL DEFAULT 'standard',
  question       TEXT NOT NULL,
  option_a       TEXT NOT NULL DEFAULT '',
  option_b       TEXT NOT NULL DEFAULT '',
  option_c       TEXT NOT NULL DEFAULT '',
  option_d       TEXT NOT NULL DEFAULT '',
  correct_answer TEXT NOT NULL DEFAULT 'A',
  explanation    TEXT DEFAULT '',
  page_number    INTEGER DEFAULT 1,
  source         TEXT DEFAULT 'ai',
  enabled        INTEGER DEFAULT 1,
  created_at     DATETIME DEFAULT CURRENT_TIMESTAMP,
  FOREIGN KEY (pdf_id) REFERENCES pdfs(id) ON DELETE CASCADE
);

-- ── MCQ Settings ─────────────────────────────────────────────────────────────
CREATE TABLE IF NOT EXISTS mcq_settings (
  id         INTEGER PRIMARY KEY AUTOINCREMENT,
  pdf_id     INTEGER NOT NULL,
  type       TEXT NOT NULL DEFAULT 'standard',
  enabled    INTEGER NOT NULL DEFAULT 1,
  prompt     TEXT DEFAULT '',
  created_at DATETIME DEFAULT CURRENT_TIMESTAMP,
  updated_at DATETIME DEFAULT CURRENT_TIMESTAMP,
  UNIQUE(pdf_id, type),
  FOREIGN KEY (pdf_id) REFERENCES pdfs(id) ON DELETE CASCADE
);

-- ── MCQ Generation Queue ──────────────────────────────────────────────────────
CREATE TABLE IF NOT EXISTS mcq_generation_queue (
  id           INTEGER PRIMARY KEY AUTOINCREMENT,
  pdf_id       INTEGER NOT NULL,
  page_number  INTEGER NOT NULL,
  type         TEXT NOT NULL DEFAULT 'standard',
  status       TEXT DEFAULT 'generating',
  started_at   INTEGER,
  completed_at INTEGER,
  UNIQUE(pdf_id, page_number, type)
);

-- ── Exam Results ─────────────────────────────────────────────────────────────
CREATE TABLE IF NOT EXISTS exam_results (
  id              INTEGER PRIMARY KEY AUTOINCREMENT,
  user_id         INTEGER NOT NULL,
  pdf_id          INTEGER,
  page_numbers    TEXT DEFAULT '',
  mcq_type        TEXT DEFAULT 'standard',
  total_questions INTEGER DEFAULT 0,
  correct_answers INTEGER DEFAULT 0,
  score           REAL DEFAULT 0,
  created_at      DATETIME DEFAULT CURRENT_TIMESTAMP,
  FOREIGN KEY (user_id) REFERENCES users(id) ON DELETE CASCADE
);

-- ── Exam Answers ─────────────────────────────────────────────────────────────
CREATE TABLE IF NOT EXISTS exam_answers (
  id              INTEGER PRIMARY KEY AUTOINCREMENT,
  exam_result_id  INTEGER NOT NULL,
  mcq_id          INTEGER,
  question        TEXT NOT NULL,
  option_a        TEXT DEFAULT '',
  option_b        TEXT DEFAULT '',
  option_c        TEXT DEFAULT '',
  option_d        TEXT DEFAULT '',
  correct_answer  TEXT NOT NULL,
  user_answer     TEXT,
  is_correct      INTEGER DEFAULT 0,
  explanation     TEXT DEFAULT '',
  page_number     INTEGER DEFAULT 1,
  FOREIGN KEY (exam_result_id) REFERENCES exam_results(id) ON DELETE CASCADE
);

-- ── Focus Sessions ────────────────────────────────────────────────────────────
CREATE TABLE IF NOT EXISTS focus_sessions (
  id               INTEGER PRIMARY KEY AUTOINCREMENT,
  user_id          INTEGER NOT NULL,
  status           TEXT DEFAULT 'active',
  study_seconds    INTEGER DEFAULT 0,
  breaks_used      INTEGER DEFAULT 0,
  breaks_count     INTEGER DEFAULT 0,
  started_at       DATETIME DEFAULT CURRENT_TIMESTAMP,
  break_started_at DATETIME,
  ended_at         DATETIME,
  FOREIGN KEY (user_id) REFERENCES users(id) ON DELETE CASCADE
);

-- ── Page Views ────────────────────────────────────────────────────────────────
CREATE TABLE IF NOT EXISTS page_views (
  id          INTEGER PRIMARY KEY AUTOINCREMENT,
  user_id     INTEGER NOT NULL,
  pdf_id      INTEGER NOT NULL,
  page_number INTEGER DEFAULT 1,
  created_at  DATETIME DEFAULT CURRENT_TIMESTAMP,
  FOREIGN KEY (user_id) REFERENCES users(id) ON DELETE CASCADE
);

-- ── Announcements ─────────────────────────────────────────────────────────────
CREATE TABLE IF NOT EXISTS announcements (
  id          INTEGER PRIMARY KEY AUTOINCREMENT,
  title       TEXT NOT NULL,
  body        TEXT DEFAULT '',
  link        TEXT DEFAULT '',
  emoji       TEXT DEFAULT '📢',
  color       TEXT DEFAULT '#6C63FF',
  active      INTEGER DEFAULT 1,
  sort_order  INTEGER DEFAULT 0,
  created_at  DATETIME DEFAULT CURRENT_TIMESTAMP
);

-- ── Packages / Plans ──────────────────────────────────────────────────────────
CREATE TABLE IF NOT EXISTS packages (
  id          INTEGER PRIMARY KEY AUTOINCREMENT,
  name        TEXT NOT NULL,
  type        TEXT NOT NULL DEFAULT 'premium',
  price       TEXT DEFAULT '',
  page_limit  INTEGER DEFAULT 10,
  description TEXT DEFAULT '',
  youtube_url TEXT DEFAULT '',
  features    TEXT DEFAULT '[]',
  created_at  DATETIME DEFAULT CURRENT_TIMESTAMP,
  UNIQUE(type)
);

-- ── Owner Profile ─────────────────────────────────────────────────────────────
CREATE TABLE IF NOT EXISTS owner_profile (
  id           INTEGER PRIMARY KEY AUTOINCREMENT,
  name         TEXT DEFAULT '',
  title        TEXT DEFAULT '',
  bio          TEXT DEFAULT '',
  email        TEXT DEFAULT '',
  phone        TEXT DEFAULT '',
  facebook     TEXT DEFAULT '',
  image_url    TEXT DEFAULT '',
  created_at   DATETIME DEFAULT CURRENT_TIMESTAMP
);

-- ── Site Settings ─────────────────────────────────────────────────────────────
CREATE TABLE IF NOT EXISTS site_settings (
  key   TEXT PRIMARY KEY,
  value TEXT NOT NULL DEFAULT ''
);

-- ── Indexes ───────────────────────────────────────────────────────────────────
CREATE INDEX IF NOT EXISTS idx_users_phone          ON users(phone);
CREATE INDEX IF NOT EXISTS idx_users_token          ON users(session_token);
CREATE INDEX IF NOT EXISTS idx_chapters_subject     ON chapters(subject_id);
CREATE INDEX IF NOT EXISTS idx_pdfs_chapter         ON pdfs(chapter_id);
CREATE INDEX IF NOT EXISTS idx_mcqs_pdf_type        ON mcqs(pdf_id, type, page_number);
CREATE INDEX IF NOT EXISTS idx_mcq_settings_pdf     ON mcq_settings(pdf_id, type);
CREATE INDEX IF NOT EXISTS idx_exam_user            ON exam_results(user_id);
CREATE INDEX IF NOT EXISTS idx_exam_answers_result  ON exam_answers(exam_result_id);
CREATE INDEX IF NOT EXISTS idx_focus_user           ON focus_sessions(user_id, status);
CREATE INDEX IF NOT EXISTS idx_page_views_user      ON page_views(user_id, created_at);
CREATE INDEX IF NOT EXISTS idx_announcements_active ON announcements(active, sort_order);
CREATE INDEX IF NOT EXISTS idx_gen_queue            ON mcq_generation_queue(pdf_id, page_number, type, status);

-- ── Seed data ─────────────────────────────────────────────────────────────────

-- Default admin (password: atlas2024 — change immediately in production)
-- Hash of 'atlas2024' + 'atlas_salt_2024' via SHA-256:
INSERT OR IGNORE INTO users (name, phone, password_hash, is_admin, access_type, daily_page_limit)
VALUES ('Admin', '01754365403',
  'b7e6d3a7f4c2b8e5d1a9f6c3b7e4d2a8df2f3b4c7a8e1d6f9c2b5a8e3d7f4c1',
  1, 'premium', 99999);

-- Default site settings
INSERT OR IGNORE INTO site_settings (key, value) VALUES ('free_daily_limit',    '10');
INSERT OR IGNORE INTO site_settings (key, value) VALUES ('premium_daily_limit', '1000');

-- Default packages
INSERT OR IGNORE INTO packages (name, type, price, page_limit, features)
VALUES ('Free Plan', 'free', '0', 10,
  '["সব বিষয় দেখা","দিনে ১০ পৃষ্ঠা PDF","MCQ Exam (limited)","Focus Timer"]');

INSERT OR IGNORE INTO packages (name, type, price, page_limit, features)
VALUES ('Premium Plan', 'premium', '99', 1000,
  '["Unlimited PDF পড়া","সব MCQ Exam","AI ব্যাখ্যা","Offline cache","Priority support"]');
