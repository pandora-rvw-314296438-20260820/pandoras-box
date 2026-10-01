import "jsr:@supabase/functions-js@2.4.5/edge-runtime.d.ts";
import { createClient } from "jsr:@supabase/supabase-js@2.57.2";
import {
  hasExactGoogleReadScopes,
  normalizeGoogleScopes,
  verifyGoogleIdToken,
} from "./google_oidc_verification.mjs";

const supabaseUrl = Deno.env.get("SUPABASE_URL") || "";
const serviceRoleKey = Deno.env.get("SUPABASE_SERVICE_ROLE_KEY") || "";
const admin = createClient(supabaseUrl, serviceRoleKey, {
  auth: { persistSession: false, autoRefreshToken: false },
});
const headers = {
  "content-type": "text/html; charset=utf-8",
  "cache-control": "no-store",
  "content-security-policy": "default-src 'none'; style-src 'unsafe-inline'; base-uri 'none'; form-action 'none'; frame-ancestors 'none'",
  "x-content-type-options": "nosniff",
  "x-frame-options": "DENY",
  "referrer-policy": "no-referrer",
};
const text = (value: unknown) => typeof value === "string" ? value.trim() : "";
const record = (value: unknown): Record<string, unknown> =>
  value !== null && typeof value === "object" && !Array.isArray(value)
    ? value as Record<string, unknown>
    : {};
const escapeHtml = (value: string) => value.replace(/[&<>"']/g, (character) => ({
  "&": "&amp;",
  "<": "&lt;",
  ">": "&gt;",
  '"': "&quot;",
  "'": "&#39;",
}[character] || character));
const page = (title: string, body: string, status = 200) => new Response(
  `<!doctype html><meta name="viewport" content="width=device-width,initial-scale=1"><title>${escapeHtml(title)}</title><body style="font-family:system-ui;background:#0b0b0d;color:#f5f5f5;padding:32px;max-width:680px;margin:auto"><h1>${escapeHtml(title)}</h1><p>${escapeHtml(body)}</p><p>Return to Pandora and refresh Connections.</p></body>`,
  { status, headers },
);

Deno.serve(async (req: Request) => {
  try {
    const requestUrl = new URL(req.url);
    if (!requestUrl.pathname.endsWith("/callback") || req.method !== "GET") {
      return page("Not found", "This endpoint accepts only the Google OAuth callback.", 404);
    }
    const error = text(requestUrl.searchParams.get("error"));
    const state = text(requestUrl.searchParams.get("state"));
    const code = text(requestUrl.searchParams.get("code"));
    if (error) return page("Google authorization was not completed", "No Pandora connection was changed.", 400);
    if (!state || !code || state.length > 256 || code.length > 4096) {
      return page("Invalid authorization response", "The callback did not include a valid one-time state and code.", 400);
    }

    const material = await admin.rpc("pandora_google_workspace_oauth_material_v1", { p_state: state });
    if (material.error || !material.data) {
      return page("Authorization expired", "Start Google authorization again from Pandora.", 400);
    }
    const configuration = record(material.data);
    const clientId = text(configuration.clientId);
    const clientSecret = text(configuration.clientSecret);
    const verifier = text(configuration.codeVerifier);
    const redirectUri = text(configuration.redirectUri);
    const nonceHash = text(configuration.nonceHash);
    const requiredScopes = normalizeGoogleScopes(configuration.requiredScopes);
    if (!clientId || !clientSecret || verifier.length < 43 || verifier.length > 128 ||
        !redirectUri || !/^[0-9a-f]{64}$/.test(nonceHash) || !hasExactGoogleReadScopes(requiredScopes)) {
      return page("Authorization unavailable", "Pandora Google OAuth configuration is incomplete.", 503);
    }

    const tokenResponse = await fetch("https://oauth2.googleapis.com/token", {
      method: "POST",
      headers: { "content-type": "application/x-www-form-urlencoded", accept: "application/json" },
      body: new URLSearchParams({
        code,
        client_id: clientId,
        client_secret: clientSecret,
        redirect_uri: redirectUri,
        grant_type: "authorization_code",
        code_verifier: verifier,
      }),
      redirect: "error",
      signal: AbortSignal.timeout(15_000),
    });
    const token = record(await tokenResponse.json().catch(() => ({})));
    const accessToken = text(token.access_token);
    const refreshToken = text(token.refresh_token);
    const idToken = text(token.id_token);
    const tokenType = text(token.token_type).toLowerCase();
    const expiresIn = Number(token.expires_in);
    const grantedScopes = normalizeGoogleScopes(token.scope);
    if (!tokenResponse.ok || !accessToken || accessToken.length > 8192 ||
        !refreshToken || refreshToken.length > 8192 || !idToken || idToken.length > 16_384 ||
        tokenType !== "bearer" || !Number.isFinite(expiresIn) || expiresIn <= 0 || expiresIn > 86_400 ||
        !hasExactGoogleReadScopes(grantedScopes)) {
      return page("Google authorization could not be verified", "Pandora did not receive least-privilege reusable OIDC authorization. No connection was committed.", 400);
    }

    const identity = await verifyGoogleIdToken({
      idToken,
      clientId,
      expectedNonceHash: nonceHash,
    });
    const [userinfoResponse, driveResponse] = await Promise.all([
      fetch("https://openidconnect.googleapis.com/v1/userinfo", {
        headers: { authorization: `Bearer ${accessToken}`, accept: "application/json" },
        redirect: "error",
        signal: AbortSignal.timeout(15_000),
      }),
      fetch("https://www.googleapis.com/drive/v3/about?fields=user(emailAddress,displayName,permissionId)", {
        headers: { authorization: `Bearer ${accessToken}`, accept: "application/json" },
        redirect: "error",
        signal: AbortSignal.timeout(15_000),
      }),
    ]);
    const userinfo = record(await userinfoResponse.json().catch(() => ({})));
    const drive = record(await driveResponse.json().catch(() => ({})));
    const driveUser = record(drive.user);
    const userinfoSubject = text(userinfo.sub);
    const userinfoEmail = text(userinfo.email).toLowerCase();
    const driveEmail = text(driveUser.emailAddress).toLowerCase();
    const identityVerified = userinfoResponse.ok && driveResponse.ok && userinfo.email_verified === true &&
      userinfoSubject === identity.subject && userinfoEmail === identity.email && driveEmail === identity.email;
    if (!identityVerified) {
      return page("Google authorization is incomplete", "Pandora could not verify the OIDC account identity and live Drive readback. No connection was committed.", 400);
    }

    const committed = await admin.rpc("pandora_google_workspace_oauth_commit_v1", {
      p_state: state,
      p_provider_subject: identity.subject,
      p_account_email: identity.email,
      p_display_name: identity.displayName || text(userinfo.name) || text(driveUser.displayName) || null,
      p_refresh_token: refreshToken,
      p_granted_scopes: grantedScopes,
      p_oidc_nonce: identity.nonce,
    });
    if (committed.error || committed.data?.ok !== true) {
      return page("Google authorization could not be saved", "Pandora verified Google but could not commit the connection.", 500);
    }
    return page("Google Workspace connected", `Pandora verified ${identity.email} with read-only Drive and Sheets scopes.`);
  } catch {
    return page("Google authorization failed", "Pandora rejected the callback safely. Start again from Connections.", 500);
  }
});
