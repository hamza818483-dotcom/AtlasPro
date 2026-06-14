// public-worker.js — Batch 09
// Public endpoints (no auth): /api/public/*
// Add these routes to your existing main worker OR deploy separately

// ─── Add to existing worker fetch handler ─────────────────
// Copy these route blocks into your main worker's try{} block

/*
// ===== PUBLIC ENDPOINTS (no auth required) =====

if (path === '/api/public/owner' && method === 'GET') {
  const owner = await env.DB.prepare('SELECT * FROM owner_profile LIMIT 1').first();
  return json({ owner: owner || {} });
}

if (path === '/api/public/announcements' && method === 'GET') {
  const { results } = await env.DB.prepare(
    "SELECT * FROM announcements WHERE active=1 ORDER BY sort_order ASC"
  ).all();
  return json({ announcements: results.map(r => ({ ...r, active: true })) });
}

if (path === '/api/public/packages' && method === 'GET') {
  const { results } = await env.DB.prepare(
    "SELECT * FROM packages ORDER BY type DESC, created_at DESC"
  ).all();
  return json({ packages: results });
}
*/

// ─── Standalone worker (if deploying separately) ───────────
export default {
  async fetch(request, env) {
    const url = new URL(request.url);
    const path = url.pathname;
    const method = request.method;

    const corsHeaders = {
      'Access-Control-Allow-Origin': '*',
      'Access-Control-Allow-Methods': 'GET, OPTIONS',
      'Access-Control-Allow-Headers': 'Content-Type',
    };
    if (method === 'OPTIONS') return new Response(null, { headers: corsHeaders });

    const json = (data, status = 200) =>
      new Response(JSON.stringify(data), {
        status,
        headers: { ...corsHeaders, 'Content-Type': 'application/json' },
      });

    try {
      if (path === '/api/public/owner' && method === 'GET') {
        const owner = await env.DB.prepare(
          'SELECT name, title, bio, email, phone, facebook, image_url FROM owner_profile LIMIT 1'
        ).first();
        return json({ owner: owner || {} });
      }

      if (path === '/api/public/announcements' && method === 'GET') {
        const { results } = await env.DB.prepare(
          "SELECT id, title, body, link, emoji, color FROM announcements WHERE active=1 ORDER BY sort_order ASC"
        ).all();
        return json({ announcements: results.map(r => ({ ...r, active: true })) });
      }

      if (path === '/api/public/packages' && method === 'GET') {
        const { results } = await env.DB.prepare(
          "SELECT * FROM packages ORDER BY type DESC, created_at DESC"
        ).all();
        return json({ packages: results });
      }

      return json({ error: 'Not found' }, 404);
    } catch (e) {
      return json({ error: e.message }, 500);
    }
  },
};
