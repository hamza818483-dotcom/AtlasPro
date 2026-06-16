// home-pdf-worker.js
// Routes: /api/subjects, /api/chapters, /api/pdfs, /api/pdf-url, /api/pdf/download/:id

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
        status, headers: { ...cors, 'Content-Type': 'application/json' },
      });

    // Auth
    const token = (request.headers.get('Authorization') || '').replace('Bearer ', '');
    const user = token
      ? await env.DB.prepare('SELECT * FROM users WHERE session_token=?').bind(token).first()
      : null;
    if (!user) return json({ error: 'Unauthorized' }, 401);

    try {
      // ===== SUBJECTS =====
      if (path === '/api/subjects' && method === 'GET') {
        const { results } = await env.DB.prepare(
          'SELECT * FROM subjects ORDER BY order_index ASC, id ASC'
        ).all();
        return json({ subjects: results });
      }

      // ===== CHAPTERS =====
      if (path === '/api/chapters' && method === 'GET') {
        const subjectId = url.searchParams.get('subject_id');
        const { results } = await env.DB.prepare(
          'SELECT * FROM chapters WHERE subject_id=? ORDER BY order_index ASC'
        ).bind(subjectId).all();
        return json({ chapters: results });
      }

      // ===== PDFS by chapter =====
      if (path === '/api/pdfs' && method === 'GET') {
        const chapterId = url.searchParams.get('chapter_id');
        const chapterRow = await env.DB.prepare(
          'SELECT name FROM chapters WHERE id=?'
        ).bind(chapterId).first();
        const { results } = await env.DB.prepare(
          'SELECT * FROM pdfs WHERE chapter_id=? ORDER BY created_at ASC'
        ).bind(chapterId).all();
        return json({
          pdfs: results,
          chapter_name: chapterRow?.name || '',
        });
      }

      // ===== PDF DOWNLOAD (stream from R2) =====
      if (path.match(/^\/api\/pdf\/download\/\d+$/) && method === 'GET') {
        const pdfId = path.split('/').pop();
        const pdf = await env.DB.prepare('SELECT r2_key FROM pdfs WHERE id=?')
          .bind(pdfId).first();
        if (!pdf) return json({ error: 'PDF not found' }, 404);

        const obj = await env.R2.get(pdf.r2_key);
        if (!obj) return json({ error: 'File not found in storage' }, 404);

        return new Response(obj.body, {
          headers: {
            ...cors,
            'Content-Type': 'application/pdf',
            'Content-Disposition': 'attachment',
          },
        });
      }

      // ===== MCQ fetch for exam (with unique pattern) =====
      if (path === '/api/exam/mcq' && method === 'GET') {
        const pdfId = parseInt(url.searchParams.get('pdf_id'));
        const pageNumber = parseInt(url.searchParams.get('page_number') || '1');
        const type = url.searchParams.get('type') || 'standard';
        const examCount = parseInt(url.searchParams.get('exam_count') || '10');

        // Check type enabled
        const settings = await env.DB.prepare(
          'SELECT enabled FROM mcq_settings WHERE pdf_id=? AND type=?'
        ).bind(pdfId, type).first();
        if (settings && settings.enabled === 0) {
          return json({ disabled: true, coming_soon: true,
            message: 'এই ধরনের MCQ এখনো চালু হয়নি' });
        }

        // Get all MCQs for this page
        const { results: allMcqs } = await env.DB.prepare(
          'SELECT * FROM mcqs WHERE pdf_id=? AND page_number=? AND type=? ORDER BY id ASC'
        ).bind(pdfId, pageNumber, type).all();

        if (allMcqs.length > 0) {
          const userMcqs = assignUniqueSubset(allMcqs, user.id, examCount);
          return json({ mcqs: userMcqs, from_cache: true });
        }

        // Check if generating
        const queue = await env.DB.prepare(
          "SELECT * FROM mcq_generation_queue WHERE pdf_id=? AND page_number=? AND type=? AND status='generating'"
        ).bind(pdfId, pageNumber, type).first();

        if (queue) {
          const elapsed = Math.floor((Date.now() - queue.started_at) / 1000);
          const progress = Math.min(90, Math.floor((elapsed / 30) * 100));
          return json({
            generating: true, progress,
            eta_seconds: Math.max(0, 30 - elapsed),
            message: 'MCQ তৈরি হচ্ছে...',
          });
        }

        // Start generation async
        await env.DB.prepare(`
          INSERT OR REPLACE INTO mcq_generation_queue (pdf_id, page_number, type, status, started_at)
          VALUES (?,?,?,'generating',?)
        `).bind(pdfId, pageNumber, type, Date.now()).run();

        // Generate (simplified — call Gemini)
        const prompt = await getPrompt(env, pdfId, type);
        const mcqs = await generateMcqs(env, prompt, pageNumber);

        for (const mcq of mcqs) {
          await env.DB.prepare(`
            INSERT INTO mcqs (pdf_id, type, question, option_a, option_b, option_c, option_d, correct_answer, explanation, page_number, source)
            VALUES (?,?,?,?,?,?,?,?,?,?,'ai')
          `).bind(pdfId, type, mcq.question||'', mcq.option_a||'', mcq.option_b||'',
            mcq.option_c||'', mcq.option_d||'',
            (mcq.correct_answer||'A').toUpperCase(), mcq.explanation||'', pageNumber).run();
        }

        await env.DB.prepare(
          "UPDATE mcq_generation_queue SET status='done', completed_at=? WHERE pdf_id=? AND page_number=? AND type=?"
        ).bind(Date.now(), pdfId, pageNumber, type).run();

        const { results: newMcqs } = await env.DB.prepare(
          'SELECT * FROM mcqs WHERE pdf_id=? AND page_number=? AND type=?'
        ).bind(pdfId, pageNumber, type).all();

        return json({ mcqs: assignUniqueSubset(newMcqs, user.id, examCount), from_cache: false });
      }

      // ===== PDF URL (for viewer) =====
      if (path === '/api/pdf-url' && method === 'GET') {
        const pdfId = url.searchParams.get('pdf_id');
        if (!pdfId) return json({ error: 'pdf_id required' }, 400);
        const pdf = await env.DB.prepare(
          'SELECT id, title, r2_url, page_count FROM pdfs WHERE id=?'
        ).bind(pdfId).first();
        if (!pdf) return json({ error: 'PDF not found' }, 404);
        return json({ url: pdf.r2_url, title: pdf.title, page_count: pdf.page_count || 0 });
      }

      return json({ error: 'Not found' }, 404);
    } catch (e) {
      return json({ error: e.message }, 500);
    }
  },
};

function assignUniqueSubset(allMcqs, userId, count) {
  if (allMcqs.length <= count) return allMcqs;
  const today = new Date().toISOString().substring(0, 10);
  let seed = hashCode(`${userId}_${today}`);
  const shuffled = [...allMcqs];
  for (let i = shuffled.length - 1; i > 0; i--) {
    seed = (seed * 1664525 + 1013904223) & 0xFFFFFFFF;
    const j = seed % (i + 1);
    [shuffled[i], shuffled[j]] = [shuffled[j], shuffled[i]];
  }
  return shuffled.slice(0, count);
}

function hashCode(str) {
  let h = 0;
  for (let i = 0; i < str.length; i++) {
    h = Math.imul(31, h) + str.charCodeAt(i) | 0;
  }
  return Math.abs(h);
}

async function getPrompt(env, pdfId, type) {
  const s = await env.DB.prepare(
    'SELECT prompt FROM mcq_settings WHERE pdf_id=? AND type=?'
  ).bind(pdfId, type).first();
  const defaults = {
    standard: 'Generate 20 MCQs with 4 options each. Return JSON array only: [{"question":"","option_a":"","option_b":"","option_c":"","option_d":"","correct_answer":"A","explanation":""}]',
    true_false: 'Generate 20 true/false questions. A=True B=False. Return JSON array only.',
    hard: 'Generate 20 hard analytical MCQs. Return JSON array only.',
  };
  return s?.prompt || defaults[type] || defaults.standard;
}

async function generateMcqs(env, prompt, pageNumber) {
  const fullPrompt = `${prompt}\n\nPage: ${pageNumber}`;
  try {
    const res = await fetch(
      `https://generativelanguage.googleapis.com/v1beta/models/gemini-2.0-flash:generateContent?key=${env.GEMINI_KEY}`,
      { method: 'POST', headers: {'Content-Type':'application/json'},
        body: JSON.stringify({ contents: [{ parts: [{ text: fullPrompt }] }],
          generationConfig: { maxOutputTokens: 4096 } }) }
    );
    const d = await res.json();
    const text = d.candidates?.[0]?.content?.parts?.[0]?.text || '[]';
    const m = text.match(/\[[\s\S]*\]/);
    if (m) return JSON.parse(m[0]);
  } catch (_) {}
  // Groq fallback
  try {
    const res = await fetch('https://api.groq.com/openai/v1/chat/completions', {
      method: 'POST',
      headers: {'Content-Type':'application/json','Authorization':`Bearer ${env.GROQ_KEY}`},
      body: JSON.stringify({ model:'llama3-8b-8192',
        messages:[{role:'user',content:fullPrompt}], max_tokens:4096 })
    });
    const d = await res.json();
    const text = d.choices?.[0]?.message?.content || '[]';
    const m = text.match(/\[[\s\S]*\]/);
    if (m) return JSON.parse(m[0]);
  } catch (_) {}
  return [];
}
