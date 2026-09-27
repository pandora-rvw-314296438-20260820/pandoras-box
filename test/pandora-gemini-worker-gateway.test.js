"use strict";

const assert = require("node:assert/strict");
const fs = require("node:fs");
const test = require("node:test");

const gateway = fs.readFileSync(
  "supabase/functions/mcpmaster-supabase-control/gemini-worker-gateway.mjs",
  "utf8",
);
const control = fs.readFileSync(
  "supabase/functions/mcpmaster-supabase-control/index.ts",
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

test("Gemini route is isolated inside the existing control function and cannot reach production control actions", () => {
  assert.match(control, /handleGeminiWorkerRequest/);
  const serve = control.indexOf("Deno.serve");
  const worker = control.indexOf("handleGeminiWorkerRequest", serve);
  const production = control.indexOf("verifyVercelToken", serve);
  assert.ok(serve >= 0 && worker > serve && production > worker);
  assert.match(gateway, /ROUTE_MARKER = "\/mcpmaster-supabase-control\/gemini-worker"/);
  assert.match(gateway, /MODEL_PATH\.test\(path\)/);
  assert.match(gateway, /GEMINI_ROUTE_NOT_ALLOWED/);
  assert.match(gateway, /if \(key\.toLowerCase\(\) === "key"\) continue/);
  assert.doesNotMatch(config, /\[functions\.pandora-gemini-worker-gateway\]/);
  assert.match(config, /\[functions\.mcpmaster-supabase-control\]\s+verify_jwt = false/);
});

test("Gemini MCP uses worker identity, never approval authority, and Vercel Connect for GitHub", () => {
  assert.match(mcp, /mcpmaster-supabase-control\/gemini-worker\/identity/);
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
