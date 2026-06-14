// workers/auth-worker.js — FIXED (Batch 15)
// Only handles: /api/auth/register, /api/auth/login
// exam routes moved to exam-worker.js

import { hashPassword, verifyPassword, generateToken, safeUser } from './utils.js';

export default {
  async fetch(request, env) {
    const url = new URL(request.url);
    const path = url.pathname;
    const method = request.method;

    const cors = {
      'Access-Control-Allow-Origin': '*',
      'Access-Control-Allow-Methods': 'GET, POST, OPTIONS',
      'Access-Control-Allow-Headers': 'Content-Type, Authorization',
    };
    if (method === 'OPTIONS') return new Response(null, { headers: cors });

    const json = (data, status = 200) =>
      new Response(JSON.stringify(data), {
        status,
        headers: { ...cors, 'Content-Type': 'application/json' },
      });

    try {
      // ── REGISTER ──────────────────────────────────────────
      if (path === '/api/auth/register' && method === 'POST') {
        const body = await request.json();
        const { phone, password, name } = body;

        if (!phone || !password || !name) {
          return json({ error: 'নাম, ফোন ও পাসওয়ার্ড আবশ্যক' }, 400);
        }
        if (password.length < 6) {
          return json({ error: 'পাসওয়ার্ড কমপক্ষে ৬ অক্ষর' }, 400);
        }

        const existing = await env.DB.prepare(
          'SELECT id FROM users WHERE phone=?'
        ).bind(phone).first();
        if (existing) return json({ error: 'এই ফোন নম্বর আগেই নিবন্ধিত' }, 409);

        const hashed = await hashPassword(password);
        const token  = generateToken();

        const res = await env.DB.prepare(`
          INSERT INTO users (
            name, father_name, mother_name, hsc_batch, college_name,
            ssc_gpa, hsc_gpa, phone, secondary_phone, social_link,
            password_hash, gender, session_token,
            access_type, daily_page_limit, is_admin, created_at
          ) VALUES (?,?,?,?,?,?,?,?,?,?,?,?,?,'free',5,0,datetime('now'))
        `).bind(
          name,
          body.father_name    || '',
          body.mother_name    || '',
          body.hsc_batch      || '',
          body.college_name   || '',
          body.ssc_gpa        || '',
          body.hsc_gpa        || '',
          phone,
          body.secondary_phone || '',
          body.social_link     || '',
          hashed,
          body.gender          || 'male',
          token,
        ).run();

        const newUser = await env.DB.prepare('SELECT * FROM users WHERE id=?')
          .bind(res.meta.last_row_id).first();

        return json({ token, user: safeUser(newUser) }, 201);
      }

      // ── LOGIN ─────────────────────────────────────────────
      if (path === '/api/auth/login' && method === 'POST') {
        const body = await request.json();
        const { phone, password } = body;

        if (!phone || !password) {
          return json({ error: 'ফোন ও পাসওয়ার্ড দাও' }, 400);
        }

        const user = await env.DB.prepare('SELECT * FROM users WHERE phone=?')
          .bind(phone).first();
        if (!user) return json({ error: 'ফোন নম্বর পাওয়া যায়নি' }, 401);

        const valid = await verifyPassword(password, user.password_hash);
        if (!valid) return json({ error: 'পাসওয়ার্ড ভুল' }, 401);

        const token = generateToken();
        await env.DB.prepare('UPDATE users SET session_token=? WHERE id=?')
          .bind(token, user.id).run();

        return json({ token, user: safeUser({ ...user, session_token: token }) });
      }

      return json({ error: 'Not found' }, 404);
    } catch (e) {
      return json({ error: e.message }, 500);
    }
  },
};
