// workers/exam-worker.js
import { getGeminiKeys, callGemini, callGroq, callCfAi, parseMcqJson } from './utils.js';

export default {
  async fetch(request, env) {
    const url = new URL(request.url);
    const path = url.pathname;
    const method = request.method;

    const cors = {
      'Access-Control-Allow-Origin': '*',
      'Access-Control-Allow-Methods': 'GET, POST, PUT, DELETE, OPTIONS',
      'Access-Control-Allow-Headers': 'Content-Type, Authorization',
    };
    if (method === 'OPTIONS') return new Response(null, { headers: cors });

    const json = (data, status = 200) =>
      new Response(JSON.stringify(data), {
        status,
        headers: { ...cors, 'Content-Type': 'application/json' },
      });

    // Auth
    const token = (request.headers.get('Authorization') || '').replace('Bearer ', '');
    if (!token) return json({ error: 'Unauthorized' }, 401);
    const user = await env.DB.prepare(
      'SELECT * FROM users WHERE session_token=?'
    ).bind(token).first();
    if (!user) return json({ error: 'Invalid token' }, 401);

    try {
      // ── GET QUESTIONS (for exam.html) ─────────────────────
      if (path === '/api/exam/questions' && method === 'GET') {
        const pdfId  = url.searchParams.get('pdf_id');
        const pagesRaw = url.searchParams.get('pages') || '';
        const type   = url.searchParams.get('type') || 'standard';
        const pages  = pagesRaw ? pagesRaw.split(',').map(Number).filter(Boolean) : [];

        if (!pdfId) return json({ error: 'pdf_id required' }, 400);

        let allMcqs = [];
        if (pages.length > 0) {
          for (const pg of pages) {
            const { results } = await env.DB.prepare(
              'SELECT * FROM mcqs WHERE pdf_id=? AND page_number=? AND type=? ORDER BY id ASC'
            ).bind(pdfId, pg, type).all();
            allMcqs.push(...results);
          }
        } else {
          const { results } = await env.DB.prepare(
            'SELECT * FROM mcqs WHERE pdf_id=? AND type=? ORDER BY id ASC'
          ).bind(pdfId, type).all();
          allMcqs = results;
        }

        // If no MCQs found, try AI generation
        if (allMcqs.length === 0) {
          if (type !== 'standard') {
            const isPremium = user.is_premium === 1 || user.is_premium === true;
            if (!isPremium) {
              return json({ coming_soon: true, message: 'এই ধরনের MCQ Premium ব্যবহারকারীদের জন্য। Standard MCQ সবার জন্য উপলব্ধ।' });
            }
          }

          // Fetch PDF info for AI prompt
          const pdf = await env.DB.prepare('SELECT * FROM pdfs WHERE id=?').bind(pdfId).first();
          if (!pdf) return json({ error: 'PDF not found' }, 404);

          const geminiKeys = getGeminiKeys(env);
          const pageList = pages.length ? pages.join(', ') : 'all';
          const typePrompt = type === 'true_false' ? 'True/False questions' : type === 'hard' ? 'hard/advanced MCQs' : 'standard MCQs';
          const prompt = `Generate 5 ${typePrompt} from page ${pageList} of a textbook PDF titled "${pdf.title || 'Unknown'}".
Each question must have 4 options (A, B, C, D), one correct answer, and a brief explanation.
Return ONLY a JSON array: [{"question":"...","option_a":"...","option_b":"...","option_c":"...","option_d":"...","correct_answer":"A","explanation":"..."}]`;

          let aiText = null;

          // Try Gemini Vision if PDF URL available
          if (pdf.url && geminiKeys.length > 0) {
            try {
              const pdfRes = await fetch(pdf.url);
              if (pdfRes.ok) {
                const buf = await pdfRes.arrayBuffer();
                const b64 = btoa(String.fromCharCode(...new Uint8Array(buf)));
                const body = {
                  contents: [{ parts: [
                    { inline_data: { mime_type: 'application/pdf', data: b64 } },
                    { text: prompt }
                  ]}],
                  generationConfig: { temperature: 0.7, maxOutputTokens: 4096 }
                };
                aiText = await callGemini(geminiKeys, body);
              }
            } catch (_) {}
          }

          // Fallback: Gemini text-only
          if (!aiText && geminiKeys.length > 0) {
            const body = {
              contents: [{ parts: [{ text: prompt }] }],
              generationConfig: { temperature: 0.7, maxOutputTokens: 4096 }
            };
            aiText = await callGemini(geminiKeys, body);
          }

          // Fallback: Groq
          if (!aiText && env.GROQ_KEY) {
            aiText = await callGroq(env.GROQ_KEY, [{ role: 'user', content: prompt }], 4096);
          }

          // Fallback: Cloudflare AI
          if (!aiText) {
            aiText = await callCfAi(env, prompt);
          }

          if (aiText) {
            const parsed = parseMcqJson(aiText);
            if (parsed.length > 0) {
              // Save to DB for future use
              for (const pg of (pages.length ? pages : [1])) {
                for (const q of parsed) {
                  await env.DB.prepare(`
                    INSERT INTO mcqs (pdf_id, page_number, type, question, option_a, option_b, option_c, option_d, correct_answer, explanation, created_at)
                    VALUES (?,?,?,?,?,?,?,?,?,?,datetime('now'))
                  `).bind(pdfId, pg, type, q.question, q.option_a, q.option_b, q.option_c, q.option_d, q.correct_answer || 'A', q.explanation || '').run();
                }
              }

              const questions = parsed.map(q => ({
                question: q.question,
                options: [q.option_a, q.option_b, q.option_c, q.option_d],
                correct_index: ['A','B','C','D'].indexOf((q.correct_answer||'A').toUpperCase()),
                explanation: q.explanation || '',
                type,
                page: pages[0] || 1,
              }));
              return json({ questions, ai_generated: true });
            }
          }

          return json({ coming_soon: true, message: 'MCQ তৈরি করা যায়নি। পরে আবার চেষ্টা করুন।' });
        }

        const questions = allMcqs.map(m => ({
          id:            m.id,
          question:      m.question,
          options:       [m.option_a, m.option_b, m.option_c, m.option_d],
          correct_index: ['A','B','C','D'].indexOf((m.correct_answer||'A').toUpperCase()),
          explanation:   m.explanation || '',
          type:          m.type || type,
          page:          m.page_number,
          image_url:     m.image_url || null,
        }));

        return json({ questions });
      }

      // ── SUBMIT EXAM ────────────────────────────────────────
      if (path === '/api/exam/submit' && method === 'POST') {
        const body = await request.json();
        const {
          pdf_id, page_numbers, mcq_type,
          total_questions, correct_answers, score, answers,
        } = body;

        const res = await env.DB.prepare(`
          INSERT INTO exam_results
            (user_id, pdf_id, page_numbers, mcq_type,
             total_questions, correct_answers, score, created_at)
          VALUES (?,?,?,?,?,?,?,datetime('now'))
        `).bind(
          user.id, pdf_id,
          Array.isArray(page_numbers) ? page_numbers.join(',') : (page_numbers || ''),
          mcq_type || 'standard',
          total_questions || 0, correct_answers || 0, score || 0,
        ).run();

        const examResultId = res.meta.last_row_id;

        // Save per-question answers
        if (Array.isArray(answers) && answers.length > 0) {
          for (const ans of answers) {
            await env.DB.prepare(`
              INSERT INTO exam_answers
                (exam_result_id, mcq_id, question,
                 option_a, option_b, option_c, option_d,
                 correct_answer, user_answer, is_correct,
                 explanation, page_number)
              VALUES (?,?,?,?,?,?,?,?,?,?,?,?)
            `).bind(
              examResultId,
              ans.mcq_id || null,
              ans.question || '',
              ans.option_a || '', ans.option_b || '',
              ans.option_c || '', ans.option_d || '',
              ans.correct_answer || 'A',
              ans.user_answer || null,
              ans.is_correct ? 1 : 0,
              ans.explanation || '',
              ans.page_number || 1,
            ).run();
          }
        }

        return json({ id: examResultId, score, message: 'Saved' }, 201);
      }

      // ── GET EXAM ANSWERS (detail / practice) ──────────────
      if (path.match(/^\/api\/exam\/answers\/\d+$/) && method === 'GET') {
        const examId = path.split('/').pop();
        const mistakeOnly = url.searchParams.get('mistake_only') === 'true';

        const exam = await env.DB.prepare(
          'SELECT * FROM exam_results WHERE id=? AND user_id=?'
        ).bind(examId, user.id).first();
        if (!exam) return json({ error: 'Not found' }, 404);

        const q = mistakeOnly
          ? 'SELECT * FROM exam_answers WHERE exam_result_id=? AND is_correct=0 ORDER BY id ASC'
          : 'SELECT * FROM exam_answers WHERE exam_result_id=? ORDER BY id ASC';

        const { results } = await env.DB.prepare(q).bind(examId).all();
        return json({ questions: results.map(r => ({ ...r, is_correct: r.is_correct === 1 })), exam });
      }

      // ── EXAM HISTORY (profile screen) ─────────────────────
      if (path === '/api/exam/history' && method === 'GET') {
        const { results } = await env.DB.prepare(`
          SELECT er.*,
            p.title  AS pdf_title,
            c.name   AS chapter_name,
            s.name   AS subject_name,
            strftime('%d/%m/%Y %H:%M', er.created_at) AS exam_date
          FROM exam_results er
          LEFT JOIN pdfs     p ON er.pdf_id     = p.id
          LEFT JOIN chapters c ON p.chapter_id  = c.id
          LEFT JOIN subjects s ON c.subject_id  = s.id
          WHERE er.user_id = ?
          ORDER BY er.created_at DESC
          LIMIT 50
        `).bind(user.id).all();

        // Attach question count per exam
        const history = [];
        for (const exam of results) {
          const cnt = await env.DB.prepare(
            'SELECT COUNT(*) AS c FROM exam_answers WHERE exam_result_id=?'
          ).bind(exam.id).first();
          history.push({ ...exam, answer_count: cnt?.c || 0 });
        }
        return json({ history });
      }

      return json({ error: 'Not found' }, 404);
    } catch (e) {
      return json({ error: e.message }, 500);
    }
  },
};
