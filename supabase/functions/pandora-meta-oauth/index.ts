import "jsr:@supabase/functions-js@2.4.5/edge-runtime.d.ts";
import { createClient } from "jsr:@supabase/supabase-js@2.57.2";
const SUPABASE_URL = Deno.env.get("SUPABASE_URL") || "";
const SERVICE = Deno.env.get("SUPABASE_SERVICE_ROLE_KEY") || "";
const admin = createClient(SUPABASE_URL, SERVICE, { auth: { persistSession: false, autoRefreshToken: false } });
const GRAPH_VERSION = "v26.0";
const headers = { "content-type": "text/html; charset=utf-8", "cache-control": "no-store", "x-content-type-options": "nosniff", "referrer-policy": "no-referrer" };
const text = (v: unknown) => typeof v === "string" ? v.trim() : "";
const page = (title: string, body: string, status = 200) => new Response(
  `<!doctype html><meta name="viewport" content="width=device-width,initial-scale=1"><title>${title}</title><body style="font-family:system-ui;background:#050505;color:#f5f5f5;padding:32px;max-width:680px;margin:auto"><h1>${title}</h1><p>${body}</p><p>Return to Pandora and refresh Connections.</p></body>`,
  { status, headers },
);
async function graph(path: string, token: string) {
  const response = await fetch(`https://graph.facebook.com/${GRAPH_VERSION}/${path}`, { headers: { authorization: `Bearer ${token}`, accept: "application/json" }, redirect: "error" });
  const value = await response.json().catch(() => ({})) as Record<string, unknown>;
  if (!response.ok || value.error) throw new Error("meta_graph_rejected");
  return value;
}
Deno.serve(async (req: Request) => {
  try {
    const url = new URL(req.url);
    if (!url.pathname.endsWith("/callback") || req.method !== "GET") return page("Not found", "This endpoint accepts only the Meta OAuth callback.", 404);
    const error = text(url.searchParams.get("error")), state = text(url.searchParams.get("state")), code = text(url.searchParams.get("code"));
    if (error) return page("Meta authorization was not completed", "No Pandora connection was changed.", 400);
    if (!state || !code || state.length > 256 || code.length > 4096) return page("Invalid authorization response", "The callback did not include a valid one-time state and code.", 400);

    const material = await admin.rpc("pandora_meta_oauth_material_v1", { p_state: state });
    if (material.error || !material.data) return page("Authorization expired", "Start Meta authorization again from Pandora.", 400);
    const m = material.data as Record<string, unknown>;
    const appId = text(m.appId), appSecret = text(m.appSecret), redirectUri = text(m.redirectUri);
    const requiredScopes = Array.isArray(m.requiredScopes) ? m.requiredScopes.map(String) : [];
    if (!appId || !appSecret || !redirectUri) return page("Authorization unavailable", "Pandora Meta OAuth configuration is incomplete.", 503);

    const tokenResponse = await fetch(`https://graph.facebook.com/${GRAPH_VERSION}/oauth/access_token`, {
      method: "POST", headers: { "content-type": "application/x-www-form-urlencoded", accept: "application/json" },
      body: new URLSearchParams({ client_id: appId, client_secret: appSecret, redirect_uri: redirectUri, code }), redirect: "error",
    });
    const shortToken = await tokenResponse.json().catch(() => ({})) as Record<string, unknown>;
    const shortAccessToken = text(shortToken.access_token);
    if (!tokenResponse.ok || !shortAccessToken) return page("Meta authorization could not be verified", "Pandora did not receive a usable authorization token.", 400);

    const longUrl = new URL(`https://graph.facebook.com/${GRAPH_VERSION}/oauth/access_token`);
    longUrl.searchParams.set("grant_type", "fb_exchange_token"); longUrl.searchParams.set("client_id", appId); longUrl.searchParams.set("client_secret", appSecret); longUrl.searchParams.set("fb_exchange_token", shortAccessToken);
    const longResponse = await fetch(longUrl, { headers: { accept: "application/json" }, redirect: "error" });
    const longValue = await longResponse.json().catch(() => ({})) as Record<string, unknown>;
    const userToken = longResponse.ok && text(longValue.access_token) ? text(longValue.access_token) : shortAccessToken;
    const expiresIn = Number(longValue.expires_in ?? shortToken.expires_in ?? 0);

    const [identity, permissions, pagesValue, adAccountsValue] = await Promise.all([
      graph("me?fields=id,name", userToken),
      graph("me/permissions", userToken),
      graph("me/accounts?fields=id,name,tasks,access_token&limit=100", userToken),
      graph("me/adaccounts?fields=id,account_id,name,account_status,currency,business%7Bid,name%7D&limit=100", userToken),
    ]);
    const providerUserId = text(identity.id), displayName = text(identity.name);
    const permissionRows = Array.isArray(permissions.data) ? permissions.data as Array<Record<string, unknown>> : [];
    const grantedScopes = permissionRows.filter((row) => text(row.status) === "granted").map((row) => text(row.permission)).filter(Boolean);
    const granted = new Set(grantedScopes);
    if (!providerUserId || !requiredScopes.every((scope) => granted.has(scope))) return page("Meta authorization is incomplete", "Pandora could not verify all required Page and Marketing API permissions. No connection was committed.", 400);
    const pages = Array.isArray(pagesValue.data) ? pagesValue.data : [], adAccounts = Array.isArray(adAccountsValue.data) ? adAccountsValue.data : [];
    if (!pages.length) return page("No Facebook Page access found", "The authorized account did not expose a manageable Facebook Page.", 400);

    const committed = await admin.rpc("pandora_meta_oauth_commit_v1", {
      p_state: state, p_provider_user_id: providerUserId, p_display_name: displayName || null, p_user_token: userToken,
      p_expires_in: Number.isFinite(expiresIn) ? Math.max(0, Math.floor(expiresIn)) : 0, p_granted_scopes: grantedScopes,
      p_pages: pages, p_ad_accounts: adAccounts,
    });
    if (committed.error || committed.data?.ok !== true) return page("Meta authorization could not be saved", "Pandora verified Meta but could not commit the Vault-backed connection.", 500);
    return page("Facebook & Instagram connected", `Pandora verified ${pages.length} Page${pages.length === 1 ? "" : "s"} and ${adAccounts.length} ad account${adAccounts.length === 1 ? "" : "s"}.`);
  } catch {
    return page("Meta authorization failed", "Pandora rejected the callback safely. Start again from Connections.", 500);
  }
});
