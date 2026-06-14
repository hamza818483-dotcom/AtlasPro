-- schema_addon_batch07.sql
-- Run this on Cloudflare D1 to add Batch 07 tables

-- MCQ Settings per PDF per type
CREATE TABLE IF NOT EXISTS mcq_settings (
  id INTEGER PRIMARY KEY AUTOINCREMENT,
  pdf_id INTEGER NOT NULL,
  type TEXT NOT NULL DEFAULT 'standard', -- standard, true_false, hard
  enabled INTEGER NOT NULL DEFAULT 1,
  prompt TEXT DEFAULT '',
  created_at DATETIME DEFAULT CURRENT_TIMESTAMP,
  updated_at DATETIME DEFAULT CURRENT_TIMESTAMP,
  UNIQUE(pdf_id, type),
  FOREIGN KEY (pdf_id) REFERENCES pdfs(id) ON DELETE CASCADE
);

-- MCQs table (if not exists from batch06)
CREATE TABLE IF NOT EXISTS mcqs (
  id INTEGER PRIMARY KEY AUTOINCREMENT,
  pdf_id INTEGER NOT NULL,
  type TEXT NOT NULL DEFAULT 'standard',
  question TEXT NOT NULL,
  option_a TEXT NOT NULL DEFAULT '',
  option_b TEXT NOT NULL DEFAULT '',
  option_c TEXT NOT NULL DEFAULT '',
  option_d TEXT NOT NULL DEFAULT '',
  correct_answer TEXT NOT NULL DEFAULT 'A',
  explanation TEXT DEFAULT '',
  page_number INTEGER DEFAULT 1,
  source TEXT DEFAULT 'ai', -- ai, manual, csv
  created_at DATETIME DEFAULT CURRENT_TIMESTAMP,
  FOREIGN KEY (pdf_id) REFERENCES pdfs(id) ON DELETE CASCADE
);

-- Announcements / Special Cards
CREATE TABLE IF NOT EXISTS announcements (
  id INTEGER PRIMARY KEY AUTOINCREMENT,
  title TEXT NOT NULL,
  body TEXT DEFAULT '',
  link TEXT DEFAULT '',
  emoji TEXT DEFAULT '📢',
  color TEXT DEFAULT '#6C63FF',
  active INTEGER DEFAULT 1,
  sort_order INTEGER DEFAULT 0,
  created_at DATETIME DEFAULT CURRENT_TIMESTAMP
);

-- Packages / Plans
CREATE TABLE IF NOT EXISTS packages (
  id INTEGER PRIMARY KEY AUTOINCREMENT,
  name TEXT NOT NULL,
  type TEXT NOT NULL DEFAULT 'premium', -- free, premium
  price TEXT DEFAULT '',
  description TEXT DEFAULT '',
  youtube_url TEXT DEFAULT '',
  features TEXT DEFAULT '',
  created_at DATETIME DEFAULT CURRENT_TIMESTAMP
);

-- Owner Profile
CREATE TABLE IF NOT EXISTS owner_profile (
  id INTEGER PRIMARY KEY AUTOINCREMENT,
  name TEXT DEFAULT '',
  title TEXT DEFAULT '',
  bio TEXT DEFAULT '',
  email TEXT DEFAULT '',
  phone TEXT DEFAULT '',
  facebook TEXT DEFAULT '',
  image_url TEXT DEFAULT '',
  created_at DATETIME DEFAULT CURRENT_TIMESTAMP
);

-- Site Settings (key-value)
CREATE TABLE IF NOT EXISTS site_settings (
  key TEXT PRIMARY KEY,
  value TEXT NOT NULL DEFAULT ''
);

-- Add columns to users table if not exists
-- (Run these individually if users table exists already)
-- ALTER TABLE users ADD COLUMN access_type TEXT DEFAULT 'free';
-- ALTER TABLE users ADD COLUMN daily_page_limit INTEGER DEFAULT 5;
-- ALTER TABLE users ADD COLUMN is_admin INTEGER DEFAULT 0;

-- Ensure admin user
-- UPDATE users SET is_admin=1 WHERE phone='01754365403';

-- Default site settings
INSERT OR IGNORE INTO site_settings (key, value) VALUES ('free_daily_limit', '5');
INSERT OR IGNORE INTO site_settings (key, value) VALUES ('premium_daily_limit', '100');

-- Indexes for performance
CREATE INDEX IF NOT EXISTS idx_mcqs_pdf_type ON mcqs(pdf_id, type, page_number);
CREATE INDEX IF NOT EXISTS idx_mcq_settings_pdf ON mcq_settings(pdf_id, type);
CREATE INDEX IF NOT EXISTS idx_announcements_active ON announcements(active, sort_order);
