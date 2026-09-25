"use strict";

const assert = require("node:assert/strict");
const fs = require("node:fs");
const path = require("node:path");
const test = require("node:test");

const root = path.resolve(__dirname, "..");
const entry = fs.readFileSync(path.join(root, "vercel-entrypoint.js"), "utf8");
const callback = fs.readFileSync(path.join(root, "src", "pandora-meta-oauth-http.js"), "utf8");
const migration = fs.readFileSync(
  path.join(root, "supabase", "migrations", "20260925070000_pandora_meta_oauth_vercel_callback_v1.sql"),
  "utf8",
);

test("Vercel mounts the bounded public Meta OAuth callback", () => {
  assert.match(entry, /createPandoraMetaOauthRouter/);
  assert.match(entry, /app\.use\(createPandoraMetaOauthRouter\(\)\)/);
  assert.match(callback, /router\.get\(CALLBACK_PATH/);
  assert.match(callback, /const CALLBACK_PATH = "\/oauth\/meta\/callback"/);
});

test("Meta callback keeps OAuth secrets server-side and commits through Vault-backed RPCs", () => {
  assert.match(callback, /SUPABASE_SERVICE_ROLE_KEY/);
  assert.match(callback, /pandora_meta_oauth_material_v1/);
  assert.match(callback, /pandora_meta_oauth_commit_v1/);
  assert.match(callback, /https:\/\/graph\.facebook\.com\//);
  assert.doesNotMatch(callback, /res\.json\([^\n]*(appSecret|userToken|shortAccessToken)/);
});

test("Meta OAuth redirect is moved off the saturated Supabase Edge Function surface", () => {
  assert.match(migration, /https:\/\/mcpmaster\.vercel\.app\/oauth\/meta\/callback/);
  assert.doesNotMatch(migration, /supabase\.co\/functions\/v1\/pandora-meta-oauth/);
  assert.match(migration, /pandora_meta_oauth_prepare_v1/);
});
