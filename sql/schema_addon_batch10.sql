-- schema_addon_batch10.sql

-- MCQ Generation Queue (ETA + status tracking)
CREATE TABLE IF NOT EXISTS mcq_generation_queue (
  id INTEGER PRIMARY KEY AUTOINCREMENT,
  pdf_id INTEGER NOT NULL,
  page_number INTEGER NOT NULL,
  type TEXT NOT NULL DEFAULT 'standard',
  status TEXT DEFAULT 'generating', -- generating, done, failed
  started_at INTEGER,
  completed_at INTEGER,
  UNIQUE(pdf_id, page_number, type)
);

-- Index for fast MCQ lookup
CREATE INDEX IF NOT EXISTS idx_mcqs_unique ON mcqs(pdf_id, page_number, type, id);
CREATE INDEX IF NOT EXISTS idx_gen_queue ON mcq_generation_queue(pdf_id, page_number, type, status);
