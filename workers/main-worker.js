// workers/main-worker.js

import authWorker         from './auth-worker.js';
import homePdfWorker      from './home-pdf-worker.js';
import examWorker         from './exam-worker.js';
import adminWorker        from './admin-worker.js';
import focusProfileWorker from './focus-profile-worker.js';
import publicWorker       from './public-worker.js';
import { getGeminiKeys, callGemini, callGroq, callCfAi, callAiChain } from './utils.js';

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

    // AI endpoints
    if (path === '/api/ai/explain' && request.method === 'POST') {
      return handleAiExplain(request, env);
    }
    if (path === '/api/ai/chat' && request.method === 'POST') {
      return handleAiChat(request, env);
    }

    // Exam
    if (path.startsWith('/api/exam')) {
      return examWorker.fetch(request, env, ctx);
    }

    // Subjects / chapters / PDFs (including /api/pdf-url and /api/pdf-stream)
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

async function handleAiChat(request, env) {
  try {
    const token = (request.headers.get('Authorization') || '').replace('Bearer ', '');
    if (!token) return json({ error: 'Unauthorized' }, 401);
    const user = await env.DB.prepare('SELECT id FROM users WHERE session_token=?').bind(token).first();
    if (!user) return json({ error: 'Unauthorized' }, 401);

    const { message } = await request.json();
    if (!message?.trim()) return json({ error: 'Message required' }, 400);

    const prompt = `You are Atlas AI, a helpful educational assistant. You help students with their studies, explain concepts, solve problems, and give study tips. Respond in the same language as the user's message. If they write in Bengali, reply in Bengali. If English, reply in English. Be concise and helpful.\n\nUser: ${message}`;

    const reply = await callAiChain(env, prompt, 1024);
    return json({ reply: reply || 'দুঃখিত, উত্তর তৈরি করা যায়নি। আবার চেষ্টা করুন।' });
  } catch (e) {
    return json({ error: e.message }, 500);
  }
}

async function handleAiExplain(request, env) {
  try {
    const token = (request.headers.get('Authorization') || '').replace('Bearer ', '');
    if (!token) return json({ error: 'Unauthorized' }, 401);
    const user = await env.DB.prepare('SELECT id FROM users WHERE session_token=?').bind(token).first();
    if (!user) return json({ error: 'Unauthorized' }, 401);

    const { question, options, correct, correct_index, user_answer } = await request.json();
    const optLabels = ['ক','খ','গ','ঘ'];
    const correctLabel = correct || (correct_index !== undefined ? optLabels[correct_index] : 'ক');
    const userLabel = user_answer !== undefined && user_answer !== null
      ? (typeof user_answer === 'number' ? optLabels[user_answer] : user_answer)
      : 'কোনো উত্তর দেয়নি';

    const prompt = `প্রশ্ন: ${question}
বিকল্পগুলো:
${(options||[]).map((o, i) => `${optLabels[i]}) ${o}`).join('\n')}
সঠিক উত্তর: ${correctLabel}
শিক্ষার্থীর উত্তর: ${userLabel}

বাংলায় সংক্ষেপে (৩-৪ বাক্যে) ব্যাখ্যা করো কেন সঠিক উত্তরটি সঠিক।`;

    let explanation = await callAiChain(env, prompt, 512);

    return json({ explanation: explanation || 'AI ব্যাখ্যা পাওয়া যায়নি। সঠিক উত্তর: ' + correctLabel });
  } catch (e) {
    return json({ error: e.message }, 500);
  }
}
