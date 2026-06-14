-- schema_addon_batch08.sql

-- Focus Timer Sessions
CREATE TABLE IF NOT EXISTS focus_sessions (
  id INTEGER PRIMARY KEY AUTOINCREMENT,
  user_id INTEGER NOT NULL,
  status TEXT DEFAULT 'active', -- active, break, ended
  study_seconds INTEGER DEFAULT 0,
  breaks_used INTEGER DEFAULT 0,
  breaks_count INTEGER DEFAULT 0,
  started_at DATETIME DEFAULT CURRENT_TIMESTAMP,
  break_started_at DATETIME,
  ended_at DATETIME,
  FOREIGN KEY (user_id) REFERENCES users(id) ON DELETE CASCADE
);

-- Page View Tracking (for daily limit)
CREATE TABLE IF NOT EXISTS page_views (
  id INTEGER PRIMARY KEY AUTOINCREMENT,
  user_id INTEGER NOT NULL,
  pdf_id INTEGER NOT NULL,
  page_number INTEGER DEFAULT 1,
  created_at DATETIME DEFAULT CURRENT_TIMESTAMP,
  FOREIGN KEY (user_id) REFERENCES users(id) ON DELETE CASCADE
);

-- Exam Answers (for detailed history & practice)
CREATE TABLE IF NOT EXISTS exam_answers (
  id INTEGER PRIMARY KEY AUTOINCREMENT,
  exam_result_id INTEGER NOT NULL,
  mcq_id INTEGER,
  question TEXT NOT NULL,
  option_a TEXT DEFAULT '',
  option_b TEXT DEFAULT '',
  option_c TEXT DEFAULT '',
  option_d TEXT DEFAULT '',
  correct_answer TEXT NOT NULL,
  user_answer TEXT,
  is_correct INTEGER DEFAULT 0,
  explanation TEXT DEFAULT '',
  page_number INTEGER DEFAULT 1,
  FOREIGN KEY (exam_result_id) REFERENCES exam_results(id) ON DELETE CASCADE
);

-- Add columns to exam_results if not exist (run separately)
-- ALTER TABLE exam_results ADD COLUMN mcq_type TEXT DEFAULT 'standard';
-- ALTER TABLE exam_results ADD COLUMN page_numbers TEXT DEFAULT '';

-- Add columns to users if not exist (run separately)
-- ALTER TABLE users ADD COLUMN access_type TEXT DEFAULT 'free';
-- ALTER TABLE users ADD COLUMN daily_page_limit INTEGER DEFAULT 5;
-- ALTER TABLE users ADD COLUMN profile_pic TEXT;
-- ALTER TABLE users ADD COLUMN gender TEXT DEFAULT 'male';
-- ALTER TABLE users ADD COLUMN secondary_phone TEXT;
-- ALTER TABLE users ADD COLUMN social_link TEXT;
-- ALTER TABLE users ADD COLUMN ssc_gpa TEXT;
-- ALTER TABLE users ADD COLUMN hsc_gpa TEXT;

-- Indexes
CREATE INDEX IF NOT EXISTS idx_focus_sessions_user ON focus_sessions(user_id, status);
CREATE INDEX IF NOT EXISTS idx_page_views_user_date ON page_views(user_id, created_at);
CREATE INDEX IF NOT EXISTS idx_exam_answers_result ON exam_answers(exam_result_id);
