-- schema_addon_batch06.sql — Exam sessions
CREATE TABLE IF NOT EXISTS exam_sessions (
  id INTEGER PRIMARY KEY AUTOINCREMENT,
  user_id INTEGER NOT NULL,
  pdf_id INTEGER,
  page_numbers TEXT DEFAULT '',
  mcq_type TEXT DEFAULT 'standard',
  status TEXT DEFAULT 'active',
  started_at DATETIME DEFAULT CURRENT_TIMESTAMP,
  FOREIGN KEY (user_id) REFERENCES users(id) ON DELETE CASCADE
);
