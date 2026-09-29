"use strict";

const assert = require("node:assert/strict");
const fs = require("node:fs");
const test = require("node:test");

const chat = fs.readFileSync("supabase/functions/pandora-intelligence-chat/index.ts", "utf8");
const router = fs.readFileSync("src/pandora-growth-memory-http.js", "utf8");
const entry = fs.readFileSync("vercel-entrypoint.js", "utf8");

test("Ask Pandora hydrates growth metrics and approved Memory server-side", () => {
  assert.match(chat, /hydrateGrowthCommandContext\(c\.user,c\.organizationId,i\.enterpriseContext\)/);
  assert.match(chat, /hydrateGrowthMemoryContext\(req,c\.organizationId,i\.enterpriseContext,i\.message\)/);
  assert.match(chat, /pandora_marketing_growth_command_center_v2/);
  assert.match(chat, /https:\/\/mcpmaster\.vercel\.app\/api\/growth\/memory-context/);
  assert.match(chat, /growthApprovedMemory:records/);
  assert.match(chat, /growthMemorySourceHealth:\{status:"verified"/);
});

test("Supabase chat runtime never receives or forwards Vercel workload identity", () => {
  assert.doesNotMatch(chat, /x-pandora-vercel-oidc|getVercelOidcToken|resolveVercelWorkloadToken/);
  assert.match(router, /x-pandora-vercel-oidc/);
  assert.match(router, /resolveVercelWorkloadToken/);
  assert.match(router, /MEMORY_BRIDGE_URL/);
});

test("growth prompt preserves evidence and authority boundaries", () => {
  assert.match(chat, /Business KPIs exclude test traffic/);
  assert.match(chat, /Never invent a winner, causal claim, provider delivery, spend, publication or campaign mutation/);
  assert.match(chat, /Pending, rejected, revoked and superseded learning is excluded/);
  assert.match(chat, /Memory retrieval never grants execution authority/);
  assert.match(chat, /If approvalGates say not_granted, treat the action as not authorized/);
});

test("Vercel endpoint is mounted before the public tracking and container fallback", () => {
  const importAt = entry.indexOf("createPandoraGrowthMemoryRouter");
  const mountAt = entry.indexOf("app.use(createPandoraGrowthMemoryRouter())");
  const trackingAt = entry.indexOf("app.use(createPandoraTrackingRouter())");
  const containerAt = entry.indexOf("app.use(createPandoraContainerApp())");
  assert.ok(importAt >= 0);
  assert.ok(mountAt > importAt);
  assert.ok(trackingAt > mountAt);
  assert.ok(containerAt > trackingAt);
});

test("live growth Memory remains independent of Operations Room state", () => {
  const growthFunction = chat.slice(
    chat.indexOf("async function hydrateGrowthCommandContext"),
    chat.indexOf("function request(", chat.indexOf("async function hydrateGrowthCommandContext")),
  );
  assert.doesNotMatch(growthFunction, /pandora_ops_|operations room|operations_room/i);
  assert.match(router, /operationsRoomRequired !== false/);
  assert.doesNotMatch(router, /pandora_ops_tasks|pandora_ops_events|pandora_ops_human_gates/);
});
