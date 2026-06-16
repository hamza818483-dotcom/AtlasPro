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
