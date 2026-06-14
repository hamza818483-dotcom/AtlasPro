-- schema.sql — AtlasPro Base Schema (Batch 02)
-- Run FIRST before all other SQL files

CREATE TABLE IF NOT EXISTS users (
  id INTEGER PRIMARY KEY AUTOINCREMENT,
  name TEXT NOT NULL,
  father_name TEXT DEFAULT '',
  mother_name TEXT DEFAULT '',
  hsc_batch TEXT DEFAULT '',
  college_name TEXT DEFAULT '',
  ssc_gpa TEXT DEFAULT '',
  hsc_gpa TEXT DEFAULT '',
  phone TEXT UNIQUE NOT NULL,
  secondary_phone TEXT DEFAULT '',
  social_link TEXT DEFAULT '',
  password_hash TEXT NOT NULL,
  gender TEXT DEFAULT 'male',
  profile_pic TEXT,
  session_token TEXT,
  access_type TEXT DEFAULT 'free',
  daily_page_limit INTEGER DEFAULT 5,
  is_admin INTEGER DEFAULT 0,
  created_at DATETIME DEFAULT CURRENT_TIMESTAMP
);

CREATE TABLE IF NOT EXISTS subjects (
  id INTEGER PRIMARY KEY AUTOINCREMENT,
  name TEXT NOT NULL,
  description TEXT DEFAULT '',
  icon TEXT DEFAULT '📚',
  order_index INTEGER DEFAULT 0,
  created_at DATETIME DEFAULT CURRENT_TIMESTAMP
);

CREATE TABLE IF NOT EXISTS chapters (
  id INTEGER PRIMARY KEY AUTOINCREMENT,
  subject_id INTEGER NOT NULL,
  name TEXT NOT NULL,
  order_index INTEGER DEFAULT 0,
  created_at DATETIME DEFAULT CURRENT_TIMESTAMP,
  FOREIGN KEY (subject_id) REFERENCES subjects(id) ON DELETE CASCADE
);

CREATE TABLE IF NOT EXISTS pdfs (
  id INTEGER PRIMARY KEY AUTOINCREMENT,
  chapter_id INTEGER NOT NULL,
  title TEXT NOT NULL,
  r2_key TEXT,
  r2_url TEXT,
  page_count INTEGER DEFAULT 0,
  file_size INTEGER DEFAULT 0,
  created_at DATETIME DEFAULT CURRENT_TIMESTAMP,
  FOREIGN KEY (chapter_id) REFERENCES chapters(id) ON DELETE CASCADE
);

CREATE TABLE IF NOT EXISTS exam_results (
  id INTEGER PRIMARY KEY AUTOINCREMENT,
  user_id INTEGER NOT NULL,
  pdf_id INTEGER,
  page_numbers TEXT DEFAULT '',
  mcq_type TEXT DEFAULT 'standard',
  total_questions INTEGER DEFAULT 0,
  correct_answers INTEGER DEFAULT 0,
  score REAL DEFAULT 0,
  created_at DATETIME DEFAULT CURRENT_TIMESTAMP,
  FOREIGN KEY (user_id) REFERENCES users(id) ON DELETE CASCADE
);

-- Admin seed
INSERT OR IGNORE INTO users (name, phone, password_hash, is_admin, access_type, daily_page_limit)
VALUES (
  'Admin', '01754365403',
  'df2f3b4c7a8e1d6f9c2b5a8e3d7f4c1b9e6d3a7f4c2b8e5d1a9f6c3b7e4d2a8',
  1, 'premium', 1000
);

CREATE INDEX IF NOT EXISTS idx_users_phone ON users(phone);
CREATE INDEX IF NOT EXISTS idx_chapters_subject ON chapters(subject_id);
CREATE INDEX IF NOT EXISTS idx_pdfs_chapter ON pdfs(chapter_id);
CREATE INDEX IF NOT EXISTS idx_exam_user ON exam_results(user_id);
