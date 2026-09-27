const MAX_BODY_BYTES = 32_768;
const MAX_AGE_SECONDS = 300;
const responseHeaders = {
  "content-type": "application/json; charset=utf-8",
  "cache-control": "no-store",
  "x-content-type-options": "nosniff",
};

function reply(status, body) {
  return new Response(JSON.stringify(body), { status, headers: responseHeaders });
}

function decodeBase64(value) {
  if (typeof value !== "string" || !/^(?:[A-Za-z0-9+/]{4})*(?:[A-Za-z0-9+/]{2}==|[A-Za-z0-9+/]{3}=)?$/.test(value)) return null;
  try {
    return Uint8Array.from(atob(value), (character) => character.charCodeAt(0));
  } catch {
    return null;
  }
}

// Supabase Auth signs HTTP hooks using Standard Webhooks. Check the raw body;
// parsing or reserializing JSON before HMAC verification changes the signed bytes.
export async function verifySignedHook(body, headers, configuredSecret, nowMilliseconds = Date.now()) {
  if (typeof configuredSecret !== "string" || !configuredSecret.startsWith("v1,whsec_")) return false;
  const secretBytes = decodeBase64(configuredSecret.slice("v1,whsec_".length));
  if (!secretBytes || secretBytes.length < 32) return false;

  const id = headers.get("webhook-id");
  const timestamp = headers.get("webhook-timestamp");
  const signatureHeader = headers.get("webhook-signature");
  if (!id || id.length > 256 || !timestamp || !/^[0-9]{10}$/.test(timestamp) || !signatureHeader) return false;
  if (!Number.isFinite(nowMilliseconds) || Math.abs(Math.floor(nowMilliseconds / 1000) - Number(timestamp)) > MAX_AGE_SECONDS) return false;

  const signedBytes = new TextEncoder().encode(id + "." + timestamp + "." + body);
  const key = await crypto.subtle.importKey("raw", secretBytes, { name: "HMAC", hash: "SHA-256" }, false, ["verify"]);
  for (const candidate of signatureHeader.split(" ")) {
    if (!candidate.startsWith("v1,")) continue;
    const receivedBytes = decodeBase64(candidate.slice(3));
    if (receivedBytes?.length !== 32) continue;
    if (await crypto.subtle.verify("HMAC", key, receivedBytes, signedBytes)) return true;
  }
  return false;
}

function isApprovedFacebookSignup(value) {
  if (!value || typeof value !== "object" || Array.isArray(value)) return false;
  if (value.metadata?.name !== "before-user-created") return false;
  const user = value.user;
  if (!user || typeof user !== "object" || Array.isArray(user)) return false;
  const email = user.email;
  return user.is_anonymous === false &&
    typeof email === "string" &&
    email.length <= 320 &&
    /^[^\s@]+@[^\s@]+\.[^\s@]+$/.test(email) &&
    user.app_metadata?.provider === "facebook" &&
    Array.isArray(user.app_metadata?.providers) &&
    user.app_metadata.providers.length === 1 &&
    user.app_metadata.providers[0] === "facebook";
}

// This endpoint has no Supabase JWT: only Auth's signed hook may call it.
// A failure always denies new users; it never creates users or issues sessions.
export async function handleFacebookSignupHook(request, configuredSecret, nowMilliseconds = Date.now()) {
  if (request.method !== "POST") return reply(405, { error: { http_code: 405, message: "Method not allowed" } });
  if (!configuredSecret) return reply(503, { error: { http_code: 503, message: "Signup policy unavailable" } });
  const body = await request.text();
  if (new TextEncoder().encode(body).length > MAX_BODY_BYTES) return reply(413, { error: { http_code: 413, message: "Signup policy request too large" } });
  try {
    if (!await verifySignedHook(body, request.headers, configuredSecret, nowMilliseconds)) {
      return reply(401, { error: { http_code: 401, message: "Invalid signup policy signature" } });
    }
    const event = JSON.parse(body);
    if (!isApprovedFacebookSignup(event)) {
      return reply(403, { error: { http_code: 403, message: "New accounts require Facebook sign-in with an email address" } });
    }
    return reply(200, {});
  } catch {
    return reply(400, { error: { http_code: 400, message: "Invalid signup policy request" } });
  }
}
