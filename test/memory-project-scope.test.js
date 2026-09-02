"use strict";

const assert = require("node:assert/strict");
const test = require("node:test");

const { executeMemoryTool } = require("../dist/tools/memory.js");
const {
  createCanonicalMemoryHealthProbe,
} = require("../dist/projectos-container-server.js");
const {
  PandoraPlanMemoryContextProvider,
} = require("../dist/runtime/plan-memory-context.js");

const PROJECT_KEY = "mcpmaster-pandoras-box";
const CONFIG = {
  baseUrl: "https://memory.example.test",
  oidcToken: "o".repeat(64),
  allowedNamespaces: ["real_life"],
  grantedScopes: ["memory:health", "memory:read"],
  timeoutMs: 8000,
  maxResponseBytes: 500000,
};

function memoryPayload() {
  return {
    ok: true,
    namespace: "real_life",
    current_task: null,
    adaptive_profile: [],
    style_profile: [],
    project_context: [],
    people_context: [],
    risk_warnings: [],
    open_loops: [],
    latest_context_pack: null,
    daily_context_pack: null,
    recent_events: [],
    semantic_matches: [],
    canonical_records: [],
    approved_record_count: 0,
    requested_canon_statuses: ["hard_canon", "soft_canon"],
    retrieval_mode: "project_scoped_keyword_recency",
    retrieval_reasoning_summary: "Exact-project test response.",
    warnings: [],
  };
}

function jsonResponse(payload) {
  const text = JSON.stringify(payload);
  return {
    ok: true,
    status: 200,
    headers: { get: () => null },
    text: async () => text,
  };
}

test("memory.search requires an explicit project key before network access", async () => {
  let calls = 0;
  await assert.rejects(
    () => executeMemoryTool(
      "memory.search",
      { namespace: "real_life", query: "current state" },
      CONFIG,
      async () => {
        calls += 1;
        return jsonResponse(memoryPayload());
      },
    ),
    (error) => {
      assert.equal(error?.name, "ZodError");
      return true;
    },
  );
  assert.equal(calls, 0);
});

test("memory.search forwards the exact project key to the bridge", async () => {
  let requestBody = null;
  await executeMemoryTool(
    "memory.search",
    { namespace: "real_life", projectKey: PROJECT_KEY, query: "current state" },
    CONFIG,
    async (_url, init) => {
      requestBody = JSON.parse(init.body);
      return jsonResponse(memoryPayload());
    },
  );
  assert.equal(requestBody.project_key, PROJECT_KEY);
  assert.equal(requestBody.projectKey, undefined);
});

test("memory.canonicalContext preserves the exact project scope", async () => {
  let requestBody = null;
  await executeMemoryTool(
    "memory.canonicalContext",
    { namespace: "real_life", projectKey: PROJECT_KEY, query: "current state" },
    CONFIG,
    async (_url, init) => {
      requestBody = JSON.parse(init.body);
      return jsonResponse(memoryPayload());
    },
  );
  assert.equal(requestBody.project_key, PROJECT_KEY);
});

test("durable plan hydration fails closed before Memory when project scope is absent", async () => {
  let calls = 0;
  const provider = new PandoraPlanMemoryContextProvider({
    baseUrl: "https://memory.example.test",
    fetchFn: async () => {
      calls += 1;
      return jsonResponse(memoryPayload());
    },
    now: () => new Date("2026-09-01T04:30:00.000Z"),
  });
  const result = await provider.hydrate("o".repeat(64), {
    tool: "github.get-file",
    args: { owner: "example", repo: "example" },
  });
  assert.equal(result.envelope.status, "unavailable");
  assert.equal(result.envelope.failure.status, 400);
  assert.equal(calls, 0);
});

test("durable plan hydration forwards explicit project scope", async () => {
  let requestBody = null;
  const provider = new PandoraPlanMemoryContextProvider({
    baseUrl: "https://memory.example.test",
    fetchFn: async (_url, init) => {
      requestBody = JSON.parse(init.body);
      return jsonResponse(memoryPayload());
    },
    now: () => new Date("2026-09-01T04:30:00.000Z"),
  });
  const result = await provider.hydrate("o".repeat(64), {
    tool: "supabase.get-project",
    args: { projectKey: PROJECT_KEY },
  });
  assert.equal(result.envelope.status, "empty");
  assert.equal(requestBody.project_key, PROJECT_KEY);
});



test("canonical Memory health probe forwards the exact project key", async () => {
  let searchBody = null;
  const probe = createCanonicalMemoryHealthProbe(
    { VERCEL_OIDC_TOKEN: "o".repeat(64) },
    async (url, init = {}) => {
      const pathname = new URL(url).pathname;
      if (pathname === "/api/projectos/health") {
        return jsonResponse({
          ok: true,
          project: "pandora-memory-engine",
          status: "projectos-connected",
          context_pack_hydration: "active",
          daily_context_pack: "scheduled_15m",
          post_task_learning: "review_gated",
        });
      }
      if (pathname === "/api/projectos/memory/search") {
        searchBody = JSON.parse(init.body);
        return jsonResponse(memoryPayload());
      }
      throw new Error(`Unexpected Memory probe path: ${pathname}`);
    },
    () => Date.parse("2026-09-01T05:30:00.000Z"),
  );

  const snapshot = await probe();
  assert.equal(snapshot.status, "healthy");
  assert.equal(snapshot.searchVerified, true);
  assert.equal(searchBody.project_key, PROJECT_KEY);
  assert.equal(searchBody.projectKey, undefined);
});
