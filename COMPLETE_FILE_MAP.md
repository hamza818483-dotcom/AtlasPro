# AtlasPro — সম্পূর্ণ File Map (Batch 01–14)
# GitHub repo: github.com/hamza818483-dotcom/AtlasPro

## ── FLUTTER APP (lib/) ────────────────────────────────────

lib/
├── main.dart                          → Batch 13
├── router.dart                        → Batch 14 ✅ FINAL
├── pubspec.yaml                       → Batch 13
│
├── core/
│   ├── theme.dart                     → Batch 13 (core_files.dart এ)
│   └── constants.dart                 → Batch 13 (core_files.dart এ)
│
├── services/
│   ├── auth_service.dart              → Batch 13
│   ├── access_service.dart            → Batch 08
│   └── offline_service.dart          → Batch 10
│
├── screens/
│   ├── splash_screen.dart            → Batch 14 ✅
│   ├── auth_screen.dart              → Batch 12
│   ├── home_screen.dart              → Batch 12
│   ├── course_screens.dart           → Batch 14 ✅ (CourseList + CourseDetail)
│   ├── chapter_subject_screens.dart  → Batch 12 (SubjectList + ChapterList)
│   ├── pdf_viewer_screen.dart        → Batch 12
│   ├── exam_screen.dart              → Batch 13
│   ├── exam_detail_screen.dart       → Batch 10
│   ├── profile_screen.dart           → Batch 08
│   ├── focus_timer_screen.dart       → Batch 08
│   ├── packages_screen.dart          → Batch 09
│   ├── offline_cache_screen.dart     → Batch 10
│   ├── page_access_gate.dart         → Batch 08
│   └── admin/
│       ├── admin_panel_screen.dart   → Batch 07
│       ├── admin_subjects_screen.dart → Batch 07
│       ├── admin_mcq_screen.dart     → Batch 07
│       ├── admin_users_screen.dart   → Batch 07
│       ├── admin_owner_screen.dart   → Batch 07
│       ├── admin_announcements_screen.dart → Batch 07
│       └── admin_packages_screen.dart → Batch 07
│
└── widgets/
    ├── owner_flip_card.dart          → Batch 09
    ├── announcement_slideshow.dart   → Batch 09
    └── app_sidebar.dart              → Batch 09

## ── WORKERS ──────────────────────────────────────────────

workers/
├── main-worker.js           → Batch 14 ✅ FINAL (FIXED imports)
├── utils.js                 → Batch 14 ✅
├── auth-worker.js           → Batch 13 (register+login+exam submit+answers)
├── home-pdf-worker.js       → Batch 12 (subjects+chapters+pdfs+mcq+download)
├── admin-worker.js          → Batch 07
├── focus-profile-worker.js  → Batch 08
├── public-worker.js         → Batch 09
└── mcq-cache-worker.js      → Batch 10 (reference only, logic in home-pdf-worker)

## ── SQL (run in order) ───────────────────────────────────

sql/
├── schema.sql                    → Batch 02
├── schema_addon_batch05.sql      → Batch 05
├── schema_addon_batch06.sql      → Batch 06
├── schema_addon_batch07.sql      → Batch 07
├── schema_addon_batch08.sql      → Batch 08
└── schema_addon_batch10.sql      → Batch 10

## ── CONFIG ───────────────────────────────────────────────

├── wrangler.toml               → Batch 11
├── .gitignore                  → Batch 11
├── android/app/build.gradle    → Batch 11
└── scripts/setup_github.sh     → Batch 11

## ── DEPLOY STEPS ─────────────────────────────────────────

1. npx wrangler d1 create atlaspro-db
   → D1 ID → wrangler.toml এ বসাও

2. SQL files run করো (order অনুযায়ী):
   npx wrangler d1 execute atlaspro-db --file=sql/schema.sql
   npx wrangler d1 execute atlaspro-db --file=sql/schema_addon_batch05.sql
   npx wrangler d1 execute atlaspro-db --file=sql/schema_addon_batch06.sql
   npx wrangler d1 execute atlaspro-db --file=sql/schema_addon_batch07.sql
   npx wrangler d1 execute atlaspro-db --file=sql/schema_addon_batch08.sql
   npx wrangler d1 execute atlaspro-db --file=sql/schema_addon_batch10.sql

3. ALTER TABLE (D1 console এ manually):
   ALTER TABLE users ADD COLUMN access_type TEXT DEFAULT 'free';
   ALTER TABLE users ADD COLUMN daily_page_limit INTEGER DEFAULT 5;
   ALTER TABLE users ADD COLUMN is_admin INTEGER DEFAULT 0;
   ALTER TABLE users ADD COLUMN profile_pic TEXT;
   ALTER TABLE users ADD COLUMN gender TEXT DEFAULT 'male';
   ALTER TABLE users ADD COLUMN secondary_phone TEXT;
   ALTER TABLE users ADD COLUMN social_link TEXT;
   ALTER TABLE users ADD COLUMN ssc_gpa TEXT;
   ALTER TABLE users ADD COLUMN hsc_gpa TEXT;
   ALTER TABLE users ADD COLUMN hsc_batch TEXT;
   ALTER TABLE users ADD COLUMN college_name TEXT;
   ALTER TABLE users ADD COLUMN father_name TEXT;
   ALTER TABLE users ADD COLUMN mother_name TEXT;
   ALTER TABLE exam_results ADD COLUMN mcq_type TEXT DEFAULT 'standard';
   ALTER TABLE exam_results ADD COLUMN page_numbers TEXT DEFAULT '';

4. R2 bucket:
   npx wrangler r2 bucket create atlaspro-files

5. Secrets:
   npx wrangler secret put GEMINI_KEY
   npx wrangler secret put GROQ_KEY

6. Deploy:
   npx wrangler deploy

7. constants.dart এ workerBaseUrl বসাও

8. Flutter build:
   flutter pub get
   flutter build apk --release
