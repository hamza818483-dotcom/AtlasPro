// workers/main-worker.js — FINAL (Batch 15, replaces Batch 14)

import authWorker        from './auth-worker.js';
import homePdfWorker     from './home-pdf-worker.js';
import examWorker        from './exam-worker.js';
import adminWorker       from './admin-worker.js';
import focusProfileWorker from './focus-profile-worker.js';
import publicWorker      from './public-worker.js';

const CORS = {
  'Access-Control-Allow-Origin': '*',
  'Access-Control-Allow-Methods': 'GET, POST, PUT, DELETE, OPTIONS',
  'Access-Control-Allow-Headers': 'Content-Type, Authorization',
};

export default {
  async fetch(request, env, ctx) {
    const url  = new URL(request.url);
    const path = url.pathname;

    if (request.method === 'OPTIONS') {
      return new Response(null, { headers: CORS });
    }

    // Auth (register / login only)
    if (path.startsWith('/api/auth')) {
      return authWorker.fetch(request, env, ctx);
    }

    // Public (no auth)
    if (path.startsWith('/api/public')) {
      return publicWorker.fetch(request, env, ctx);
    }

    // Exam submit / answers / history
    if (path.startsWith('/api/exam')) {
      return examWorker.fetch(request, env, ctx);
    }

    // Subjects / chapters / PDFs / MCQ fetch
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

    // Focus timer / profile / page-view
    if (
      path.startsWith('/api/focus')     ||
      path.startsWith('/api/profile')   ||
      path.startsWith('/api/page-view')
    ) {
      return focusProfileWorker.fetch(request, env, ctx);
    }

    return new Response(JSON.stringify({ error: 'Not found' }), {
      status: 404,
      headers: { ...CORS, 'Content-Type': 'application/json' },
    });
  },
};
