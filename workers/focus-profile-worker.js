// focus-profile-worker.js — Batch 08
// Routes: /api/focus/*, /api/profile/*, /api/page-view

export default {
  async fetch(request, env) {
    const url = new URL(request.url);
    const path = url.pathname;
    const method = request.method;

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

    // Auth
    const token = (request.headers.get('Authorization') || '').replace('Bearer ', '');
    if (!token) return json({ error: 'Unauthorized' }, 401);
    const user = await env.DB.prepare('SELECT * FROM users WHERE session_token=?').bind(token).first();
    if (!user) return json({ error: 'Invalid token' }, 401);

    try {
      // ===== FOCUS TIMER =====

      // Start session
      if (path === '/api/focus/start' && method === 'POST') {
        // End any existing active session for this user
        await env.DB.prepare(
          "UPDATE focus_sessions SET status='ended', ended_at=datetime('now') WHERE user_id=? AND status IN ('active','break')"
        ).bind(user.id).run();

        const res = await env.DB.prepare(`
          INSERT INTO focus_sessions (user_id, status, started_at)
          VALUES (?, 'active', datetime('now'))
        `).bind(user.id).run();

        return json({ session_id: res.meta.last_row_id });
      }

      // Take break
      if (path === '/api/focus/break' && method === 'POST') {
        const body = await request.json();
        await env.DB.prepare(`
          UPDATE focus_sessions SET status='break', break_started_at=datetime('now'),
          breaks_count = breaks_count + 1
          WHERE id=? AND user_id=?
        `).bind(body.session_id, user.id).run();
        return json({ message: 'Break started' });
      }

      // Resume from break
      if (path === '/api/focus/resume' && method === 'POST') {
        const body = await request.json();
        await env.DB.prepare(`
          UPDATE focus_sessions SET status='active', break_started_at=NULL
          WHERE id=? AND user_id=?
        `).bind(body.session_id, user.id).run();
        return json({ message: 'Resumed' });
      }

      // End session
      if (path === '/api/focus/end' && method === 'POST') {
        const body = await request.json();
        await env.DB.prepare(`
          UPDATE focus_sessions SET status='ended', ended_at=datetime('now'),
          study_seconds=?, breaks_used=?
          WHERE id=? AND user_id=?
        `).bind(
          body.study_seconds || 0,
          body.breaks_used || 0,
          body.session_id,
          user.id
        ).run();
        return json({ message: 'Session ended' });
      }

      // Get active students
      if (path === '/api/focus/active' && method === 'GET') {
        const { results } = await env.DB.prepare(`
          SELECT fs.id, fs.status, fs.study_seconds, fs.breaks_used,
            u.name, u.profile_pic, u.gender, u.hsc_batch, u.college_name,
            CAST((julianday('now') - julianday(fs.started_at)) * 86400 AS INTEGER) as total_elapsed
          FROM focus_sessions fs
          JOIN users u ON fs.user_id = u.id
          WHERE fs.status IN ('active', 'break')
          AND fs.started_at > datetime('now', '-12 hours')
          ORDER BY fs.started_at DESC
        `).all();

        const students = results.map(s => ({
          ...s,
          study_seconds: s.status === 'active'
            ? (s.study_seconds || 0) + (s.total_elapsed - (s.study_seconds || 0))
            : (s.study_seconds || 0),
        }));

        return json({ students });
      }

      // ===== PROFILE =====

      if (path === '/api/profile' && method === 'GET') {
        const today = new Date().toISOString().substring(0, 10);
        const pagesUsed = await env.DB.prepare(`
          SELECT COUNT(*) as count FROM page_views
          WHERE user_id=? AND date(created_at)=?
        `).bind(user.id, today).first();

        return json({
          profile: {
            ...user,
            session_token: undefined,
            pages_used_today: pagesUsed?.count || 0,
          }
        });
      }

      if (path === '/api/profile/limits' && method === 'GET') {
        const today = new Date().toISOString().substring(0, 10);
        const pagesUsed = await env.DB.prepare(`
          SELECT COUNT(*) as count FROM page_views
          WHERE user_id=? AND date(created_at)=?
        `).bind(user.id, today).first();

        return json({
          access_type: user.access_type || 'free',
          daily_page_limit: user.daily_page_limit || 5,
          pages_used_today: pagesUsed?.count || 0,
        });
      }

      // Profile photo upload
      if (path === '/api/profile/photo' && method === 'POST') {
        const formData = await request.formData();
        const file = formData.get('file');
        if (!file) return json({ error: 'No file' }, 400);

        const key = `profiles/${user.id}_${Date.now()}${getExt(file.name)}`;
        const buffer = await file.arrayBuffer();
        await env.R2.put(key, buffer, {
          httpMetadata: { contentType: file.type || 'image/jpeg' },
        });
        const photoUrl = `https://${env.R2_PUBLIC_DOMAIN}/${key}`;
        await env.DB.prepare('UPDATE users SET profile_pic=? WHERE id=?')
          .bind(photoUrl, user.id).run();
        return json({ url: photoUrl });
      }

      // Exam history
      if (path === '/api/profile/exam-history' && method === 'GET') {
        const { results } = await env.DB.prepare(`
          SELECT er.*, 
            p.title as pdf_title,
            c.name as chapter_name,
            s.name as subject_name,
            strftime('%d %m %Y %H:%M', er.created_at) as exam_date
          FROM exam_results er
          LEFT JOIN pdfs p ON er.pdf_id = p.id
          LEFT JOIN chapters c ON p.chapter_id = c.id
          LEFT JOIN subjects s ON c.subject_id = s.id
          WHERE er.user_id=?
          ORDER BY er.created_at DESC
          LIMIT 50
        `).bind(user.id).all();

        // For each exam, get question details
        const history = [];
        for (const exam of results) {
          const { results: questions } = await env.DB.prepare(`
            SELECT * FROM exam_answers WHERE exam_result_id=?
          `).bind(exam.id).all();
          history.push({ ...exam, questions });
        }

        return json({ history });
      }

      // ===== PAGE VIEW TRACKING =====
      if (path === '/api/page-view' && method === 'POST') {
        const body = await request.json();
        const today = new Date().toISOString().substring(0, 10);

        // Check limit
        const limitRow = await env.DB.prepare(
          "SELECT COALESCE(daily_page_limit, 5) as lim, COALESCE(access_type,'free') as access_type FROM users WHERE id=?"
        ).bind(user.id).first();
        
        const pagesUsed = await env.DB.prepare(`
          SELECT COUNT(*) as count FROM page_views
          WHERE user_id=? AND date(created_at)=?
        `).bind(user.id, today).first();

        if (pagesUsed.count >= limitRow.lim) {
          return json({
            error: 'limit_exceeded',
            used: pagesUsed.count,
            limit: limitRow.lim,
            access_type: limitRow.access_type,
          }, 429);
        }

        await env.DB.prepare(`
          INSERT INTO page_views (user_id, pdf_id, page_number)
          VALUES (?,?,?)
        `).bind(user.id, body.pdf_id, body.page_number).run();

        return json({
          allowed: true,
          used: pagesUsed.count + 1,
          limit: limitRow.lim,
          remaining: limitRow.lim - pagesUsed.count - 1,
        });
      }

      return json({ error: 'Not found' }, 404);
    } catch (e) {
      return json({ error: e.message }, 500);
    }
  },
};

function getExt(filename) {
  const parts = (filename || '').split('.');
  return parts.length > 1 ? '.' + parts.pop() : '.jpg';
}
