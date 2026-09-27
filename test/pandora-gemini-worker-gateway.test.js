"use strict";

const assert = require("node:assert/strict");
const fs = require("node:fs");
const test = require("node:test");

const gateway = fs.readFileSync(
  "supabase/functions/pandora-gemini-worker-gateway/index.ts",
  "utf8",
);
const config = fs.readFileSync("supabase/config.toml", "utf8");
const mcp = fs.readFileSync("api/gemini-mcp.ts", "utf8");
const handler = fs.readFileSync("src/pandora-mcp-handler.js", "utf8");

test("Gemini worker gateway accepts only exact mcpmaster development OIDC", () => {
  assert.match(gateway, /https:\/\/oidc\.vercel\.com\/mbanatao/);
  assert.match(gateway, /const ENVIRONMENT = "development"/);
  assert.match(gateway, /prj_Y5rZVcq8xJVzHVt4uvfmg9wPvXMk/);
  assert.match(gateway, /team_3yw1CN59ce4pj5SwyQGCAqN3/);
  assert.match(gateway, /owner:mbanatao:project:mcpmaster:environment:development/);
  assert.doesNotMatch(gateway, /environment.*production/i);
});

test("Gemini provider key remains server-side and Vault-backed", () => {
  assert.match(gateway, /pandora_gemini_stream_credential_service_20260901/);
  assert.match(gateway, /generativelanguage\.googleapis\.com/);
  assert.match(gateway, /headers\.set\("x-goog-api-key", apiKey\)/);
  assert.doesNotMatch(gateway, /GEMINI_API_KEY/);
  assert.doesNotMatch(gateway, /console\.(log|error).*apiKey/);
});

test("Gateway cannot become an arbitrary HTTP proxy", () => {
  assert.match(gateway, /MODEL_PATH\.test\(path\)/);
  assert.match(gateway, /GEMINI_ROUTE_NOT_ALLOWED/);
  assert.match(gateway, /if \(key\.toLowerCase\(\) === "key"\) continue/);
  assert.match(gateway, /\["GET", "POST"\]/);
  assert.match(gateway, /MAX_BODY_BYTES/);
});

test("Supabase platform JWT check is disabled only because the function verifies Vercel OIDC itself", () => {
  assert.match(
    config,
    /\[functions\.pandora-gemini-worker-gateway\]\s+verify_jwt = false\s+enabled = false/,
  );
});

test("Gemini MCP uses worker identity, never approval authority, and Vercel Connect for GitHub", () => {
  assert.match(mcp, /pandora-gemini-worker-gateway\/identity/);
  assert.match(mcp, /role: 'operator'/);
  assert.match(mcp, /'pandora:execute'/);
  assert.doesNotMatch(mcp, /'pandora:approve'/);
  assert.match(mcp, /connectorUid: CONNECTOR_UID/);
  assert.match(mcp, /installationId: INSTALLATION_ID/);
  assert.match(mcp, /allowedRepositories: \[CANONICAL_REPOSITORY\]/);
  assert.match(mcp, /canExecutePlan/);
});

test("Core MCP execution remains default owner-admin but supports a route-specific executor predicate", () => {
  assert.match(handler, /canExecutePlan: \(actor\) => EXECUTOR_ROLES\.has\(actor\.membership\.role\)/);
  assert.match(handler, /if \(!dependencies\.canExecutePlan\(actor\)\)/);
  assert.match(handler, /canApprovePandoraPlan\(actor\)/);
});
