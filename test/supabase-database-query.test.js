"use strict";

const test = require("node:test");
const assert = require("node:assert/strict");
const { createHash } = require("node:crypto");

const { SupabaseMCPServer } = require("../dist/tools/supabase.js");

const PROJECT_REF = "ivmvufhcsezyhczzondn";
const SQL = "select project_key from public.pandora_projects order by project_key";
const BODY = { query: SQL, read_only: true };
const BODY_SHA256 = createHash("sha256")
  .update(JSON.stringify(BODY), "utf8")
  .digest("hex");
const CONFIRMATION =
  `DATABASE QUERY ${PROJECT_REF} READ_ONLY true BODY_SHA256 ${BODY_SHA256}`;

function server(fetchFn) {
  return new SupabaseMCPServer({
    accounts: [{
      id: "battle-realmatch",
      label: "test",
      authMode: "pat",
      token: "vault-backed-test-token",
      allowMutations: true,
      allowedOrganizationSlugs: [],
      allowedProjectRefs: [PROJECT_REF],
    }],
    timeoutMs: 5000,
    maxResponseBytes: 100000,
  }, fetchFn);
}

test("governed Supabase database query forwards the exact hash-bound body", async () => {
  let request;
  const client = server(async (url, init) => {
    request = { url, init };
    return new Response(JSON.stringify([{ project_key: "mcpmaster-pandoras-box" }]), {
      status: 200,
      headers: { "content-type": "application/json" },
    });
  });

  const result = await client.queryDatabase(
    "battle-realmatch",
    PROJECT_REF,
    SQL,
    true,
    BODY_SHA256,
    CONFIRMATION,
  );

  assert.deepEqual(result, [{ project_key: "mcpmaster-pandoras-box" }]);
  assert.equal(
    request.url,
    `https://api.supabase.com/v1/projects/${PROJECT_REF}/database/query`,
  );
  assert.equal(request.init.method, "POST");
  assert.equal(request.init.body, JSON.stringify(BODY));
  assert.equal(request.init.redirect, "error");
  assert.match(request.init.headers.Authorization, /^Bearer /);
});

test("governed Supabase database query rejects a mismatched body hash before dispatch", async () => {
  let calls = 0;
  const client = server(async () => {
    calls += 1;
    throw new Error("provider must not be called");
  });

  await assert.rejects(
    client.queryDatabase(
      "battle-realmatch",
      PROJECT_REF,
      SQL,
      true,
      "0".repeat(64),
      CONFIRMATION,
    ),
    /bodySha256 must exactly equal/,
  );
  assert.equal(calls, 0);
});

test("governed Supabase database query remains project allowlist bound", async () => {
  let calls = 0;
  const client = server(async () => {
    calls += 1;
    throw new Error("provider must not be called");
  });

  await assert.rejects(
    client.queryDatabase(
      "battle-realmatch",
      "aaaaaaaaaaaaaaaaaaaa",
      SQL,
      true,
      BODY_SHA256,
      CONFIRMATION,
    ),
    /not allowed to access project/,
  );
  assert.equal(calls, 0);
});
