const GOOGLE_JWKS_URI = "https://www.googleapis.com/oauth2/v3/certs";
const GOOGLE_ISSUERS = new Set([
  "https://accounts.google.com",
  "accounts.google.com",
]);
const MAX_ID_TOKEN_BYTES = 16_384;

export const GOOGLE_REQUIRED_SCOPES = Object.freeze([
  "openid",
  "email",
  "profile",
  "https://www.googleapis.com/auth/drive.metadata.readonly",
  "https://www.googleapis.com/auth/spreadsheets.readonly",
]);

const GOOGLE_SCOPE_ALIASES = new Map([
  ["https://www.googleapis.com/auth/userinfo.email", "email"],
  ["https://www.googleapis.com/auth/userinfo.profile", "profile"],
]);

function fail(reason) {
  throw new Error(`google_oidc_${reason}`);
}

function isRecord(value) {
  return value !== null && typeof value === "object" && !Array.isArray(value);
}

function decodeBase64Url(value) {
  if (typeof value !== "string" || !value || !/^[A-Za-z0-9_-]+$/.test(value)) {
    fail("jwt_encoding_invalid");
  }
  const padded = value.replace(/-/g, "+").replace(/_/g, "/") + "=".repeat((4 - value.length % 4) % 4);
  let decoded;
  try {
    decoded = atob(padded);
  } catch {
    fail("jwt_encoding_invalid");
  }
  return Uint8Array.from(decoded, (character) => character.charCodeAt(0));
}

function decodeJsonSegment(value) {
  let parsed;
  try {
    parsed = JSON.parse(new TextDecoder("utf-8", { fatal: true }).decode(decodeBase64Url(value)));
  } catch {
    fail("jwt_json_invalid");
  }
  if (!isRecord(parsed)) fail("jwt_json_invalid");
  return parsed;
}

async function sha256Hex(value) {
  const digest = new Uint8Array(await crypto.subtle.digest("SHA-256", new TextEncoder().encode(value)));
  return [...digest].map((byte) => byte.toString(16).padStart(2, "0")).join("");
}

function equalHex(left, right) {
  if (!/^[0-9a-f]{64}$/.test(left) || !/^[0-9a-f]{64}$/.test(right)) return false;
  let difference = 0;
  for (let index = 0; index < left.length; index += 1) {
    difference |= left.charCodeAt(index) ^ right.charCodeAt(index);
  }
  return difference === 0;
}

function validateClaims(claims, clientId, expectedNonceHash, nowSeconds) {
  if (!GOOGLE_ISSUERS.has(claims.iss)) fail("issuer_invalid");
  const audiences = typeof claims.aud === "string"
    ? [claims.aud]
    : Array.isArray(claims.aud) && claims.aud.every((value) => typeof value === "string")
      ? claims.aud
      : [];
  if (!audiences.includes(clientId)) fail("audience_invalid");
  if ((audiences.length > 1 || claims.azp !== undefined) && claims.azp !== clientId) {
    fail("authorized_party_invalid");
  }
  if (!Number.isInteger(claims.exp) || claims.exp <= nowSeconds) fail("expired");
  if (!Number.isInteger(claims.iat) || claims.iat > nowSeconds + 60) fail("issued_at_invalid");
  if (claims.nbf !== undefined && (!Number.isInteger(claims.nbf) || claims.nbf > nowSeconds + 60)) {
    fail("not_yet_valid");
  }
  if (typeof claims.sub !== "string" || !/^[\x21-\x7e]{1,255}$/.test(claims.sub)) {
    fail("subject_invalid");
  }
  if (typeof claims.email !== "string" || claims.email.length > 320 || !claims.email.includes("@")) {
    fail("email_invalid");
  }
  if (claims.email_verified !== true) fail("email_unverified");
  if (typeof claims.nonce !== "string" || claims.nonce.length < 16 || claims.nonce.length > 512) {
    fail("nonce_invalid");
  }
  if (!/^[0-9a-f]{64}$/.test(expectedNonceHash)) fail("expected_nonce_invalid");
}

export function normalizeGoogleScopes(value) {
  const source = Array.isArray(value)
    ? value
    : typeof value === "string"
      ? value.split(/\s+/)
      : [];
  return [...new Set(source
    .map((scope) => typeof scope === "string" ? scope.trim() : "")
    .filter(Boolean)
    .map((scope) => GOOGLE_SCOPE_ALIASES.get(scope) || scope))].sort();
}

export function hasExactGoogleReadScopes(scopes) {
  const normalized = normalizeGoogleScopes(scopes);
  const required = [...GOOGLE_REQUIRED_SCOPES].sort();
  return normalized.length === required.length && normalized.every((scope, index) => scope === required[index]);
}

export async function verifyGoogleIdToken({
  idToken,
  clientId,
  expectedNonceHash,
  fetcher = fetch,
  now = () => Date.now(),
}) {
  if (typeof idToken !== "string" || !idToken || idToken.length > MAX_ID_TOKEN_BYTES) {
    fail("token_invalid");
  }
  if (typeof clientId !== "string" || !clientId || clientId.length > 512) fail("client_id_invalid");
  const segments = idToken.split(".");
  if (segments.length !== 3) fail("jwt_structure_invalid");
  const [encodedHeader, encodedPayload, encodedSignature] = segments;
  const header = decodeJsonSegment(encodedHeader);
  const claims = decodeJsonSegment(encodedPayload);
  if (header.alg !== "RS256" || typeof header.kid !== "string" || !/^[A-Za-z0-9._-]{1,256}$/.test(header.kid)) {
    fail("header_invalid");
  }
  if (header.crit !== undefined || header.jku !== undefined || header.x5u !== undefined) {
    fail("header_unsupported");
  }

  const response = await fetcher(GOOGLE_JWKS_URI, {
    method: "GET",
    headers: { accept: "application/json" },
    redirect: "error",
    signal: AbortSignal.timeout(10_000),
  });
  if (!response.ok) fail("jwks_unavailable");
  const payload = await response.json().catch(() => null);
  const keys = isRecord(payload) && Array.isArray(payload.keys)
    ? payload.keys.filter((key) => isRecord(key) && key.kid === header.kid)
    : [];
  if (keys.length !== 1) fail("signing_key_invalid");
  const jwk = keys[0];
  if (jwk.kty !== "RSA" || jwk.use !== "sig" || (jwk.alg !== undefined && jwk.alg !== "RS256") ||
      typeof jwk.n !== "string" || typeof jwk.e !== "string") {
    fail("signing_key_invalid");
  }

  let key;
  try {
    key = await crypto.subtle.importKey(
      "jwk",
      jwk,
      { name: "RSASSA-PKCS1-v1_5", hash: "SHA-256" },
      false,
      ["verify"],
    );
  } catch {
    fail("signing_key_invalid");
  }
  const signatureValid = await crypto.subtle.verify(
    "RSASSA-PKCS1-v1_5",
    key,
    decodeBase64Url(encodedSignature),
    new TextEncoder().encode(`${encodedHeader}.${encodedPayload}`),
  );
  if (!signatureValid) fail("signature_invalid");

  const nowSeconds = Math.floor(now() / 1000);
  validateClaims(claims, clientId, expectedNonceHash, nowSeconds);
  const nonceHash = await sha256Hex(claims.nonce);
  if (!equalHex(nonceHash, expectedNonceHash)) fail("nonce_mismatch");

  return Object.freeze({
    subject: claims.sub,
    email: claims.email.toLowerCase(),
    displayName: typeof claims.name === "string" ? claims.name.trim() : "",
    hostedDomain: typeof claims.hd === "string" ? claims.hd.toLowerCase() : "",
    nonce: claims.nonce,
    expiresAt: claims.exp,
  });
}
