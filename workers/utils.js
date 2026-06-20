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

// Timeout-aware fetch (prevents AI calls from hanging)
function fetchWithTimeout(url, options = {}, timeoutMs = 20000) {
  const controller = new AbortController();
  const timer = setTimeout(() => controller.abort(), timeoutMs);
  return fetch(url, { ...options, signal: controller.signal }).finally(() => clearTimeout(timer));
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
        const res = await fetchWithTimeout(
          `https://generativelanguage.googleapis.com/v1beta/models/${model}:generateContent?key=${key}`,
          { method: 'POST', headers: { 'Content-Type': 'application/json' }, body: JSON.stringify(body) },
          25000
        );
        if (res.status === 429 || res.status >= 500) continue;
        if (!res.ok) continue;
        const d = await res.json();
        const text = d.candidates?.[0]?.content?.parts?.[0]?.text;
        if (text) return text;
      } catch (_) {}
    }
  }
  return null;
}

// Generic OpenAI-compatible API caller (text-only)
async function callOpenAICompat(endpoint, key, model, messages, maxTokens = 4096) {
  if (!key) return null;
  try {
    const res = await fetchWithTimeout(endpoint, {
      method: 'POST',
      headers: { 'Content-Type': 'application/json', 'Authorization': `Bearer ${key}` },
      body: JSON.stringify({ model, messages, max_tokens: maxTokens }),
    }, 20000);
    if (!res.ok) return null;
    const d = await res.json();
    return d.choices?.[0]?.message?.content || null;
  } catch (_) { return null; }
}

// Generic OpenAI-compatible API caller (vision — image + text)
async function callOpenAICompatVision(endpoint, key, model, prompt, imageBase64, maxTokens = 4096) {
  if (!key || !imageBase64) return null;
  try {
    const res = await fetchWithTimeout(endpoint, {
      method: 'POST',
      headers: { 'Content-Type': 'application/json', 'Authorization': `Bearer ${key}` },
      body: JSON.stringify({
        model,
        messages: [{
          role: 'user',
          content: [
            { type: 'image_url', image_url: { url: imageBase64 } },
            { type: 'text', text: prompt },
          ],
        }],
        max_tokens: maxTokens,
      }),
    }, 20000);
    if (!res.ok) return null;
    const d = await res.json();
    return d.choices?.[0]?.message?.content || null;
  } catch (_) { return null; }
}

export async function callGroq(key, messages, maxTokens = 4096) {
  return callOpenAICompat('https://api.groq.com/openai/v1/chat/completions', key, 'llama-3.1-8b-instant', messages, maxTokens);
}

export async function callTogether(key, messages, maxTokens = 4096) {
  return callOpenAICompat('https://api.together.xyz/v1/chat/completions', key, 'meta-llama/Llama-3.3-70B-Instruct-Turbo-Free', messages, maxTokens);
}

export async function callOpenRouter(key, messages, maxTokens = 4096) {
  return callOpenAICompat('https://openrouter.ai/api/v1/chat/completions', key, 'meta-llama/llama-3.1-8b-instruct:free', messages, maxTokens);
}

export async function callCerebras(key, messages, maxTokens = 4096) {
  return callOpenAICompat('https://api.cerebras.ai/v1/chat/completions', key, 'llama-3.3-70b', messages, maxTokens);
}

export async function callCfAi(env, prompt) {
  if (!env.AI) return null;
  const models = ['@cf/meta/llama-3.1-8b-instruct', '@cf/meta/llama-3-8b-instruct'];
  for (const model of models) {
    try {
      const aiPromise = env.AI.run(model, {
        messages: [
          { role: 'system', content: 'You are a helpful assistant. Always respond with valid JSON when asked. No extra text outside JSON.' },
          { role: 'user', content: prompt }
        ],
      });
      const timeout = new Promise((_, rej) => setTimeout(() => rej(new Error('timeout')), 15000));
      const res = await Promise.race([aiPromise, timeout]);
      if (res?.response) return res.response;
    } catch (_) {}
  }
  return null;
}

// Vision model callers (free vision-capable models)
export async function callGroqVision(key, prompt, imageBase64, maxTokens = 4096) {
  return callOpenAICompatVision('https://api.groq.com/openai/v1/chat/completions', key, 'llama-3.2-90b-vision-preview', prompt, imageBase64, maxTokens);
}

export async function callTogetherVision(key, prompt, imageBase64, maxTokens = 4096) {
  return callOpenAICompatVision('https://api.together.xyz/v1/chat/completions', key, 'meta-llama/Llama-Vision-Free', prompt, imageBase64, maxTokens);
}

export async function callOpenRouterVision(key, prompt, imageBase64, maxTokens = 4096) {
  return callOpenAICompatVision('https://openrouter.ai/api/v1/chat/completions', key, 'meta-llama/llama-3.2-11b-vision-instruct:free', prompt, imageBase64, maxTokens);
}

export async function callCfAiVision(env, prompt, imageBase64) {
  if (!env.AI || !imageBase64) return null;
  try {
    const aiPromise = env.AI.run('@cf/meta/llama-3.2-11b-vision-instruct', {
      messages: [{
        role: 'user',
        content: [
          { type: 'image_url', image_url: { url: imageBase64 } },
          { type: 'text', text: prompt },
        ],
      }],
    });
    const timeout = new Promise((_, rej) => setTimeout(() => rej(new Error('timeout')), 15000));
    const res = await Promise.race([aiPromise, timeout]);
    if (res?.response) return res.response;
  } catch (_) {}
  return null;
}

// Get all configured AI keys
export function getAiKeys(env) {
  return {
    groq: env.GROQ_KEY || null,
    together: env.TOGETHER_KEY || null,
    openrouter: env.OPENROUTER_KEY || null,
    cerebras: env.CEREBRAS_KEY || null,
  };
}

// Full AI Vision fallback chain (image + text)
// Fast parallel groups: [Groq+OpenRouter] → [Together+CF AI] → text-only
export async function callAiVisionChain(env, prompt, imageBase64, maxTokens = 4096) {
  if (!imageBase64) return callAiChain(env, prompt, maxTokens);
  const keys = getAiKeys(env);

  // Group 1: Race Groq + OpenRouter vision (fastest)
  const g1 = [];
  if (keys.groq) g1.push(callGroqVision(keys.groq, prompt, imageBase64, maxTokens));
  if (keys.openrouter) g1.push(callOpenRouterVision(keys.openrouter, prompt, imageBase64, maxTokens));
  if (g1.length) {
    const results = await Promise.allSettled(g1);
    for (const r of results) if (r.status === 'fulfilled' && r.value) return r.value;
  }

  // Group 2: Race Together + CF AI vision
  const g2 = [];
  if (keys.together) g2.push(callTogetherVision(keys.together, prompt, imageBase64, maxTokens));
  if (env.AI) g2.push(callCfAiVision(env, prompt, imageBase64));
  if (g2.length) {
    const results = await Promise.allSettled(g2);
    for (const r of results) if (r.status === 'fulfilled' && r.value) return r.value;
  }

  // Last resort: text-only chain
  return callAiChain(env, prompt, maxTokens);
}

// Full AI fallback chain (text-only, no vision)
// Fast parallel groups: [Groq+Gemini] → [OpenRouter+Together+Cerebras] → CF AI
export async function callAiChain(env, prompt, maxTokens = 4096) {
  const messages = [{ role: 'user', content: prompt }];
  const keys = getAiKeys(env);

  // Group 1: Race Groq (fastest) + Gemini
  const g1 = [];
  if (keys.groq) g1.push(callGroq(keys.groq, messages, maxTokens));
  const geminiKeys = getGeminiKeys(env);
  if (geminiKeys.length > 0) {
    g1.push(callGemini(geminiKeys, {
      contents: [{ parts: [{ text: prompt }] }],
      generationConfig: { maxOutputTokens: maxTokens },
    }));
  }
  if (g1.length) {
    const results = await Promise.allSettled(g1);
    for (const r of results) if (r.status === 'fulfilled' && r.value) return r.value;
  }

  // Group 2: Race OpenRouter + Together + Cerebras
  const g2 = [];
  if (keys.openrouter) g2.push(callOpenRouter(keys.openrouter, messages, maxTokens));
  if (keys.together) g2.push(callTogether(keys.together, messages, maxTokens));
  if (keys.cerebras) g2.push(callCerebras(keys.cerebras, messages, maxTokens));
  if (g2.length) {
    const results = await Promise.allSettled(g2);
    for (const r of results) if (r.status === 'fulfilled' && r.value) return r.value;
  }

  // Last resort: CF AI
  return callCfAi(env, prompt);
}

export function parseMcqJson(text) {
  if (!text) return [];
  let cleaned = text.replace(/```json\s*/gi, '').replace(/```\s*/g, '').trim();
  const m = cleaned.match(/\[[\s\S]*\]/);
  if (!m) return [];
  try {
    const arr = JSON.parse(m[0]);
    if (!Array.isArray(arr)) return [];
    return arr.filter(q => {
      if (!q || typeof q !== 'object') return false;
      const qText = (q.question || '').trim();
      if (!qText || qText.length < 5) return false;
      if (/^MCQ\s*\d+/i.test(qText) && qText.length < 30) return false;
      if (/প্রশ্নটি যোগ করুন|add.*question|your question/i.test(qText)) return false;
      const opts = [q.option_a, q.option_b, q.option_c, q.option_d].map(o => (o || '').trim());
      const filledOpts = opts.filter(o => o.length > 0);
      if (filledOpts.length < 2) return false;
      return true;
    });
  } catch (_) { return []; }
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
