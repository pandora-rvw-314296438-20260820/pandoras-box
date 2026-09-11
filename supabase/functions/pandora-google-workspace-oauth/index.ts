import "jsr:@supabase/functions-js@2.4.5/edge-runtime.d.ts";
import { createClient } from "jsr:@supabase/supabase-js@2.57.2";

const URL = Deno.env.get("SUPABASE_URL") || "";
const SERVICE = Deno.env.get("SUPABASE_SERVICE_ROLE_KEY") || "";
const admin = createClient(URL, SERVICE, { auth: { persistSession: false, autoRefreshToken: false } });
const headers = { "content-type": "text/html; charset=utf-8", "cache-control": "no-store", "x-content-type-options": "nosniff", "referrer-policy": "no-referrer" };
const text = (v: unknown) => typeof v === "string" ? v.trim() : "";
const page = (title: string, body: string, status = 200) => new Response(`<!doctype html><meta name="viewport" content="width=device-width,initial-scale=1"><title>${title}</title><body style="font-family:system-ui;background:#0b0b0d;color:#f5f5f5;padding:32px;max-width:680px;margin:auto"><h1>${title}</h1><p>${body}</p><p>Return to Pandora and refresh Plugins.</p></body>`, { status, headers });

Deno.serve(async (req: Request) => {
  try {
    const url = new URL(req.url);
    if (!url.pathname.endsWith("/callback") || req.method !== "GET") return page("Not found", "This endpoint accepts only the Google OAuth callback.", 404);
    const error = text(url.searchParams.get("error"));
    const state = text(url.searchParams.get("state"));
    const code = text(url.searchParams.get("code"));
    if (error) return page("Google authorization was not completed", "No Pandora connection was changed.", 400);
    if (!state || !code || state.length > 256 || code.length > 4096) return page("Invalid authorization response", "The callback did not include a valid one-time state and code.", 400);

    const material = await admin.rpc("pandora_google_workspace_oauth_material_v1", { p_state: state });
    if (material.error || !material.data) return page("Authorization expired", "Start Google authorization again from Pandora.", 400);
    const m = material.data as Record<string, unknown>;
    const clientId = text(m.clientId), clientSecret = text(m.clientSecret), verifier = text(m.codeVerifier), redirectUri = text(m.redirectUri);
    const requiredScopes = Array.isArray(m.requiredScopes) ? m.requiredScopes.map(String) : [];
    if (!clientId || !clientSecret || !verifier || !redirectUri) return page("Authorization unavailable", "Pandora Google OAuth configuration is incomplete.", 503);

    const tokenResponse = await fetch("https://oauth2.googleapis.com/token", { method: "POST", headers: { "content-type": "application/x-www-form-urlencoded", accept: "application/json" }, body: new URLSearchParams({ code, client_id: clientId, client_secret: clientSecret, redirect_uri: redirectUri, grant_type: "authorization_code", code_verifier: verifier }) });
    const token = await tokenResponse.json().catch(() => ({})) as Record<string, unknown>;
    const accessToken = text(token.access_token), refreshToken = text(token.refresh_token);
    if (!tokenResponse.ok || !accessToken || !refreshToken) return page("Google authorization could not be verified", "Pandora did not receive reusable authorization. No connection was committed.", 400);

    const [userinfoResponse, driveResponse, tokenInfoResponse] = await Promise.all([
      fetch("https://www.googleapis.com/oauth2/v3/userinfo", { headers: { authorization: `Bearer ${accessToken}`, accept: "application/json" } }),
      fetch("https://www.googleapis.com/drive/v3/about?fields=user", { headers: { authorization: `Bearer ${accessToken}`, accept: "application/json" } }),
      fetch(`https://oauth2.googleapis.com/tokeninfo?access_token=${encodeURIComponent(accessToken)}`, { headers: { accept: "application/json" } }),
    ]);
    const userinfo = await userinfoResponse.json().catch(() => ({})) as Record<string, unknown>;
    const drive = await driveResponse.json().catch(() => ({})) as Record<string, unknown>;
    const tokenInfo = await tokenInfoResponse.json().catch(() => ({})) as Record<string, unknown>;
    const subject = text(userinfo.sub), email = text(userinfo.email).toLowerCase(), displayName = text(userinfo.name);
    const grantedScopes = [...new Set((text(tokenInfo.scope) || text(token.scope)).split(/\s+/).filter(Boolean))];
    const scopeSet = new Set(grantedScopes);
    if (!userinfoResponse.ok || !driveResponse.ok || !tokenInfoResponse.ok || !subject || !email || !drive.user || !requiredScopes.every((scope) => scopeSet.has(scope))) return page("Google authorization is incomplete", "Pandora could not verify the account, required scopes and live Drive access. No connection was committed.", 400);

    const committed = await admin.rpc("pandora_google_workspace_oauth_commit_v1", { p_state: state, p_provider_subject: subject, p_account_email: email, p_display_name: displayName || null, p_refresh_token: refreshToken, p_granted_scopes: grantedScopes });
    if (committed.error || committed.data?.ok !== true) return page("Google authorization could not be saved", "Pandora verified Google but could not commit the connection.", 500);
    return page("Google Workspace connected", `Pandora verified ${email} with the required Drive and Sheets scopes.`);
  } catch {
    return page("Google authorization failed", "Pandora rejected the callback safely. Start again from Plugins.", 500);
  }
});