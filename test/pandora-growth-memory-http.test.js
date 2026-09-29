"use strict";

const assert = require("node:assert/strict");
const express = require("express");
const http = require("node:http");
const test = require("node:test");
const { createPandoraGrowthMemoryRouter } = require("../src/pandora-growth-memory-http.js");

const ORG = "2270b266-59da-4c39-bfd9-9f8d08352af0";
const SOURCE_PROJECT = "ee282126-3f61-4058-8c92-2fedbfcecf1f";
const MEMORY_PROJECT = "7c686cbd-d968-49d5-86cc-918f5e777bd2";
const USER = "11111111-1111-4111-8111-111111111111";
const RECORD = "22222222-2222-4222-8222-222222222222";
const REVIEW = "33333333-3333-4333-8333-333333333333";
const VERSION = RECORD + "@" + "a".repeat(64);
const TOKEN = "user-jwt-token-with-enough-length-12345";

function response(body, status = 200) {
  return new Response(JSON.stringify(body), {
    status,
    headers: { "content-type": "application/json" },
  });
}

function memoryPayload() {
  return {
    ok: true,
    action: "growth_context",
    project_id: MEMORY_PROJECT,
    project_key: "mcpmaster-pandoras-box",
    data: {
      schemaVersion: "growth.approved-memory-context.v1",
      status: "available",
      namespace: "real_life",
      querySha256: "b".repeat(64),
      contextSha256: "c".repeat(64),
      asOf: "2026-09-30T00:00:00.000Z",
      records: [{
        memoryRecordId: RECORD,
        memoryVersionId: VERSION,
        reviewItemId: REVIEW,
        recordSha256: "d".repeat(64),
        status: "approved_current",
        recordType: "failure_lesson",
        title: "Creative fatigue lesson",
        summary: "Refresh creative only after verified performance decay.",
        evidenceRefs: ["experiment:verified:1"],
        authorizationEffect: "none",
      }],
      invariants: {
        approvedCurrentOnly: true,
        pendingExcluded: true,
        rejectedExcluded: true,
        revokedExcluded: true,
        supersededExcluded: true,
        retrievalDoesNotGrantExecutionAuthority: true,
        canAuthorizeSpend: false,
        canMutateCampaigns: false,
        canPublish: false,
        operationsRoomRequired: false,
      },
    },
  };
}

async function withApp(fetchFn, fn, role = "owner") {
  const app = express();
  app.use(createPandoraGrowthMemoryRouter({
    environment: {
      SUPABASE_URL: "https://primary.supabase.test",
      SUPABASE_SERVICE_ROLE_KEY: "service-role-fixture",
    },
    fetchFn,
    resolveOidc: async () => "vercel-workload-oidc-fixture",
  }));
  const server = http.createServer(app);
  await new Promise((resolve) => server.listen(0, "127.0.0.1", resolve));
  try {
    const address = server.address();
    await fn("http://127.0.0.1:" + address.port, role);
  } finally {
    await new Promise((resolve) => server.close(resolve));
  }
}

function fixture(calls, role = "owner") {
  return async (url, init = {}) => {
    calls.push({ url: String(url), init });
    const value = String(url);
    if (value.endsWith("/auth/v1/user")) return response({ id: USER });
    if (value.includes("/rest/v1/memberships?")) {
      return response([{ organization_id: ORG, role, status: "active" }]);
    }
    if (value.includes("/rest/v1/pandora_tracking_tenants?")) {
      return response([{
        id: "44444444-4444-4444-8444-444444444444",
        organization_id: ORG,
        project_id: SOURCE_PROJECT,
        workspace_key: "pandora-platform",
        status: "active",
      }]);
    }
    if (value.includes("pandora-memory-bridge")) return response(memoryPayload());
    if (value.includes("/rpc/pandora_growth_record_memory_retrieval_receipt_v1")) {
      return response({ ok: true, status: "approved_current" });
    }
    return response({ error: "unexpected" }, 500);
  };
}

test("owner gets approved-current Memory and OIDC never leaves the server call", async () => {
  const calls = [];
  await withApp(fixture(calls), async (base) => {
    const result = await fetch(base + "/api/growth/memory-context", {
      method: "POST",
      headers: {
        authorization: "Bearer " + TOKEN,
        "x-organization-id": ORG,
        "content-type": "application/json",
      },
      body: JSON.stringify({ terms: ["facebook", "creative", "performance"] }),
    });
    assert.equal(result.status, 200);
    const body = await result.json();
    assert.equal(body.ok, true);
    assert.equal(body.records.length, 1);
    assert.equal(body.records[0].reviewItemId, REVIEW);
    assert.equal(body.invariants.canAuthorizeSpend, false);
    assert.equal(body.invariants.operationsRoomRequired, false);
    assert.doesNotMatch(JSON.stringify(body), /vercel-workload-oidc-fixture|service-role-fixture|user-jwt-token/);
  });
  const memoryCall = calls.find((call) => call.url.includes("pandora-memory-bridge"));
  assert.equal(memoryCall.init.headers["x-pandora-vercel-oidc"], "vercel-workload-oidc-fixture");
  const receiptCall = calls.find((call) => call.url.includes("pandora_growth_record_memory_retrieval_receipt_v1"));
  assert.ok(receiptCall);
  const receipt = JSON.parse(receiptCall.init.body);
  assert.equal(receipt.p_project_id, SOURCE_PROJECT);
  assert.equal(receipt.p_memory_record_id, RECORD);
  assert.equal(receipt.p_review_item_id, REVIEW);
});

test("non-owner cannot retrieve growth Memory", async () => {
  const calls = [];
  await withApp(fixture(calls, "staff"), async (base) => {
    const result = await fetch(base + "/api/growth/memory-context", {
      method: "POST",
      headers: {
        authorization: "Bearer " + TOKEN,
        "x-organization-id": ORG,
        "content-type": "application/json",
      },
      body: JSON.stringify({ terms: ["facebook"] }),
    });
    assert.equal(result.status, 403);
    const body = await result.json();
    assert.equal(body.error, "owner_admin_required");
  });
  assert.equal(calls.some((call) => call.url.includes("pandora-memory-bridge")), false);
});

test("caller cannot choose project, principal, namespace, or authority", async () => {
  const calls = [];
  await withApp(fixture(calls), async (base) => {
    const result = await fetch(base + "/api/growth/memory-context", {
      method: "POST",
      headers: {
        authorization: "Bearer " + TOKEN,
        "x-organization-id": ORG,
        "content-type": "application/json",
      },
      body: JSON.stringify({ terms: ["facebook"], project_id: "attacker" }),
    });
    assert.equal(result.status, 400);
    assert.equal((await result.json()).error, "unexpected_field");
  });
  assert.equal(calls.length, 0);
});
