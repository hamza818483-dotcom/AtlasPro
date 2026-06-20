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
    const res = await fetch(endpoint, {
      method: 'POST',
      headers: { 'Content-Type': 'application/json', 'Authorization': `Bearer ${key}` },
      body: JSON.stringify({ model, messages, max_tokens: maxTokens }),
    });
    if (!res.ok) return null;
    const d = await res.json();
    return d.choices?.[0]?.message?.content || null;
  } catch (_) { return null; }
}

// Generic OpenAI-compatible API caller (vision — image + text)
async function callOpenAICompatVision(endpoint, key, model, prompt, imageBase64, maxTokens = 4096) {
  if (!key || !imageBase64) return null;
  try {
    const res = await fetch(endpoint, {
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
    });
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
      const res = await env.AI.run(model, {
        messages: [
          { role: 'system', content: 'You are a helpful assistant. Always respond with valid JSON when asked. No extra text outside JSON.' },
          { role: 'user', content: prompt }
        ],
      });
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
    const res = await env.AI.run('@cf/meta/llama-3.2-11b-vision-instruct', {
      messages: [{
        role: 'user',
        content: [
          { type: 'image_url', image_url: { url: imageBase64 } },
          { type: 'text', text: prompt },
        ],
      }],
    });
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
// Order: Gemini 2.5 Flash (PDF) → Groq Vision → OpenRouter Vision → Together Vision → CF AI Vision → text-only chain
export async function callAiVisionChain(env, prompt, imageBase64, maxTokens = 4096) {
  if (!imageBase64) return callAiChain(env, prompt, maxTokens);
  const keys = getAiKeys(env);

  // 1. Groq Vision (fastest)
  if (keys.groq) { const t = await callGroqVision(keys.groq, prompt, imageBase64, maxTokens); if (t) return t; }

  // 2. OpenRouter Vision
  if (keys.openrouter) { const t = await callOpenRouterVision(keys.openrouter, prompt, imageBase64, maxTokens); if (t) return t; }

  // 3. Together Vision
  if (keys.together) { const t = await callTogetherVision(keys.together, prompt, imageBase64, maxTokens); if (t) return t; }

  // 4. CF AI Vision (no key needed)
  const cfResult = await callCfAiVision(env, prompt, imageBase64);
  if (cfResult) return cfResult;

  // 5. Last resort: text-only chain
  return callAiChain(env, prompt, maxTokens);
}

// Full AI fallback chain (text-only, no vision)
// Order: Groq (fastest) → Gemini → OpenRouter → Together → Cerebras → CF AI
export async function callAiChain(env, prompt, maxTokens = 4096) {
  const messages = [{ role: 'user', content: prompt }];
  const keys = getAiKeys(env);

  if (keys.groq) { const t = await callGroq(keys.groq, messages, maxTokens); if (t) return t; }

  const geminiKeys = getGeminiKeys(env);
  if (geminiKeys.length > 0) {
    const t = await callGemini(geminiKeys, {
      contents: [{ parts: [{ text: prompt }] }],
      generationConfig: { maxOutputTokens: maxTokens },
    });
    if (t) return t;
  }

  if (keys.openrouter) { const t = await callOpenRouter(keys.openrouter, messages, maxTokens); if (t) return t; }
  if (keys.together) { const t = await callTogether(keys.together, messages, maxTokens); if (t) return t; }
  if (keys.cerebras) { const t = await callCerebras(keys.cerebras, messages, maxTokens); if (t) return t; }

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
