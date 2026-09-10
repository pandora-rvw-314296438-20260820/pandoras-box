"use strict";

const fs = require("node:fs");
const test = require("node:test");
const assert = require("node:assert/strict");

const bridge = fs.readFileSync(
  "supabase/functions/pandora-base44-read-bridge/index.ts",
  "utf8",
);
const migration = fs.readFileSync(
  "supabase/migrations/20260910043000_pandora_base44_identity_bridge_v1.sql",
  "utf8",
);

test("bridge is pinned to the exact verified Base44 app and origin", () => {
  assert.match(bridge, /BASE44_APP_ID = "6a94ecfadf75736cd4ebf7e1"/);
  assert.match(
    bridge,
    /BASE44_ORIGIN = "https:\/\/app--build-with-pandora\.base44\.app"/,
  );
  assert.doesNotMatch(bridge, /\*\.base44\.app/);
  assert.doesNotMatch(bridge, /https:\/\/app\.base44\.com"/);
});

test("Base44 bearer token is validated server-side against User me before service reads", () => {
  const auth = bridge.indexOf("validateBase44User(token)");
  const admin = bridge.indexOf("createClient(SUPABASE_URL, SERVICE_ROLE");
  assert.ok(auth > 0);
  assert.ok(admin > auth);
  assert.match(
    bridge,
    /api\/apps\/\$\{BASE44_APP_ID\}\/entities\/User\/me/,
  );
  assert.match(bridge, /user\.is_verified !== true/);
  assert.match(bridge, /user\.disabled === true/);
});

test("identity mapping is service-only and exact", () => {
  assert.match(
    migration,
    /primary key \(base44_app_id, base44_user_id\)/,
  );
  assert.match(
    migration,
    /revoke all on table public\.pandora_base44_identity_links from public, anon, authenticated/,
  );
  assert.match(
    migration,
    /grant select, insert, update, delete on table public\.pandora_base44_identity_links to service_role/,
  );
  assert.match(migration, /6a94ecfadf75736cd4ebf7e1/);
  assert.match(migration, /6a94ecfadf75736cd4ebf7e2/);
  assert.match(migration, /f17558e4-e1b2-4b8d-a215-b96775b1a470/);
});

test("bridge is read-only, membership-bound, and rate-limited", () => {
  assert.match(bridge, /req\.method !== "GET"/);
  assert.match(bridge, /"access-control-allow-methods": "GET, OPTIONS"/);
  assert.match(bridge, /from\("memberships"\)/);
  assert.match(bridge, /\.eq\("status", "active"\)/);
  assert.match(bridge, /from\("projectos_projects"\)/);
  assert.match(bridge, /\.eq\("organization_id", organizationId\)/);
  assert.match(bridge, /consume_runtime_rate_limit/);
  assert.doesNotMatch(bridge, /\.insert\(/);
  assert.doesNotMatch(bridge, /\.update\(/);
  assert.doesNotMatch(bridge, /\.delete\(/);
});

test("theatre truth is never invented", () => {
  assert.match(
    bridge,
    /mode: "idle"[\s\S]*ownerStage: null,[\s\S]*progressPercent: null/,
  );
  assert.match(
    bridge,
    /source: "pandora_build_theatre_projection"/,
  );
  assert.match(
    bridge,
    /mode: activeBuildJobId === buildJobId \? "active" : "result"/,
  );
  assert.match(bridge, /canPublish: experience\.can_publish === true/);
  assert.match(
    bridge,
    /live: Boolean\(theatre\.liveUrl\)[\s\S]*production_deployment_id/,
  );
});

test("bridge never exposes or embeds Pandora provider credentials", () => {
  assert.doesNotMatch(
    bridge,
    /service_role\s*[:=]\s*["'][A-Za-z0-9._-]{20,}/i,
  );
  assert.doesNotMatch(bridge, /github_pat_|ghp_|sk-proj-/i);
  assert.doesNotMatch(bridge, /base44_access_token/);
});
