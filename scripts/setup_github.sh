#!/bin/bash
# setup_github.sh — AtlasPro GitHub + Cloudflare setup script
# Run: chmod +x setup_github.sh && ./setup_github.sh

echo "📁 Setting up AtlasPro project structure..."

# ─── GitHub Repo Structure ─────────────────────────────────
# github.com/hamza818483-dotcom/AtlasPro
#
# AtlasPro/
# ├── workers/
# │   ├── main-worker.js
# │   ├── auth-worker.js
# │   ├── home-worker.js
# │   ├── pdf-worker.js
# │   ├── exam-worker.js
# │   ├── admin-worker.js
# │   ├── focus-profile-worker.js
# │   ├── public-worker.js
# │   └── mcq-cache-worker.js
# ├── sql/
# │   ├── schema.sql              (base - batch02)
# │   ├── schema_addon_batch05.sql
# │   ├── schema_addon_batch06.sql
# │   ├── schema_addon_batch07.sql
# │   ├── schema_addon_batch08.sql
# │   └── schema_addon_batch10.sql
# ├── flutter_app/               (Flutter source)
# │   ├── lib/
# │   ├── android/
# │   ├── pubspec.yaml
# │   └── ...
# ├── wrangler.toml
# └── README.md

# ─── Git init & push ──────────────────────────────────────
# git init
# git remote add origin https://github.com/hamza818483-dotcom/AtlasPro.git
# git add .
# git commit -m "Initial AtlasPro commit"
# git push -u origin main

# ─── Cloudflare D1 Setup ──────────────────────────────────
echo "Setting up Cloudflare D1..."
# npx wrangler d1 create atlaspro-db
# Copy database_id to wrangler.toml

# Run all SQL schemas in order:
# npx wrangler d1 execute atlaspro-db --file=sql/schema.sql
# npx wrangler d1 execute atlaspro-db --file=sql/schema_addon_batch05.sql
# npx wrangler d1 execute atlaspro-db --file=sql/schema_addon_batch06.sql
# npx wrangler d1 execute atlaspro-db --file=sql/schema_addon_batch07.sql
# npx wrangler d1 execute atlaspro-db --file=sql/schema_addon_batch08.sql
# npx wrangler d1 execute atlaspro-db --file=sql/schema_addon_batch10.sql

# ─── R2 Bucket Setup ──────────────────────────────────────
# npx wrangler r2 bucket create atlaspro-files

# ─── Secrets (API Keys) ───────────────────────────────────
# npx wrangler secret put GEMINI_KEY
# → AIzaSyBHfdZwqQkrBWF2pp1hLCGZKaXKrinP9ew

# npx wrangler secret put GROQ_KEY
# → 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

# npx wrangler secret put SUPABASE_URL
# → https://cctbwbipsoapskajoubr.supabase.co

# npx wrangler secret put SUPABASE_KEY
# → eyJhbGci...

# ─── Deploy Worker ────────────────────────────────────────
# npx wrangler deploy

# ─── Admin user seed ──────────────────────────────────────
# npx wrangler d1 execute atlaspro-db --command="
#   INSERT OR IGNORE INTO users (name, phone, password_hash, is_admin, access_type)
#   VALUES ('Admin', '01754365403', '1234atlas_hashed', 1, 'premium');
# "

echo "✅ Setup complete!"
echo "Worker URL: https://atlaspro-main.YOUR_SUBDOMAIN.workers.dev"
