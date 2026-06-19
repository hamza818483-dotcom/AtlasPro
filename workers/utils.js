// workers/utils.js — FIXED (Batch 15, replaces Batch 14)

export async function hashPassword(password) {
  const enc = new TextEncoder();
  const data = enc.encode(password + 'atlas_salt_2024');
  const hash = await crypto.subtle.digest('SHA-256', data);
  return Array.from(new Uint8Array(hash))
    .map(b => b.toString(16).padStart(2, '0')).join(''); // ✅ padStart (not padLeft)
}

export async function verifyPassword(password, hash) {
  const computed = await hashPassword(password);
  return computed === hash;
}

export function generateToken() {
  const arr = new Uint8Array(32);
  crypto.getRandomValues(arr);
  return Array.from(arr)
    .map(b => b.toString(16).padStart(2, '0')).join(''); // ✅ padStart (not padLeft)
}

export function safeUser(u) {
  if (!u) return null;
  const { password_hash, session_token, ...safe } = u;
  return safe;
}

export function jsonRes(data, status = 200) {
  return new Response(JSON.stringify(data), {
    status,
    headers: {
      'Content-Type': 'application/json',
      'Access-Control-Allow-Origin': '*',
    },
  });
}

// Gemini key rotation helpers
export function getGeminiKeys(env) {
  const keys = [];
  if (env.GEMINI_KEYS) keys.push(...env.GEMINI_KEYS.split(',').map(k => k.trim()).filter(Boolean));
  if (env.GEMINI_KEY)  keys.push(env.GEMINI_KEY.trim());
  return [...new Set(keys)];
}

export async function callGemini(keys, body) {
  const models = ['gemini-2.5-flash'];
  for (const key of keys) {
    for (const model of models) {
      try {
        const res = await fetch(
          `https://generativelanguage.googleapis.com/v1beta/models/${model}:generateContent?key=${key}`,
          { method: 'POST', headers: { 'Content-Type': 'application/json' }, body: JSON.stringify(body) }
        );
        if (!res.ok) continue;
        const d = await res.json();
        const text = d.candidates?.[0]?.content?.parts?.[0]?.text;
        if (text) return text;
      } catch (_) {}
    }
  }
  return null;
}

export async function callGroq(key, messages, maxTokens = 4096) {
  if (!key) return null;
  try {
    const res = await fetch('https://api.groq.com/openai/v1/chat/completions', {
      method: 'POST',
      headers: { 'Content-Type': 'application/json', 'Authorization': `Bearer ${key}` },
      body: JSON.stringify({ model: 'llama3-8b-8192', messages, max_tokens: maxTokens }),
    });
    if (!res.ok) return null;
    const d = await res.json();
    return d.choices?.[0]?.message?.content || null;
  } catch (_) { return null; }
}

export async function callCfAi(env, prompt) {
  if (!env.AI) return null;
  try {
    const res = await env.AI.run('@cf/meta/llama-3-8b-instruct', {
      messages: [{ role: 'user', content: prompt }],
    });
    return res?.response || null;
  } catch (_) { return null; }
}

export function parseMcqJson(text) {
  if (!text) return [];
  const m = text.match(/\[[\s\S]*\]/);
  if (!m) return [];
  try { return JSON.parse(m[0]); } catch (_) { return []; }
}

// Supabase Storage helpers (replaces R2)
export async function supabaseUpload(env, path, buffer, contentType = 'application/octet-stream') {
  const url = `${env.SUPABASE_URL}/storage/v1/object/${path}`;
  const res = await fetch(url, {
    method: 'POST',
    headers: {
      'Authorization': `Bearer ${env.SUPABASE_ANON_KEY}`,
      'Content-Type': contentType,
      'x-upsert': 'true',
    },
    body: buffer,
  });
  if (!res.ok) throw new Error(`Supabase upload failed: ${await res.text()}`);
  return `${env.SUPABASE_URL}/storage/v1/object/public/${path}`;
}

export async function supabaseDelete(env, path) {
  await fetch(`${env.SUPABASE_URL}/storage/v1/object/${path}`, {
    method: 'DELETE',
    headers: { 'Authorization': `Bearer ${env.SUPABASE_ANON_KEY}` },
  });
}
