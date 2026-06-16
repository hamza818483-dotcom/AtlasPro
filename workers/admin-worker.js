// admin-worker.js — AtlasPro Admin API
// Handles: subjects, chapters, pdfs, mcq, users, announcements, packages, owner, settings

export default {
  async fetch(request, env) {
    const url = new URL(request.url);
    const path = url.pathname;
    const method = request.method;

    // CORS
    const corsHeaders = {
      'Access-Control-Allow-Origin': '*',
      'Access-Control-Allow-Methods': 'GET, POST, PUT, DELETE, OPTIONS',
      'Access-Control-Allow-Headers': 'Content-Type, Authorization',
    };
    if (method === 'OPTIONS') return new Response(null, { headers: corsHeaders });

    const json = (data, status = 200) =>
      new Response(JSON.stringify(data), {
        status,
        headers: { ...corsHeaders, 'Content-Type': 'application/json' },
      });

    // Auth check
    const authHeader = request.headers.get('Authorization') || '';
    const token = authHeader.replace('Bearer ', '');
    if (!token) return json({ error: 'Unauthorized' }, 401);

    const userRow = await env.DB.prepare(
      'SELECT * FROM users WHERE session_token=? AND is_admin=1'
    ).bind(token).first();
    if (!userRow) return json({ error: 'Admin only' }, 403);

    // Helper: relative time string
    const relativeTime = (dateStr) => {
      if (!dateStr) return 'অজানা';
      const diff = Date.now() - new Date(dateStr).getTime();
      const mins = Math.floor(diff / 60000);
      if (mins < 1) return 'এইমাত্র';
      if (mins < 60) return `${mins} মিনিট আগে`;
      const hrs = Math.floor(mins / 60);
      if (hrs < 24) return `${hrs} ঘণ্টা আগে`;
      const days = Math.floor(hrs / 24);
      return `${days} দিন আগে`;
    };

    try {
      // ===== STATS =====
      if (path === '/api/admin/stats' && method === 'GET') {
        const totalUsers = await env.DB.prepare(
          'SELECT COUNT(*) as cnt FROM users WHERE is_admin=0'
        ).first();
        const totalPdfs = await env.DB.prepare(
          'SELECT COUNT(*) as cnt FROM pdfs'
        ).first();
        const totalMcq = await env.DB.prepare(
          'SELECT COUNT(*) as cnt FROM mcqs'
        ).first();
        const activeToday = await env.DB.prepare(
          "SELECT COUNT(DISTINCT user_id) as cnt FROM page_views WHERE date(created_at)=date('now')"
        ).first();
        return json({
          total_users: totalUsers?.cnt ?? 0,
          total_pdfs: totalPdfs?.cnt ?? 0,
          total_mcq: totalMcq?.cnt ?? 0,
          active_today: activeToday?.cnt ?? 0,
        });
      }

      // ===== ACTIVITY =====
      if (path === '/api/admin/activity' && method === 'GET') {
        const { results: newUsers } = await env.DB.prepare(
          'SELECT name, created_at FROM users WHERE is_admin=0 ORDER BY created_at DESC LIMIT 5'
        ).all();
        const { results: examResults } = await env.DB.prepare(
          'SELECT u.name, er.created_at FROM exam_results er LEFT JOIN users u ON er.user_id=u.id ORDER BY er.created_at DESC LIMIT 5'
        ).all();

        const activities = [
          ...newUsers.map(u => ({
            icon: '👤',
            message: `নতুন user নিবন্ধন: ${u.name || 'অজানা'}`,
            time: relativeTime(u.created_at),
            _ts: new Date(u.created_at).getTime(),
          })),
          ...examResults.map(r => ({
            icon: '📝',
            message: `${r.name || 'অজানা'} পরীক্ষা দিয়েছে`,
            time: relativeTime(r.created_at),
            _ts: new Date(r.created_at).getTime(),
          })),
        ];

        activities.sort((a, b) => b._ts - a._ts);
        const trimmed = activities.slice(0, 10).map(({ _ts, ...rest }) => rest);
        return json({ activities: trimmed });
      }

      // ===== USER STATS =====
      if (path === '/api/admin/user-stats' && method === 'GET') {
        const premium = await env.DB.prepare(
          "SELECT COUNT(*) as cnt FROM users WHERE access_type='premium' AND is_admin=0"
        ).first();
        const total = await env.DB.prepare(
          'SELECT COUNT(*) as cnt FROM users WHERE is_admin=0'
        ).first();
        return json({
          premium: premium?.cnt ?? 0,
          total: total?.cnt ?? 0,
        });
      }

      // ===== SUBJECTS =====
      if (path === '/api/admin/subjects' && method === 'GET') {
        const { results } = await env.DB.prepare(
          'SELECT * FROM subjects ORDER BY order_index ASC, created_at DESC'
        ).all();
        return json({ subjects: results });
      }

      if (path === '/api/admin/subjects' && method === 'POST') {
        const body = await request.json();
        const { name, description, icon, order_index = 0 } = body;
        const res = await env.DB.prepare(
          'INSERT INTO subjects (name, description, icon, order_index) VALUES (?,?,?,?)'
        ).bind(name, description || '', icon || '📚', order_index).run();
        return json({ id: res.meta.last_row_id, message: 'Created' }, 201);
      }

      if (path.match(/^\/api\/admin\/subjects\/\d+$/) && method === 'PUT') {
        const id = path.split('/').pop();
        const body = await request.json();
        await env.DB.prepare(
          'UPDATE subjects SET name=?, description=?, icon=? WHERE id=?'
        ).bind(body.name, body.description || '', body.icon || '📚', id).run();
        return json({ message: 'Updated' });
      }

      if (path.match(/^\/api\/admin\/subjects\/\d+$/) && method === 'DELETE') {
        const id = path.split('/').pop();
        await env.DB.prepare('DELETE FROM subjects WHERE id=?').bind(id).run();
        return json({ message: 'Deleted' });
      }

      // ===== CHAPTERS =====
      if (path === '/api/admin/chapters' && method === 'GET') {
        const subjectId = url.searchParams.get('subject_id');
        const { results } = await env.DB.prepare(
          'SELECT * FROM chapters WHERE subject_id=? ORDER BY order_index ASC'
        ).bind(subjectId).all();
        return json({ chapters: results });
      }

      if (path === '/api/admin/chapters' && method === 'POST') {
        const body = await request.json();
        const res = await env.DB.prepare(
          'INSERT INTO chapters (subject_id, name, order_index) VALUES (?,?,?)'
        ).bind(body.subject_id, body.name, body.order_index || 1).run();
        return json({ id: res.meta.last_row_id }, 201);
      }

      if (path.match(/^\/api\/admin\/chapters\/\d+$/) && method === 'PUT') {
        const id = path.split('/').pop();
        const body = await request.json();
        await env.DB.prepare(
          'UPDATE chapters SET name=?, order_index=? WHERE id=?'
        ).bind(body.name, body.order_index || 1, id).run();
        return json({ message: 'Updated' });
      }

      if (path.match(/^\/api\/admin\/chapters\/\d+$/) && method === 'DELETE') {
        const id = path.split('/').pop();
        await env.DB.prepare('DELETE FROM chapters WHERE id=?').bind(id).run();
        return json({ message: 'Deleted' });
      }

      // ===== PDFs =====
      if (path === '/api/admin/pdfs' && method === 'GET') {
        const chapterId = url.searchParams.get('chapter_id');
        const { results } = await env.DB.prepare(
          'SELECT * FROM pdfs WHERE chapter_id=? ORDER BY created_at DESC'
        ).bind(chapterId).all();
        return json({ pdfs: results });
      }

      if (path === '/api/admin/pdfs/all' && method === 'GET') {
        const { results } = await env.DB.prepare(`
          SELECT p.*, c.name as chapter_name, s.name as subject_name
          FROM pdfs p
          LEFT JOIN chapters c ON p.chapter_id = c.id
          LEFT JOIN subjects s ON c.subject_id = s.id
          ORDER BY p.created_at DESC
        `).all();
        return json({ pdfs: results });
      }

      if (path === '/api/admin/pdfs/upload' && method === 'POST') {
        const formData = await request.formData();
        const file = formData.get('file');
        const chapterId = formData.get('chapter_id');
        const title = formData.get('title') || file.name.replace('.pdf', '');

        if (!file) return json({ error: 'No file' }, 400);

        const key = `pdfs/${Date.now()}_${file.name}`;
        const buffer = await file.arrayBuffer();
        await env.R2.put(key, buffer, {
          httpMetadata: { contentType: 'application/pdf' },
        });

        const r2Url = `https://${env.R2_PUBLIC_DOMAIN}/${key}`;
        const res = await env.DB.prepare(
          'INSERT INTO pdfs (chapter_id, title, r2_key, r2_url, file_size) VALUES (?,?,?,?,?)'
        ).bind(chapterId, title, key, r2Url, buffer.byteLength).run();

        return json({ id: res.meta.last_row_id, url: r2Url }, 201);
      }

      if (path.match(/^\/api\/admin\/pdfs\/\d+$/) && method === 'DELETE') {
        const id = path.split('/').pop();
        const pdf = await env.DB.prepare('SELECT r2_key FROM pdfs WHERE id=?').bind(id).first();
        if (pdf?.r2_key) await env.R2.delete(pdf.r2_key);
        await env.DB.prepare('DELETE FROM pdfs WHERE id=?').bind(id).run();
        return json({ message: 'Deleted' });
      }

      // ===== MCQ =====
      if (path === '/api/admin/mcq' && method === 'GET') {
        const pdfId = url.searchParams.get('pdf_id');
        const type = url.searchParams.get('type') || 'standard';
        const { results } = await env.DB.prepare(
          'SELECT * FROM mcqs WHERE pdf_id=? AND type=? ORDER BY page_number ASC, id ASC'
        ).bind(pdfId, type).all();
        const settings = await env.DB.prepare(
          'SELECT * FROM mcq_settings WHERE pdf_id=? AND type=?'
        ).bind(pdfId, type).first();
        return json({ mcqs: results, settings: settings || {} });
      }

      if (path === '/api/admin/mcq' && method === 'POST') {
        const body = await request.json();
        const res = await env.DB.prepare(`
          INSERT INTO mcqs (pdf_id, type, question, option_a, option_b, option_c, option_d, correct_answer, explanation, page_number)
          VALUES (?,?,?,?,?,?,?,?,?,?)
        `).bind(
          body.pdf_id, body.type || 'standard', body.question,
          body.option_a, body.option_b, body.option_c, body.option_d,
          body.correct_answer, body.explanation || '', body.page_number || 1
        ).run();
        return json({ id: res.meta.last_row_id }, 201);
      }

      if (path.match(/^\/api\/admin\/mcq\/\d+$/) && method === 'PUT') {
        const id = path.split('/').pop();
        const body = await request.json();
        await env.DB.prepare(`
          UPDATE mcqs SET question=?, option_a=?, option_b=?, option_c=?, option_d=?,
          correct_answer=?, explanation=?, page_number=? WHERE id=?
        `).bind(
          body.question, body.option_a, body.option_b, body.option_c, body.option_d,
          body.correct_answer, body.explanation || '', body.page_number || 1, id
        ).run();
        return json({ message: 'Updated' });
      }

      if (path.match(/^\/api\/admin\/mcq\/\d+$/) && method === 'DELETE') {
        const id = path.split('/').pop();
        await env.DB.prepare('DELETE FROM mcqs WHERE id=?').bind(id).run();
        return json({ message: 'Deleted' });
      }

      // MCQ Settings (enable/disable type per PDF)
      if (path === '/api/admin/mcq/settings' && method === 'PUT') {
        const body = await request.json();
        await env.DB.prepare(`
          INSERT INTO mcq_settings (pdf_id, type, enabled, prompt)
          VALUES (?,?,?,?)
          ON CONFLICT(pdf_id, type) DO UPDATE SET enabled=excluded.enabled, prompt=excluded.prompt
        `).bind(body.pdf_id, body.type, body.enabled ? 1 : 0, body.prompt || '').run();
        return json({ message: 'Updated' });
      }

      // MCQ Generate via AI
      if (path === '/api/admin/mcq/generate' && method === 'POST') {
        const body = await request.json();
        const { pdf_id, page_number, type, prompt } = body;

        // Check if already generated
        const existing = await env.DB.prepare(
          'SELECT COUNT(*) as count FROM mcqs WHERE pdf_id=? AND page_number=? AND type=?'
        ).bind(pdf_id, page_number, type).first();

        if (existing?.count >= 2) {
          const { results } = await env.DB.prepare(
            'SELECT * FROM mcqs WHERE pdf_id=? AND page_number=? AND type=? LIMIT 10'
          ).bind(pdf_id, page_number, type).all();
          return json({ mcqs: results, from_cache: true });
        }

        const pdf = await env.DB.prepare('SELECT r2_url FROM pdfs WHERE id=?').bind(pdf_id).first();
        if (!pdf) return json({ error: 'PDF not found' }, 404);

        const geminiPrompt = `${prompt}\n\nContent: Page ${page_number} of the educational PDF.\n\nReturn ONLY a JSON array like: [{"question":"...","option_a":"...","option_b":"...","option_c":"...","option_d":"...","correct_answer":"A","explanation":"..."}]`;

        let mcqs = [];
        try {
          const geminiRes = await fetch(
            `https://generativelanguage.googleapis.com/v1beta/models/gemini-2.0-flash:generateContent?key=${env.GEMINI_KEY}`,
            {
              method: 'POST',
              headers: { 'Content-Type': 'application/json' },
              body: JSON.stringify({
                contents: [{ parts: [{ text: geminiPrompt }] }],
                generationConfig: { maxOutputTokens: 2048 },
              }),
            }
          );
          const gData = await geminiRes.json();
          const text = gData.candidates?.[0]?.content?.parts?.[0]?.text || '[]';
          const jsonMatch = text.match(/\[[\s\S]*\]/);
          if (jsonMatch) mcqs = JSON.parse(jsonMatch[0]);
        } catch (e) {
          try {
            const groqRes = await fetch('https://api.groq.com/openai/v1/chat/completions', {
              method: 'POST',
              headers: {
                'Content-Type': 'application/json',
                'Authorization': `Bearer ${env.GROQ_KEY}`,
              },
              body: JSON.stringify({
                model: 'llama3-8b-8192',
                messages: [{ role: 'user', content: geminiPrompt }],
                max_tokens: 2048,
              }),
            });
            const gData = await groqRes.json();
            const text = gData.choices?.[0]?.message?.content || '[]';
            const jsonMatch = text.match(/\[[\s\S]*\]/);
            if (jsonMatch) mcqs = JSON.parse(jsonMatch[0]);
          } catch (_) {}
        }

        for (const mcq of mcqs) {
          await env.DB.prepare(`
            INSERT INTO mcqs (pdf_id, type, question, option_a, option_b, option_c, option_d, correct_answer, explanation, page_number)
            VALUES (?,?,?,?,?,?,?,?,?,?)
          `).bind(
            pdf_id, type,
            mcq.question || '', mcq.option_a || '', mcq.option_b || '',
            mcq.option_c || '', mcq.option_d || '',
            mcq.correct_answer || 'A', mcq.explanation || '', page_number
          ).run();
        }

        return json({ count: mcqs.length, mcqs });
      }

      // MCQ CSV Upload
      if (path === '/api/admin/mcq/csv' && method === 'POST') {
        const formData = await request.formData();
        const file = formData.get('file');
        const pdfId = formData.get('pdf_id');
        const type = formData.get('type') || 'standard';
        const pageNumber = parseInt(formData.get('page_number') || '1');

        const csvText = await file.text();
        const lines = csvText.split('\n').filter(l => l.trim());
        const headers = lines[0].split(',').map(h => h.trim().toLowerCase());

        let count = 0;
        for (let i = 1; i < lines.length; i++) {
          const cols = lines[i].split(',');
          const row = {};
          headers.forEach((h, idx) => row[h] = (cols[idx] || '').trim());

          if (!row.question) continue;
          await env.DB.prepare(`
            INSERT INTO mcqs (pdf_id, type, question, option_a, option_b, option_c, option_d, correct_answer, explanation, page_number)
            VALUES (?,?,?,?,?,?,?,?,?,?)
          `).bind(
            pdfId, type, row.question,
            row.option_a || row.a || '', row.option_b || row.b || '',
            row.option_c || row.c || '', row.option_d || row.d || '',
            (row.correct_answer || row.answer || 'A').toUpperCase(),
            row.explanation || '', pageNumber
          ).run();
          count++;
        }

        return json({ count, message: `${count} MCQs imported` }, 201);
      }

      // ===== USERS =====
      if (path === '/api/admin/users' && method === 'GET') {
        const { results } = await env.DB.prepare(`
          SELECT u.*,
            COALESCE(ul.pages_used, 0) as pages_used_today
          FROM users u
          LEFT JOIN (
            SELECT user_id, COUNT(*) as pages_used
            FROM page_views
            WHERE date(created_at) = date('now')
            GROUP BY user_id
          ) ul ON ul.user_id = u.id
          WHERE u.is_admin = 0
          ORDER BY u.created_at DESC
        `).all();
        return json({ users: results });
      }

      if (path.match(/^\/api\/admin\/users\/\d+\/access$/) && method === 'PUT') {
        const id = path.split('/')[4];
        const body = await request.json();
        await env.DB.prepare(
          'UPDATE users SET access_type=? WHERE id=?'
        ).bind(body.access_type, id).run();
        return json({ message: 'Updated' });
      }

      if (path.match(/^\/api\/admin\/users\/\d+\/limit$/) && method === 'PUT') {
        const id = path.split('/')[4];
        const body = await request.json();
        await env.DB.prepare(
          'UPDATE users SET daily_page_limit=? WHERE id=?'
        ).bind(body.daily_page_limit, id).run();
        return json({ message: 'Updated' });
      }

      // Fix #7: Toggle premium status for a user
      if (path.match(/^\/api\/admin\/users\/\d+\/premium$/) && method === 'PUT') {
        const id = path.split('/')[4];
        const body = await request.json();
        const isPremium = body.is_premium === true || body.is_premium === 1;
        const accessType = isPremium ? 'premium' : 'free';
        const pageLimit = isPremium ? 1000 : 10;
        await env.DB.prepare(
          'UPDATE users SET access_type=?, daily_page_limit=? WHERE id=?'
        ).bind(accessType, pageLimit, id).run();
        return json({ message: 'Updated' });
      }

      // ===== GLOBAL SETTINGS =====
      if (path === '/api/admin/settings/limits' && method === 'GET') {
        const settings = await env.DB.prepare('SELECT * FROM site_settings WHERE key IN (?,?)')
          .bind('free_daily_limit', 'premium_daily_limit').all();
        const mapped = {};
        (settings.results || []).forEach(s => mapped[s.key] = s.value);
        return json({
          settings: {
            free_daily_limit: parseInt(mapped.free_daily_limit || '5'),
            premium_daily_limit: parseInt(mapped.premium_daily_limit || '100'),
          },
        });
      }

      if (path === '/api/admin/settings/limits' && method === 'PUT') {
        const body = await request.json();
        for (const [k, v] of Object.entries({
          free_daily_limit: body.free_daily_limit,
          premium_daily_limit: body.premium_daily_limit,
        })) {
          await env.DB.prepare(`
            INSERT INTO site_settings (key, value) VALUES (?,?)
            ON CONFLICT(key) DO UPDATE SET value=excluded.value
          `).bind(k, String(v)).run();
        }
        return json({ message: 'Updated' });
      }

      // ===== ANNOUNCEMENTS =====
      // Fix #8: Accept both `content` and `body` from frontend; return both fields in GET
      if (path === '/api/admin/announcements' && method === 'GET') {
        const { results } = await env.DB.prepare(
          'SELECT * FROM announcements ORDER BY sort_order ASC, created_at DESC'
        ).all();
        return json({
          announcements: results.map(r => ({
            ...r,
            active: r.active === 1,
            content: r.body,   // alias for frontend compatibility
          })),
        });
      }

      if (path === '/api/admin/announcements' && method === 'POST') {
        const body = await request.json();
        const bodyText = body.content ?? body.body ?? '';
        const res = await env.DB.prepare(`
          INSERT INTO announcements (title, body, link, emoji, color, active)
          VALUES (?,?,?,?,?,?)
        `).bind(
          body.title,
          bodyText,
          body.link || '',
          body.emoji || '📢',
          body.color || '#6C63FF',
          body.active ? 1 : 0
        ).run();
        return json({ id: res.meta.last_row_id }, 201);
      }

      if (path.match(/^\/api\/admin\/announcements\/\d+$/) && method === 'PUT') {
        const id = path.split('/').pop();
        const body = await request.json();
        const bodyText = body.content ?? body.body ?? '';
        await env.DB.prepare(`
          UPDATE announcements SET title=?, body=?, link=?, emoji=?, color=?, active=? WHERE id=?
        `).bind(
          body.title,
          bodyText,
          body.link || '',
          body.emoji || '📢',
          body.color || '#6C63FF',
          body.active ? 1 : 0,
          id
        ).run();
        return json({ message: 'Updated' });
      }

      if (path.match(/^\/api\/admin\/announcements\/\d+$/) && method === 'DELETE') {
        const id = path.split('/').pop();
        await env.DB.prepare('DELETE FROM announcements WHERE id=?').bind(id).run();
        return json({ message: 'Deleted' });
      }

      if (path === '/api/admin/announcements/order' && method === 'PUT') {
        const body = await request.json();
        const { order } = body;
        for (let i = 0; i < order.length; i++) {
          await env.DB.prepare('UPDATE announcements SET sort_order=? WHERE id=?').bind(i, order[i]).run();
        }
        return json({ message: 'Order updated' });
      }

      // ===== PACKAGES =====
      // Fix #4: Return structured {free, premium} object instead of list
      if (path === '/api/admin/packages' && method === 'GET') {
        const freeRow = await env.DB.prepare(
          "SELECT * FROM packages WHERE type='free' LIMIT 1"
        ).first();
        const premiumRow = await env.DB.prepare(
          "SELECT * FROM packages WHERE type='premium' LIMIT 1"
        ).first();

        const parseFeatures = (val) => {
          if (!val) return [];
          try { return JSON.parse(val); } catch (_) { return []; }
        };

        return json({
          free: {
            name: freeRow?.name || 'Free Plan',
            page_limit: freeRow?.page_limit ?? freeRow?.price ?? 10,
            features: parseFeatures(freeRow?.features),
          },
          premium: {
            name: premiumRow?.name || 'Premium Plan',
            price: premiumRow?.price || '',
            features: parseFeatures(premiumRow?.features),
          },
        });
      }

      // Fix #5: PUT /api/admin/packages/free — upsert free plan
      if (path === '/api/admin/packages/free' && method === 'PUT') {
        const body = await request.json();
        const featuresJson = JSON.stringify(Array.isArray(body.features) ? body.features : []);
        const pageLimit = body.page_limit ?? 10;
        await env.DB.prepare(`
          INSERT INTO packages (name, page_limit, features, type, price)
          VALUES (?, ?, ?, 'free', ?)
          ON CONFLICT(type) DO UPDATE SET name=excluded.name, page_limit=excluded.page_limit, features=excluded.features, price=excluded.price
        `).bind(body.name || 'Free Plan', pageLimit, featuresJson, String(pageLimit)).run();
        return json({ message: 'Updated' });
      }

      // Fix #6: PUT /api/admin/packages/premium — upsert premium plan
      if (path === '/api/admin/packages/premium' && method === 'PUT') {
        const body = await request.json();
        const featuresJson = JSON.stringify(Array.isArray(body.features) ? body.features : []);
        await env.DB.prepare(`
          INSERT INTO packages (name, price, features, type, page_limit)
          VALUES (?, ?, ?, 'premium', 1000)
          ON CONFLICT(type) DO UPDATE SET name=excluded.name, price=excluded.price, features=excluded.features
        `).bind(body.name || 'Premium Plan', String(body.price || ''), featuresJson).run();
        return json({ message: 'Updated' });
      }

      // Legacy package routes (kept for backward compatibility)
      if (path === '/api/admin/packages' && method === 'POST') {
        const body = await request.json();
        const res = await env.DB.prepare(`
          INSERT INTO packages (name, price, description, youtube_url, features, type)
          VALUES (?,?,?,?,?,?)
        `).bind(
          body.name, body.price || '', body.description || '',
          body.youtube_url || '',
          typeof body.features === 'object' ? JSON.stringify(body.features) : (body.features || ''),
          body.type || 'premium'
        ).run();
        return json({ id: res.meta.last_row_id }, 201);
      }

      if (path.match(/^\/api\/admin\/packages\/\d+$/) && method === 'PUT') {
        const id = path.split('/').pop();
        const body = await request.json();
        await env.DB.prepare(`
          UPDATE packages SET name=?, price=?, description=?, youtube_url=?, features=?, type=? WHERE id=?
        `).bind(
          body.name, body.price || '', body.description || '',
          body.youtube_url || '',
          typeof body.features === 'object' ? JSON.stringify(body.features) : (body.features || ''),
          body.type || 'premium', id
        ).run();
        return json({ message: 'Updated' });
      }

      if (path.match(/^\/api\/admin\/packages\/\d+$/) && method === 'DELETE') {
        const id = path.split('/').pop();
        await env.DB.prepare('DELETE FROM packages WHERE id=?').bind(id).run();
        return json({ message: 'Deleted' });
      }

      // ===== OWNER =====
      // Fix #9: Map frontend fields (role, photo_url, social_url, social_label) to DB columns
      if (path === '/api/admin/owner' && method === 'GET') {
        const owner = await env.DB.prepare('SELECT * FROM owner_profile LIMIT 1').first();
        if (!owner) return json({ owner: {} });
        return json({
          owner: {
            ...owner,
            // Expose both original and aliased field names for full frontend compatibility
            role: owner.title,
            photo_url: owner.image_url,
            social_url: owner.facebook,
            social_label: owner.email,
          },
        });
      }

      if (path === '/api/admin/owner' && method === 'PUT') {
        const body = await request.json();
        // Map frontend field names to DB column names
        const name = body.name || '';
        const title = body.role ?? body.title ?? '';
        const bio = body.bio || '';
        const emailVal = body.social_label ?? body.email ?? '';   // social_label stored as email
        const phone = body.phone || '';
        const facebook = body.social_url ?? body.facebook ?? '';  // social_url stored as facebook
        const imageUrl = body.photo_url ?? body.image_url ?? '';

        const existing = await env.DB.prepare('SELECT id FROM owner_profile LIMIT 1').first();
        if (existing) {
          await env.DB.prepare(`
            UPDATE owner_profile SET name=?, title=?, bio=?, email=?, phone=?, facebook=?, image_url=? WHERE id=?
          `).bind(name, title, bio, emailVal, phone, facebook, imageUrl, existing.id).run();
        } else {
          await env.DB.prepare(`
            INSERT INTO owner_profile (name, title, bio, email, phone, facebook, image_url)
            VALUES (?,?,?,?,?,?,?)
          `).bind(name, title, bio, emailVal, phone, facebook, imageUrl).run();
        }
        return json({ message: 'Saved' });
      }

      if (path === '/api/admin/owner/image' && method === 'POST') {
        const formData = await request.formData();
        const file = formData.get('file');
        if (!file) return json({ error: 'No file' }, 400);
        const key = `owner/${Date.now()}_${file.name}`;
        const buffer = await file.arrayBuffer();
        await env.R2.put(key, buffer, {
          httpMetadata: { contentType: file.type || 'image/jpeg' },
        });
        const imageUrl = `https://${env.R2_PUBLIC_DOMAIN}/${key}`;
        return json({ url: imageUrl });
      }

      return json({ error: 'Not found' }, 404);
    } catch (e) {
      return json({ error: e.message }, 500);
    }
  },
};
