// workers/main-worker.js

import authWorker         from './auth-worker.js';
import homePdfWorker      from './home-pdf-worker.js';
import examWorker         from './exam-worker.js';
import adminWorker        from './admin-worker.js';
import focusProfileWorker from './focus-profile-worker.js';
import publicWorker       from './public-worker.js';

const CORS = {
  'Access-Control-Allow-Origin': '*',
  'Access-Control-Allow-Methods': 'GET, POST, PUT, DELETE, OPTIONS',
  'Access-Control-Allow-Headers': 'Content-Type, Authorization',
};

function json(data, status = 200) {
  return new Response(JSON.stringify(data), {
    status, headers: { ...CORS, 'Content-Type': 'application/json' },
  });
}

export default {
  async fetch(request, env, ctx) {
    const url  = new URL(request.url);
    const path = url.pathname;

    if (request.method === 'OPTIONS') {
      return new Response(null, { headers: CORS });
    }

    // Auth (register / login)
    if (path.startsWith('/api/auth')) {
      return authWorker.fetch(request, env, ctx);
    }

    // Public (no auth)
    if (path.startsWith('/api/public')) {
      return publicWorker.fetch(request, env, ctx);
    }

    // AI explain (result.html)
    if (path === '/api/ai/explain' && request.method === 'POST') {
      return handleAiExplain(request, env);
    }

    // Exam
    if (path.startsWith('/api/exam')) {
      return examWorker.fetch(request, env, ctx);
    }

    // Subjects / chapters / PDFs (including /api/pdf-url)
    if (
      path.startsWith('/api/subjects') ||
      path.startsWith('/api/chapters') ||
      path.startsWith('/api/pdfs')     ||
      path.startsWith('/api/pdf')
    ) {
      return homePdfWorker.fetch(request, env, ctx);
    }

    // Admin panel
    if (path.startsWith('/api/admin')) {
      return adminWorker.fetch(request, env, ctx);
    }

    // Focus / user profile / page-view
    if (
      path.startsWith('/api/focus')     ||
      path.startsWith('/api/profile')   ||
      path.startsWith('/api/user')      ||
      path.startsWith('/api/page-view')
    ) {
      return focusProfileWorker.fetch(request, env, ctx);
    }

    return json({ error: 'Not found' }, 404);
  },
};

async function handleAiExplain(request, env) {
  try {
    const token = (request.headers.get('Authorization') || '').replace('Bearer ', '');
    if (!token) return json({ error: 'Unauthorized' }, 401);
    const user = await env.DB.prepare('SELECT id FROM users WHERE session_token=?').bind(token).first();
    if (!user) return json({ error: 'Unauthorized' }, 401);

    const { question, options, correct, user_answer } = await request.json();
    const prompt = `প্রশ্ন: ${question}
বিকল্পগুলো:
${options.map((o, i) => `${['ক','খ','গ','ঘ'][i]}) ${o}`).join('\n')}
সঠিক উত্তর: ${correct}
শিক্ষার্থীর উত্তর: ${user_answer || 'কোনো উত্তর দেয়নি'}

বাংলায় সংক্ষেপে (৩-৪ বাক্যে) ব্যাখ্যা করো কেন সঠিক উত্তরটি সঠিক।`;

    // Try Gemini first
    if (env.GEMINI_KEY) {
      try {
        const res = await fetch(
          `https://generativelanguage.googleapis.com/v1beta/models/gemini-2.0-flash:generateContent?key=${env.GEMINI_KEY}`,
          {
            method: 'POST',
            headers: { 'Content-Type': 'application/json' },
            body: JSON.stringify({ contents: [{ parts: [{ text: prompt }] }], generationConfig: { maxOutputTokens: 512 } }),
          }
        );
        const d = await res.json();
        const explanation = d.candidates?.[0]?.content?.parts?.[0]?.text || '';
        if (explanation) return json({ explanation });
      } catch (_) {}
    }

    // Fallback Groq
    if (env.GROQ_KEY) {
      try {
        const res = await fetch('https://api.groq.com/openai/v1/chat/completions', {
          method: 'POST',
          headers: { 'Content-Type': 'application/json', 'Authorization': `Bearer ${env.GROQ_KEY}` },
          body: JSON.stringify({ model: 'llama3-8b-8192', messages: [{ role: 'user', content: prompt }], max_tokens: 512 }),
        });
        const d = await res.json();
        const explanation = d.choices?.[0]?.message?.content || '';
        if (explanation) return json({ explanation });
      } catch (_) {}
    }

    return json({ explanation: 'AI ব্যাখ্যা পাওয়া যায়নি। সঠিক উত্তর: ' + correct });
  } catch (e) {
    return json({ error: e.message }, 500);
  }
}
