"use strict";

const test = require("node:test");
const assert = require("node:assert/strict");
const { createHash } = require("node:crypto");

const {
  SupabaseMCPServer,
  executeSupabaseTool,
  supabaseTools,
} = require("../src/tools/supabase.js");
const {
  expectedConfirmation,
  assertManifestConfirmation,
  getToolManifest,
} = require("../src/runtime/tool-manifest.js");

const PROJECT_REF = "ivmvufhcsezyhczzondn";
const SQL = "select 1 as ok";
const PARAMETERS = [];
const READ_ONLY = false;

function queryArgs(overrides = {}) {
  const body = {
    query: overrides.sql ?? SQL,
    parameters: overrides.parameters ?? PARAMETERS,
    read_only: overrides.readOnly ?? READ_ONLY,
  };
  const bodySha256 = createHash("sha256")
    .update(JSON.stringify(body), "utf8")
    .digest("hex");
  const args = {
    accountId: "memory-primary",
    projectRef: PROJECT_REF,
    sql: body.query,
    parameters: body.parameters,
    readOnly: body.read_only,
    bodySha256,
  };
  return {
    ...args,
    confirmation: expectedConfirmation("supabase.database-query", args),
    ...overrides,
  };
}

function configuration(overrides = {}) {
  return {
    accounts: [{
      id: "memory-primary",
      label: "Memory",
      authMode: "pat",
      token: "vault-backed-test-token",
      allowMutations: true,
      allowedOrganizationSlugs: [],
      allowedProjectRefs: [PROJECT_REF],
      ...overrides,
    }],
    timeoutMs: 5000,
    maxResponseBytes: 100000,
  };
}

test("database query is registered as an approval-gated Supabase project mutation", () => {
  assert.ok(supabaseTools["supabase.database-query"]);
  const manifest = getToolManifest("supabase.database-query");
  assert.equal(manifest.provider, "supabase");
  assert.equal(manifest.risk, "write");
  assert.equal(manifest.mutation, true);
  assert.equal(manifest.scope, "project");
  assert.deepEqual(manifest.requiredProviderScopes, ["projects:read", "projects:write"]);
});

test("database query confirmation is bound to the exact body hash", () => {
  const args = queryArgs();
  assert.equal(
    args.confirmation,
    `POST DATABASE ${PROJECT_REF} READ_ONLY false BODY_SHA256 ${args.bodySha256}`,
  );
  assert.doesNotThrow(() => assertManifestConfirmation("supabase.database-query", args));
  assert.throws(
    () => assertManifestConfirmation("supabase.database-query", {
      ...args,
      sql: "select 2 as changed",
    }),
    /could not be validated/,
  );
});

test("database query dispatches the exact bounded body to the exact allowlisted project", async () => {
  let calls = 0;
  const args = queryArgs();
  const result = await executeSupabaseTool(
    "supabase.database-query",
    args,
    configuration(),
    async (url, options) => {
      calls += 1;
      assert.equal(
        url,
        `https://api.supabase.com/v1/projects/${PROJECT_REF}/database/query`,
      );
      assert.equal(options.method, "POST");
      assert.equal(options.redirect, "error");
      assert.equal(options.headers.Authorization, "Bearer vault-backed-test-token");
      assert.deepEqual(
        JSON.parse(options.body),
        { query: SQL, parameters: PARAMETERS, read_only: false },
      );
      return new Response(JSON.stringify([{ ok: true }]), {
        status: 200,
        headers: { "content-type": "application/json" },
      });
    },
  );
  assert.equal(calls, 1);
  assert.equal(result.accountId, "memory-primary");
  assert.equal(result.projectRef, PROJECT_REF);
  assert.equal(result.readOnly, false);
  assert.equal(result.bodySha256, args.bodySha256);
  assert.deepEqual(result.result, [{ ok: true }]);
  assert.doesNotMatch(JSON.stringify(result), /vault-backed-test-token/);
});

test("database query rejects a body-hash mismatch before provider dispatch", async () => {
  let calls = 0;
  const server = new SupabaseMCPServer(configuration(), async () => {
    calls += 1;
    throw new Error("must not dispatch");
  });
  const args = queryArgs();
  await assert.rejects(
    () => server.databaseQuery(
      args.accountId,
      args.projectRef,
      args.sql,
      args.parameters,
      args.readOnly,
      "0".repeat(64),
      args.confirmation,
    ),
    /body hash mismatch/,
  );
  assert.equal(calls, 0);
});

test("database query rejects accounts with mutations disabled", async () => {
  const args = queryArgs();
  const server = new SupabaseMCPServer(configuration({ allowMutations: false }));
  await assert.rejects(
    () => server.databaseQuery(
      args.accountId,
      args.projectRef,
      args.sql,
      args.parameters,
      args.readOnly,
      args.bodySha256,
      args.confirmation,
    ),
    /Mutations are disabled/,
  );
});
