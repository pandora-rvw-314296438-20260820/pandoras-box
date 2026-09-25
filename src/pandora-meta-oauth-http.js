"use strict";

const express = require("express");

const GRAPH_VERSION = "v26.0";
const CALLBACK_PATH = "/oauth/meta/callback";

function text(value) {
  return typeof value === "string" ? value.trim() : "";
}

function escapeHtml(value) {
  return String(value)
    .replaceAll("&", "&amp;")
    .replaceAll("<", "&lt;")
    .replaceAll(">", "&gt;")
    .replaceAll('"', "&quot;")
    .replaceAll("'", "&#39;");
}

function page(res, title, body, status = 200) {
  res.status(status);
  res.set("Content-Type", "text/html; charset=utf-8");
  res.set("Cache-Control", "no-store, max-age=0");
  res.set("X-Content-Type-Options", "nosniff");
  res.set("Referrer-Policy", "no-referrer");
  return res.send(
    "<!doctype html><meta name=\"viewport\" content=\"width=device-width,initial-scale=1\">" +
    "<title>" + escapeHtml(title) + "</title>" +
    "<body style=\"font-family:system-ui;background:#050505;color:#f5f5f5;padding:32px;max-width:680px;margin:auto\">" +
    "<h1>" + escapeHtml(title) + "</h1><p>" + escapeHtml(body) + "</p>" +
    "<p>Return to Pandora and refresh Connections.</p></body>"
  );
}

function createRuntime(environment, fetchFn) {
  const baseUrl = String(
    environment.SUPABASE_URL || environment.NEXT_PUBLIC_SUPABASE_URL || ""
  ).replace(/\/+$/, "");
  const serviceKey = String(
    environment.SUPABASE_SERVICE_ROLE_KEY || environment.SUPABASE_SECRET_KEY || ""
  );
  if (!baseUrl || !serviceKey) throw new Error("meta_backend_unconfigured");
  if (typeof fetchFn !== "function") throw new Error("fetch_unavailable");

  async function rpc(name, args) {
    const response = await fetchFn(baseUrl + "/rest/v1/rpc/" + name, {
      method: "POST",
      redirect: "error",
      headers: {
        apikey: serviceKey,
        authorization: "Bearer " + serviceKey,
        accept: "application/json",
        "content-type": "application/json",
      },
      body: JSON.stringify(args),
    });
    const value = await response.json().catch(() => null);
    if (!response.ok || value === null) throw new Error("meta_backend_rejected");
    return value;
  }

  async function graph(path, token) {
    const response = await fetchFn(
      "https://graph.facebook.com/" + GRAPH_VERSION + "/" + path,
      {
        redirect: "error",
        headers: {
          authorization: "Bearer " + token,
          accept: "application/json",
        },
      }
    );
    const value = await response.json().catch(() => ({}));
    if (!response.ok || (value && value.error)) throw new Error("meta_graph_rejected");
    return value;
  }

  return { rpc, graph, fetchFn };
}

function createPandoraMetaOauthRouter(options = {}) {
  const router = express.Router();
  const environment = options.environment || process.env;
  const fetchFn = options.fetchFn || globalThis.fetch;

  router.get(CALLBACK_PATH, async (req, res) => {
    try {
      const runtime = createRuntime(environment, fetchFn);
      const error = text(req.query.error);
      const state = text(req.query.state);
      const code = text(req.query.code);

      if (error) {
        return page(res, "Meta authorization was not completed", "No Pandora connection was changed.", 400);
      }
      if (!state || !code || state.length > 256 || code.length > 4096) {
        return page(res, "Invalid authorization response", "The callback did not include a valid one-time state and code.", 400);
      }

      const material = await runtime.rpc("pandora_meta_oauth_material_v1", { p_state: state });
      const appId = text(material && material.appId);
      const appSecret = text(material && material.appSecret);
      const redirectUri = text(material && material.redirectUri);
      const requiredScopes = Array.isArray(material && material.requiredScopes)
        ? material.requiredScopes.map(String)
        : [];
      if (!appId || !appSecret || !redirectUri) {
        return page(res, "Authorization unavailable", "Pandora Meta OAuth configuration is incomplete.", 503);
      }

      const tokenResponse = await runtime.fetchFn(
        "https://graph.facebook.com/" + GRAPH_VERSION + "/oauth/access_token",
        {
          method: "POST",
          redirect: "error",
          headers: {
            "content-type": "application/x-www-form-urlencoded",
            accept: "application/json",
          },
          body: new URLSearchParams({
            client_id: appId,
            client_secret: appSecret,
            redirect_uri: redirectUri,
            code,
          }),
        }
      );
      const shortToken = await tokenResponse.json().catch(() => ({}));
      const shortAccessToken = text(shortToken && shortToken.access_token);
      if (!tokenResponse.ok || !shortAccessToken) {
        return page(res, "Meta authorization could not be verified", "Pandora did not receive a usable authorization token.", 400);
      }

      const longUrl = new URL("https://graph.facebook.com/" + GRAPH_VERSION + "/oauth/access_token");
      longUrl.searchParams.set("grant_type", "fb_exchange_token");
      longUrl.searchParams.set("client_id", appId);
      longUrl.searchParams.set("client_secret", appSecret);
      longUrl.searchParams.set("fb_exchange_token", shortAccessToken);
      const longResponse = await runtime.fetchFn(longUrl, {
        redirect: "error",
        headers: { accept: "application/json" },
      });
      const longValue = await longResponse.json().catch(() => ({}));
      const userToken =
        longResponse.ok && text(longValue && longValue.access_token)
          ? text(longValue.access_token)
          : shortAccessToken;
      const expiresIn = Number(
        (longValue && longValue.expires_in) || (shortToken && shortToken.expires_in) || 0
      );

      const values = await Promise.all([
        runtime.graph("me?fields=id,name", userToken),
        runtime.graph("me/permissions", userToken),
        runtime.graph("me/accounts?fields=id,name,tasks,access_token&limit=100", userToken),
        runtime.graph("me/adaccounts?fields=id,account_id,name,account_status,currency,business%7Bid,name%7D&limit=100", userToken),
      ]);
      const identity = values[0];
      const permissions = values[1];
      const pagesValue = values[2];
      const adAccountsValue = values[3];

      const providerUserId = text(identity && identity.id);
      const displayName = text(identity && identity.name);
      const permissionRows = Array.isArray(permissions && permissions.data)
        ? permissions.data
        : [];
      const grantedScopes = permissionRows
        .filter((row) => text(row && row.status) === "granted")
        .map((row) => text(row && row.permission))
        .filter(Boolean);
      const granted = new Set(grantedScopes);
      if (!providerUserId || !requiredScopes.every((scope) => granted.has(scope))) {
        return page(res, "Meta authorization is incomplete", "Pandora could not verify all required Page and Marketing API permissions. No connection was committed.", 400);
      }

      const pages = Array.isArray(pagesValue && pagesValue.data) ? pagesValue.data : [];
      const adAccounts = Array.isArray(adAccountsValue && adAccountsValue.data)
        ? adAccountsValue.data
        : [];
      if (!pages.length) {
        return page(res, "No Facebook Page access found", "The authorized account did not expose a manageable Facebook Page.", 400);
      }

      const committed = await runtime.rpc("pandora_meta_oauth_commit_v1", {
        p_state: state,
        p_provider_user_id: providerUserId,
        p_display_name: displayName || null,
        p_user_token: userToken,
        p_expires_in: Number.isFinite(expiresIn) ? Math.max(0, Math.floor(expiresIn)) : 0,
        p_granted_scopes: grantedScopes,
        p_pages: pages,
        p_ad_accounts: adAccounts,
      });
      if (!committed || committed.ok !== true) {
        return page(res, "Meta authorization could not be saved", "Pandora verified Meta but could not commit the Vault-backed connection.", 500);
      }

      return page(
        res,
        "Facebook & Instagram connected",
        "Pandora verified " + pages.length + " Page" + (pages.length === 1 ? "" : "s") +
          " and " + adAccounts.length + " ad account" + (adAccounts.length === 1 ? "" : "s") + "."
      );
    } catch {
      return page(res, "Meta authorization failed", "Pandora rejected the callback safely. Start again from Connections.", 500);
    }
  });

  return router;
}

module.exports = {
  CALLBACK_PATH,
  createPandoraMetaOauthRouter,
};
