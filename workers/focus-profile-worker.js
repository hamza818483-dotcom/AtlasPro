// focus-profile-worker.js
// Routes: /api/focus/*, /api/profile/*, /api/user/*, /api/page-view
import { supabaseUpload } from './utils.js';

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

      // Stop session — alias for /api/focus/end (frontend uses this endpoint)
      if (path === '/api/focus/stop' && method === 'POST') {
        const body = await request.json();
        await env.DB.prepare(`
          UPDATE focus_sessions
          SET status='ended', ended_at=datetime('now')
          WHERE (id=? OR (user_id=? AND status IN ('active','break')))
            AND user_id=?
        `).bind(
          body.session_id || 0,
          user.id,
          user.id
        ).run();
        return json({ message: 'Session ended' });
      }

      // Get active students (full list with details)
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

      // Active count — returns just the number of active/break sessions in last 12 hours
      if (path === '/api/focus/active-count' && method === 'GET') {
        const row = await env.DB.prepare(`
          SELECT COUNT(*) as count
          FROM focus_sessions
          WHERE status IN ('active', 'break')
            AND started_at > datetime('now', '-12 hours')
        `).first();
        return json({ count: row?.count || 0 });
      }

      // ===== PROFILE =====

      // GET /api/profile — existing route
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

      // GET /api/user/profile — alias used by profile.html
      if (path === '/api/user/profile' && method === 'GET') {
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

      // PUT /api/user/profile — update profile fields
      if (path === '/api/user/profile' && method === 'PUT') {
        const body = await request.json();
        await env.DB.prepare(`
          UPDATE users
          SET name=?, father_name=?, mother_name=?, hsc_batch=?, college_name=?,
              ssc_gpa=?, hsc_gpa=?, secondary_phone=?, social_link=?, gender=?
          WHERE id=?
        `).bind(
          body.name ?? user.name,
          body.father_name ?? user.father_name,
          body.mother_name ?? user.mother_name,
          body.hsc_batch ?? user.hsc_batch,
          body.college_name ?? user.college_name,
          body.ssc_gpa ?? user.ssc_gpa,
          body.hsc_gpa ?? user.hsc_gpa,
          body.secondary_phone ?? user.secondary_phone,
          body.social_link ?? user.social_link,
          body.gender ?? user.gender,
          user.id
        ).run();
        return json({ message: 'Updated' });
      }

      // GET /api/user/stats — aggregated stats for the current user
      if (path === '/api/user/stats' && method === 'GET') {
        const today = new Date().toISOString().substring(0, 10);

        const examStats = await env.DB.prepare(`
          SELECT
            COUNT(*) as total_exams,
            COALESCE(SUM(correct_answers), 0) as total_correct,
            COALESCE(SUM(total_questions), 0) as total_questions
          FROM exam_results
          WHERE user_id=?
        `).bind(user.id).first();

        const focusRow = await env.DB.prepare(`
          SELECT COALESCE(SUM(study_seconds), 0) as focus_today
          FROM focus_sessions
          WHERE user_id=? AND date(started_at)=date('now') AND status='ended'
        `).bind(user.id).first();

        const pagesRow = await env.DB.prepare(`
          SELECT COUNT(*) as pages_today
          FROM page_views
          WHERE user_id=? AND date(created_at)=date('now')
        `).bind(user.id).first();

        return json({
          total_exams: examStats?.total_exams || 0,
          total_correct: examStats?.total_correct || 0,
          total_questions: examStats?.total_questions || 0,
          focus_today: focusRow?.focus_today || 0,
          pages_today: pagesRow?.pages_today || 0,
        });
      }

      // GET /api/user/exam-history — alias for /api/profile/exam-history
      if (path === '/api/user/exam-history' && method === 'GET') {
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

        const history = [];
        for (const exam of results) {
          const { results: questions } = await env.DB.prepare(`
            SELECT * FROM exam_answers WHERE exam_result_id=?
          `).bind(exam.id).all();
          history.push({ ...exam, questions });
        }

        return json({ history });
      }

      // GET /api/user/mistakes — wrong answers for practice (last 50)
      if (path === '/api/user/mistakes' && method === 'GET') {
        const { results } = await env.DB.prepare(`
          SELECT ea.question, ea.option_a, ea.option_b, ea.option_c, ea.option_d,
                 ea.correct_answer, ea.explanation
          FROM exam_answers ea
          WHERE ea.exam_result_id IN (
            SELECT id FROM exam_results WHERE user_id=?
          )
            AND ea.is_correct=0
          ORDER BY ea.id DESC
          LIMIT 50
        `).bind(user.id).all();

        return json({ questions: results });
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
        const photoUrl = await supabaseUpload(env, key, buffer, file.type || 'image/jpeg');
        await env.DB.prepare('UPDATE users SET profile_pic=? WHERE id=?')
          .bind(photoUrl, user.id).run();
        return json({ url: photoUrl });
      }

      // Exam history (original route)
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
