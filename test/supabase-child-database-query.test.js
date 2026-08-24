"use strict";

const { createHash, createHmac } = require("node:crypto");
const test = require("node:test");
const assert = require("node:assert/strict");

const {
  executeSupabaseProviderApiTool,
  supabaseProviderApiTools,
} = require("../dist/tools/provider-api.js");
const {
  expectedConfirmation,
  getToolManifest,
  highImpactReason,
} = require("../dist/runtime/tool-manifest.js");
const { executeTool, toolRegistry } = require("../dist/runtime/tool-catalog.js");
const { executionPayloadHash } = require("../dist/http-app.js");

const QUERY_TOOL = "supabase.write-child-database-query";
const DELETE_TOOL = "supabase.delete-child-branch";
const RECONCILE_TOOL = "supabase.read-child-deletion-reconciliation";
const ACCOUNT_ID = "battle-realmatch";
const ORGANIZATION = "lqvpjqbgfodmtswxizwf";
const PARENT = "qjarspsifemjubmzsdgy";
const OTHER_PARENT = "cccccccccccccccccccc";
const CHILD = "aaaaaaaaaaaaaaaaaaaa";
const SIBLING = "bbbbbbbbbbbbbbbbbbbb";
const BRANCH_ID = "11111111-1111-4111-8111-111111111111";
const OTHER_BRANCH_ID = "22222222-2222-4222-8222-222222222222";
const LOGICAL_SCOPES = ["projects:read", "projects:write"];
const TEST_PROVIDER_TOKEN = "test-provider-token";

function configuration(overrides = {}) {
  return {
    accounts: [{
      id: ACCOUNT_ID,
      token: TEST_PROVIDER_TOKEN,
      allowMutations: true,
      allowedOrganizationSlugs: [],
      allowedProjectRefs: [PARENT],
      grantedScopes: LOGICAL_SCOPES,
      ...overrides,
    }],
    timeoutMs: 1000,
    maxResponseBytes: 2000000,
  };
}

function queryProviderBody(input) {
  return { query: input.sql, parameters: input.parameters, read_only: false };
}

function sha256(value) {
  return createHash("sha256").update(value, "utf8").digest("hex");
}

function queryBodySha256(input) {
  return sha256(JSON.stringify(queryProviderBody(input)));
}

function queryConfirmation(input) {
  return `POST CHILD DATABASE ${input.parentProjectRef}:${input.branchId}:${input.childProjectRef} BODY_SHA256 ${input.bodySha256}`;
}

function validQueryArgs(overrides = {}) {
  const value = {
    accountId: ACCOUNT_ID,
    parentProjectRef: PARENT,
    branchId: BRANCH_ID,
    childProjectRef: CHILD,
    sql: "select $1::integer as governed_child_probe",
    parameters: [1],
    ...overrides,
  };
  if (!Object.prototype.hasOwnProperty.call(overrides, "bodySha256")) {
    value.bodySha256 = queryBodySha256(value);
  }
  if (!Object.prototype.hasOwnProperty.call(overrides, "confirmation")) {
    value.confirmation = queryConfirmation(value);
  }
  return value;
}

function deleteConfirmation(input) {
  return `DELETE CHILD BRANCH ${input.parentProjectRef}:${input.branchId}:${input.childProjectRef}`;
}

function validDeleteArgs(overrides = {}) {
  const value = {
    accountId: ACCOUNT_ID,
    parentProjectRef: PARENT,
    branchId: BRANCH_ID,
    childProjectRef: CHILD,
    ...overrides,
  };
  if (!Object.prototype.hasOwnProperty.call(overrides, "confirmation")) {
    value.confirmation = deleteConfirmation(value);
  }
  return value;
}

function reconciliationProof(input) {
  const canonical = JSON.stringify({
    schemaVersion: "supabase-child-deletion-reconciliation-v1",
    accountId: input.accountId,
    parentProjectRef: input.parentProjectRef,
    branchId: input.branchId,
    childProjectRef: input.childProjectRef,
    parentOrganizationSlug: input.expectedParentOrganizationSlug,
    parentStatus: input.expectedParentStatus,
  });
  return createHmac("sha256", TEST_PROVIDER_TOKEN).update(canonical, "utf8").digest("hex");
}

function validReconciliationArgs(overrides = {}) {
  const value = {
    accountId: ACCOUNT_ID,
    parentProjectRef: PARENT,
    branchId: BRANCH_ID,
    childProjectRef: CHILD,
    expectedParentOrganizationSlug: ORGANIZATION,
    expectedParentStatus: "ACTIVE_HEALTHY",
    ...overrides,
  };
  if (!Object.prototype.hasOwnProperty.call(overrides, "reconciliationProof")) {
    value.reconciliationProof = reconciliationProof(value);
  }
  return value;
}

function projectRecord(ref, organization = ORGANIZATION, status = "ACTIVE_HEALTHY") {
  return { ref, organization_slug: organization, status };
}

function branchRecord(overrides = {}) {
  return {
    id: BRANCH_ID,
    name: "disposable-child-rehearsal",
    project_ref: CHILD,
    parent_project_ref: PARENT,
    is_default: false,
    persistent: false,
    with_data: false,
    status: "FUNCTIONS_DEPLOYED",
    preview_project_status: "ACTIVE_HEALTHY",
    ...overrides,
  };
}

function jsonResponse(body, status = 200, headers = {}) {
  return new Response(JSON.stringify(body), {
    status,
    headers: { "content-type": "application/json", ...headers },
  });
}

test("manifests, schemas, confirmations, body bytes, and plan payloads bind both child routes", () => {
  for (const [tool, risk, confirmationKind] of [
    [QUERY_TOOL, "write", "supabase-child-database-query"],
    [DELETE_TOOL, "destructive", "supabase-child-branch-delete"],
  ]) {
    const manifest = getToolManifest(tool);
    assert.deepEqual({
      provider: manifest.provider,
      risk: manifest.risk,
      mutation: manifest.mutation,
      scope: manifest.scope,
      requiredProviderScopes: manifest.requiredProviderScopes,
      confirmationKind: manifest.confirmationKind,
      highImpactCapable: manifest.highImpactCapable,
    }, {
      provider: "supabase",
      risk,
      mutation: true,
      scope: "branch",
      requiredProviderScopes: LOGICAL_SCOPES,
      confirmationKind,
      highImpactCapable: undefined,
    });
    assert.ok(toolRegistry[tool]);
    assert.equal(supabaseProviderApiTools[tool].parameters.additionalProperties, false);
  }
  const reconcileManifest = getToolManifest(RECONCILE_TOOL);
  assert.deepEqual({
    provider: reconcileManifest.provider,
    risk: reconcileManifest.risk,
    mutation: reconcileManifest.mutation,
    scope: reconcileManifest.scope,
    requiredProviderScopes: reconcileManifest.requiredProviderScopes,
    confirmationKind: reconcileManifest.confirmationKind,
  }, {
    provider: "supabase",
    risk: "read",
    mutation: false,
    scope: "branch",
    requiredProviderScopes: ["projects:read"],
    confirmationKind: undefined,
  });
  assert.ok(toolRegistry[RECONCILE_TOOL]);
  assert.equal(supabaseProviderApiTools[RECONCILE_TOOL].parameters.additionalProperties, false);
  assert.deepEqual(supabaseProviderApiTools[QUERY_TOOL].parameters.required, [
    "accountId", "parentProjectRef", "branchId", "childProjectRef",
    "sql", "parameters", "bodySha256", "confirmation",
  ]);
  for (const forbidden of ["method", "pathSegments", "query", "read_only", "body"]) {
    assert.equal(supabaseProviderApiTools[QUERY_TOOL].parameters.properties[forbidden], undefined);
  }

  const queryInput = validQueryArgs();
  assert.equal(queryInput.bodySha256, queryBodySha256(queryInput));
  assert.equal(expectedConfirmation(QUERY_TOOL, queryInput), queryConfirmation(queryInput));
  assert.equal(
    expectedConfirmation(QUERY_TOOL, { ...queryInput, bodySha256: "0".repeat(64) }),
    undefined,
  );
  const deleteInput = validDeleteArgs();
  assert.equal(expectedConfirmation(DELETE_TOOL, deleteInput), deleteConfirmation(deleteInput));
  assert.equal(highImpactReason(QUERY_TOOL, queryInput), undefined);
  assert.equal(highImpactReason(DELETE_TOOL, deleteInput), undefined);

  const baseHash = executionPayloadHash(QUERY_TOOL, queryInput);
  for (const mutation of [
    { parentProjectRef: OTHER_PARENT },
    { branchId: OTHER_BRANCH_ID },
    { childProjectRef: SIBLING },
    { sql: "select 2" },
    { parameters: [2] },
  ]) {
    assert.notEqual(executionPayloadHash(QUERY_TOOL, validQueryArgs(mutation)), baseHash);
  }
  assert.notEqual(
    executionPayloadHash(DELETE_TOOL, validDeleteArgs({ branchId: OTHER_BRANCH_ID })),
    executionPayloadHash(DELETE_TOOL, deleteInput),
  );
});

test("ProjectOS rejects either missing logical scope before provider I/O", async () => {
  const originalFetch = globalThis.fetch;
  let calls = 0;
  globalThis.fetch = async () => {
    calls += 1;
    return jsonResponse({});
  };
  try {
    for (const tool of [QUERY_TOOL, DELETE_TOOL]) {
      const args = tool === QUERY_TOOL ? validQueryArgs() : validDeleteArgs();
      for (const missing of LOGICAL_SCOPES) {
        await assert.rejects(
          executeTool(tool, args, {
            supabase: configuration({
              grantedScopes: LOGICAL_SCOPES.filter((scope) => scope !== missing),
            }),
          }),
          new RegExp(`missing required scope.*${missing}`),
        );
        assert.equal(calls, 0, `${tool}: ${missing}`);
      }
    }
  } finally {
    globalThis.fetch = originalFetch;
  }
});

test("ProjectOS dispatch accepts the live coarse logical scopes while provider permission stays downstream", async () => {
  const originalFetch = globalThis.fetch;
  let calls = 0;
  globalThis.fetch = async (_url, init) => {
    calls += 1;
    if (init.method === "POST") return jsonResponse({ result: [] }, 201);
    if (calls === 1 || calls === 5) return jsonResponse(projectRecord(PARENT));
    if (calls === 2 || calls === 6) return jsonResponse([branchRecord()]);
    return jsonResponse(projectRecord(CHILD));
  };
  try {
    const result = await executeTool(QUERY_TOOL, validQueryArgs(), {
      supabase: configuration({
        grantedScopes: ["organizations:read", "organizations:write", "projects:read", "projects:write"],
      }),
    });
    assert.deepEqual(result, { result: [] });
    assert.equal(calls, 7);
  } finally {
    globalThis.fetch = originalFetch;
  }
});

test("exact parent, UUID branch, child identity, and body hash permit only the hardcoded query route", async () => {
  const calls = [];
  const input = validQueryArgs();
  const result = await executeSupabaseProviderApiTool(
    QUERY_TOOL,
    input,
    configuration(),
    async (url, init) => {
      calls.push({ url, method: init.method, body: init.body });
      switch (calls.length) {
        case 1:
        case 5:
          assert.equal(url, `https://api.supabase.com/v1/projects/${PARENT}`);
          return jsonResponse(projectRecord(PARENT));
        case 2:
        case 6:
          assert.equal(url, `https://api.supabase.com/v1/projects/${PARENT}/branches`);
          return jsonResponse([branchRecord()]);
        case 3:
        case 7:
          assert.equal(url, `https://api.supabase.com/v1/projects/${CHILD}`);
          return jsonResponse(projectRecord(CHILD));
        case 4:
          assert.equal(url, `https://api.supabase.com/v1/projects/${CHILD}/database/query`);
          assert.equal(init.method, "POST");
          assert.deepEqual(JSON.parse(init.body), queryProviderBody(input));
          assert.equal(sha256(init.body), input.bodySha256);
          return jsonResponse({ result: [{ governed_child_probe: 1 }] }, 201);
        default:
          throw new Error("unexpected provider request");
      }
    },
  );
  assert.deepEqual(result, { result: [{ governed_child_probe: 1 }] });
  assert.equal(calls.length, 7);
  assert.equal(calls.filter((call) => call.method === "POST").length, 1);
});

test("sibling, swapped, name-only, conflicting, duplicate, and parent drift fail before query dispatch", async () => {
  const fixtures = [
    { name: "same-org sibling", args: validQueryArgs(), branches: [branchRecord({ project_ref: SIBLING })] },
    { name: "swapped child", args: validQueryArgs({ childProjectRef: SIBLING }), branches: [branchRecord()] },
    { name: "name-only UUID", args: validQueryArgs(), branches: [branchRecord({ id: OTHER_BRANCH_ID, name: BRANCH_ID })] },
    { name: "conflicting provider ref", args: validQueryArgs(), branches: [branchRecord({ ref: SIBLING })] },
    { name: "duplicate exact record", args: validQueryArgs(), branches: [branchRecord(), branchRecord()] },
    {
      name: "exact plus ID collision",
      args: validQueryArgs(),
      branches: [branchRecord(), branchRecord({ id: BRANCH_ID, project_ref: SIBLING, ref: SIBLING })],
    },
    {
      name: "exact plus project-ref collision",
      args: validQueryArgs(),
      branches: [branchRecord(), branchRecord({ id: OTHER_BRANCH_ID, project_ref: CHILD, ref: SIBLING })],
    },
    {
      name: "exact plus ref collision",
      args: validQueryArgs(),
      branches: [branchRecord(), branchRecord({ id: OTHER_BRANCH_ID, project_ref: SIBLING, ref: CHILD })],
    },
    {
      name: "wrong parent binding",
      args: validQueryArgs({ parentProjectRef: OTHER_PARENT }),
      config: configuration({ allowedProjectRefs: [PARENT, OTHER_PARENT] }),
      parent: projectRecord(OTHER_PARENT),
      branches: [branchRecord()],
    },
    { name: "parent ref mismatch", args: validQueryArgs(), parent: projectRecord(OTHER_PARENT), expectedCalls: 1 },
  ];
  for (const fixture of fixtures) {
    let calls = 0;
    let queryCalls = 0;
    await assert.rejects(
      () => executeSupabaseProviderApiTool(
        QUERY_TOOL,
        fixture.args,
        fixture.config || configuration(),
        async (_url, init) => {
          calls += 1;
          if (init.method === "POST") queryCalls += 1;
          if (calls === 1) return jsonResponse(fixture.parent || projectRecord(fixture.args.parentProjectRef));
          return jsonResponse(fixture.branches || []);
        },
      ),
      fixture.expectedCalls === 1 ? /identity drifted/ : /not uniquely bound.*preflight/,
      fixture.name,
    );
    assert.equal(calls, fixture.expectedCalls || 2, fixture.name);
    assert.equal(queryCalls, 0, fixture.name);
  }
});

test("parent organization is captured even with an empty org allowlist and child must exactly agree", async () => {
  for (const fixture of [
    { name: "child ref disagreement", child: projectRecord(SIBLING) },
    { name: "child organization disagreement", child: projectRecord(CHILD, "wrong-org") },
    { name: "stale branch record with unhealthy child", child: projectRecord(CHILD, ORGANIZATION, "INACTIVE") },
  ]) {
    let calls = 0;
    await assert.rejects(
      () => executeSupabaseProviderApiTool(
        QUERY_TOOL,
        validQueryArgs(),
        configuration({ allowedOrganizationSlugs: [] }),
        async () => {
          calls += 1;
          if (calls === 1) return jsonResponse(projectRecord(PARENT));
          if (calls === 2) return jsonResponse([branchRecord()]);
          return jsonResponse(fixture.child);
        },
      ),
      /Child project.*(?:identity drifted|not ACTIVE_HEALTHY).*preflight/,
      fixture.name,
    );
    assert.equal(calls, 3, fixture.name);
  }

  let calls = 0;
  await assert.rejects(
    () => executeSupabaseProviderApiTool(
      QUERY_TOOL,
      validQueryArgs(),
      configuration({ allowedOrganizationSlugs: ["different-org"] }),
      async () => {
        calls += 1;
        return jsonResponse(projectRecord(PARENT));
      },
    ),
    /Allowed parent project.*identity drifted/,
  );
  assert.equal(calls, 1);

  calls = 0;
  await assert.rejects(
    () => executeSupabaseProviderApiTool(
      QUERY_TOOL,
      validQueryArgs(),
      configuration(),
      async () => {
        calls += 1;
        return jsonResponse(projectRecord(PARENT, ORGANIZATION, "INACTIVE"));
      },
    ),
    /parent project.*not ACTIVE_HEALTHY.*preflight/i,
  );
  assert.equal(calls, 1);

  calls = 0;
  await assert.rejects(
    () => executeSupabaseProviderApiTool(
      QUERY_TOOL,
      validQueryArgs(),
      configuration({
        allowedProjectRefs: [],
        allowedOrganizationSlugs: [ORGANIZATION],
      }),
      async () => {
        calls += 1;
        return jsonResponse(projectRecord(PARENT));
      },
    ),
    /not statically allowed to access parent project/,
  );
  assert.equal(calls, 0);
});

test("only an exact healthy disposable nondefault branch may authorize a query", async () => {
  const drifts = [
    { name: "default branch", patch: { is_default: true } },
    { name: "missing default marker", patch: { is_default: undefined } },
    { name: "mismatched exact ref", patch: { ref: SIBLING } },
    { name: "persistent branch", patch: { persistent: true } },
    { name: "missing persistence marker", patch: { persistent: undefined } },
    { name: "data-bearing branch", patch: { with_data: true } },
    { name: "missing data marker", patch: { with_data: undefined } },
    { name: "deployment incomplete", patch: { status: "MIGRATIONS_PENDING" } },
    { name: "removing", patch: { status: "REMOVING" } },
    { name: "unhealthy", patch: { preview_project_status: "COMING_UP" } },
    { name: "inactive", patch: { preview_project_status: "INACTIVE" } },
    { name: "deletion scheduled", patch: { deletion_scheduled_at: "2026-08-24T07:00:00Z" } },
  ];
  for (const drift of drifts) {
    let calls = 0;
    await assert.rejects(
      () => executeSupabaseProviderApiTool(
        QUERY_TOOL,
        validQueryArgs(),
        configuration(),
        async () => {
          calls += 1;
          return calls === 1
            ? jsonResponse(projectRecord(PARENT))
            : jsonResponse([branchRecord(drift.patch)]);
        },
      ),
      /not uniquely bound.*preflight/,
      drift.name,
    );
    assert.equal(calls, 2, drift.name);
  }
});

test("caller endpoint drift, ambiguous IDs, malformed parameters, hash drift, and unknown keys fail without I/O", async () => {
  const malformed = [
    { method: "POST" },
    { pathSegments: ["database", "query"] },
    { query: {} },
    { read_only: false },
    { body: queryProviderBody(validQueryArgs()) },
    { branchId: CHILD },
    { branchId: "AAAAAAAA-AAAA-4AAA-8AAA-AAAAAAAAAAAA" },
    { sql: "" },
    { sql: "é".repeat(120001) },
    { parameters: Array.from({ length: 101 }, () => null) },
    { parameters: ["x".repeat(65537)] },
    { parameters: [Number.POSITIVE_INFINITY] },
    { bodySha256: "0".repeat(64) },
    { confirmation: "POST CHILD DATABASE wrong" },
    { unexpected: true },
  ];
  for (const mutation of malformed) {
    let calls = 0;
    await assert.rejects(
      () => executeSupabaseProviderApiTool(
        QUERY_TOOL,
        validQueryArgs(mutation),
        configuration(),
        async () => {
          calls += 1;
          return jsonResponse({});
        },
      ),
    );
    assert.equal(calls, 0, JSON.stringify(mutation).slice(0, 200));
  }

  let sameRefCalls = 0;
  await assert.rejects(
    () => executeSupabaseProviderApiTool(
      QUERY_TOOL,
      validQueryArgs({ childProjectRef: PARENT }),
      configuration(),
      async () => {
        sameRefCalls += 1;
        return jsonResponse({});
      },
    ),
    /must differ from its allowlisted parent/,
  );
  assert.equal(sameRefCalls, 0);
});

test("post-query parent, membership, or child drift fails after one POST without retry", async () => {
  const fixtures = [
    { name: "parent drift", postParent: projectRecord(OTHER_PARENT) },
    { name: "parent organization snapshot drift", postParent: projectRecord(PARENT, "changed-org") },
    { name: "parent status snapshot drift", postParent: projectRecord(PARENT, ORGANIZATION, "PAUSED") },
    { name: "branch disappeared", postParent: projectRecord(PARENT), postBranches: [] },
    {
      name: "child org drift",
      postParent: projectRecord(PARENT),
      postBranches: [branchRecord()],
      postChild: projectRecord(CHILD, "wrong-org"),
    },
    {
      name: "child status drift",
      postParent: projectRecord(PARENT),
      postBranches: [branchRecord()],
      postChild: projectRecord(CHILD, ORGANIZATION, "COMING_UP"),
    },
  ];
  for (const fixture of fixtures) {
    let calls = 0;
    let posts = 0;
    await assert.rejects(
      () => executeSupabaseProviderApiTool(
        QUERY_TOOL,
        validQueryArgs(),
        configuration(),
        async (_url, init) => {
          calls += 1;
          if (init.method === "POST") posts += 1;
          if (calls === 1) return jsonResponse(projectRecord(PARENT));
          if (calls === 2) return jsonResponse([branchRecord()]);
          if (calls === 3) return jsonResponse(projectRecord(CHILD));
          if (calls === 4) return jsonResponse({ result: [] }, 201);
          if (calls === 5) return jsonResponse(fixture.postParent);
          if (calls === 6) return jsonResponse(fixture.postBranches || []);
          return jsonResponse(fixture.postChild);
        },
      ),
      /identity drifted|changed after its bound snapshot|not ACTIVE_HEALTHY|not uniquely bound.*postflight/,
      fixture.name,
    );
    assert.equal(posts, 1, fixture.name);
    assert.ok(calls >= 5 && calls <= 7, fixture.name);
  }
});

test("query responses are capped at one million bytes and truncation never retries POST", async () => {
  const fixtures = [
    {
      name: "declared oversize",
      response: () => jsonResponse({}, 201, { "content-length": "1000001" }),
      expected: /exceeded size limit/,
    },
    {
      name: "actual oversize",
      response: () => new Response("x".repeat(1000001), { status: 201 }),
      expected: /exceeded size limit/,
    },
    {
      name: "truncated",
      response: () => ({
        ok: true,
        status: 201,
        headers: new Headers({ "content-type": "application/json" }),
        text: async () => { throw new Error("provider response truncated"); },
      }),
      expected: /provider response truncated/,
    },
  ];
  for (const fixture of fixtures) {
    let calls = 0;
    let posts = 0;
    await assert.rejects(
      () => executeSupabaseProviderApiTool(
        QUERY_TOOL,
        validQueryArgs(),
        configuration(),
        async (_url, init) => {
          calls += 1;
          if (init.method === "POST") {
            posts += 1;
            return fixture.response();
          }
          if (calls === 1) return jsonResponse(projectRecord(PARENT));
          if (calls === 2) return jsonResponse([branchRecord()]);
          return jsonResponse(projectRecord(CHILD));
        },
      ),
      fixture.expected,
      fixture.name,
    );
    assert.equal(calls, 4, fixture.name);
    assert.equal(posts, 1, fixture.name);
  }
});

test("coarse ProjectOS scopes do not prove provider DB permission: query 403 fails without retry", async () => {
  let calls = 0;
  let posts = 0;
  await assert.rejects(
    () => executeSupabaseProviderApiTool(
      QUERY_TOOL,
      validQueryArgs(),
      configuration(),
      async (_url, init) => {
        calls += 1;
        if (init.method === "POST") {
          posts += 1;
          return jsonResponse({ message: "database permission denied" }, 403);
        }
        if (calls === 1) return jsonResponse(projectRecord(PARENT));
        if (calls === 2) return jsonResponse([branchRecord()]);
        return jsonResponse(projectRecord(CHILD));
      },
    ),
    /request failed with 403/,
  );
  assert.equal(calls, 4);
  assert.equal(posts, 1);
});

test("coarse ProjectOS scopes do not prove provider environment permission: delete 403 fails without retry", async () => {
  let calls = 0;
  let deletes = 0;
  await assert.rejects(
    () => executeSupabaseProviderApiTool(
      DELETE_TOOL,
      validDeleteArgs(),
      configuration(),
      async (_url, init) => {
        calls += 1;
        if (init.method === "DELETE") {
          deletes += 1;
          return jsonResponse({ message: "environment permission denied" }, 403);
        }
        if (calls === 1) return jsonResponse(projectRecord(PARENT));
        if (calls === 2) return jsonResponse([branchRecord()]);
        return jsonResponse(projectRecord(CHILD, ORGANIZATION, "UNHEALTHY"));
      },
    ),
    /request failed with 403/,
  );
  assert.equal(calls, 4);
  assert.equal(deletes, 1);
});

test("force teardown accepts unhealthy or deletion-pending exact bindings and preserves receipt", async () => {
  const calls = [];
  const result = await executeSupabaseProviderApiTool(
    DELETE_TOOL,
    validDeleteArgs(),
    configuration(),
    async (url, init) => {
      calls.push({ url, method: init.method });
      switch (calls.length) {
        case 1:
        case 5:
          return jsonResponse(projectRecord(PARENT));
        case 2:
          return jsonResponse([branchRecord({
            status: "FAILED",
            preview_project_status: "UNHEALTHY",
            deletion_scheduled_at: "2026-08-24T07:00:00Z",
          })]);
        case 3:
          return jsonResponse(projectRecord(CHILD, ORGANIZATION, "UNHEALTHY"));
        case 4:
          assert.equal(url, `https://api.supabase.com/v1/branches/${BRANCH_ID}?force=true`);
          assert.equal(init.method, "DELETE");
          return jsonResponse({ deletion_id: "receipt-1" });
        case 6:
          return jsonResponse([]);
        case 7:
          assert.equal(url, `https://api.supabase.com/v1/projects/${CHILD}`);
          return jsonResponse({ message: "not found" }, 404);
        default:
          throw new Error("unexpected provider request");
      }
    },
  );
  assert.deepEqual(result, {
    deleteReceipt: { deletion_id: "receipt-1" },
    reconciliation: {
      complete: true,
      branchPresent: false,
      childProjectPresent: false,
      attempts: 1,
      parentProjectRef: PARENT,
      branchId: BRANCH_ID,
      childProjectRef: CHILD,
    },
    parentSnapshot: {
      ref: PARENT,
      organizationSlug: ORGANIZATION,
      status: "ACTIVE_HEALTHY",
    },
    reconciliationArgs: validReconciliationArgs(),
  });
  assert.equal(calls.length, 7);
  assert.equal(calls.filter((call) => call.method === "DELETE").length, 1);
});

test("normal no-injected-fetch teardown uses global fetch and never needs break glass", async () => {
  const originalFetch = globalThis.fetch;
  let calls = 0;
  globalThis.fetch = async (_url, init) => {
    calls += 1;
    if (calls === 1 || calls === 5) return jsonResponse(projectRecord(PARENT));
    if (calls === 2) return jsonResponse([branchRecord()]);
    if (calls === 3) return jsonResponse(projectRecord(CHILD, ORGANIZATION, "REMOVING"));
    if (calls === 4) return jsonResponse({ deleted: true });
    if (calls === 6) return jsonResponse([]);
    assert.equal(init.method, "GET");
    return jsonResponse({}, 404);
  };
  try {
    const result = await executeSupabaseProviderApiTool(
      DELETE_TOOL,
      validDeleteArgs(),
      configuration(),
    );
    assert.equal(result.reconciliation.complete, true);
    assert.equal(result.deleteReceipt.deleted, true);
    assert.equal(calls, 7);
  } finally {
    globalThis.fetch = originalFetch;
  }
});

test("teardown preserves one DELETE receipt when the parent snapshot drifts during reconciliation", async () => {
  let calls = 0;
  let deletes = 0;
  const result = await executeSupabaseProviderApiTool(
    DELETE_TOOL,
    validDeleteArgs(),
    configuration(),
    async (_url, init) => {
      calls += 1;
      if (init.method === "DELETE") {
        deletes += 1;
        return jsonResponse({ deletion_id: "receipt-parent-drift" });
      }
      if (calls === 1) return jsonResponse(projectRecord(PARENT));
      if (calls === 2) return jsonResponse([branchRecord()]);
      if (calls === 3) return jsonResponse(projectRecord(CHILD, ORGANIZATION, "REMOVING"));
      return jsonResponse(projectRecord(PARENT, ORGANIZATION, "PAUSED"));
    },
  );
  assert.equal(calls, 5);
  assert.equal(deletes, 1);
  assert.deepEqual(result.deleteReceipt, { deletion_id: "receipt-parent-drift" });
  assert.equal(result.reconciliation.complete, false);
  assert.equal(result.reconciliation.attempts, 0);
  assert.match(result.reconciliation.error, /changed after its bound snapshot/);
});

test("teardown rejects UUID name/ref ambiguity before DELETE", async () => {
  const fixtures = [
    { name: "name-only UUID", patch: { id: OTHER_BRANCH_ID, name: BRANCH_ID, ref: CHILD } },
    { name: "default branch", patch: { is_default: true } },
    { name: "mismatched exact ref", patch: { ref: SIBLING } },
    { name: "swapped child project", patch: { project_ref: SIBLING } },
    { name: "swapped parent project", patch: { parent_project_ref: OTHER_PARENT } },
    { name: "persistent child", patch: { persistent: true } },
    { name: "data-bearing child", patch: { with_data: true } },
    {
      name: "exact plus ID collision",
      branches: [branchRecord(), branchRecord({ id: BRANCH_ID, project_ref: SIBLING, ref: SIBLING })],
    },
    {
      name: "exact plus project-ref collision",
      branches: [branchRecord(), branchRecord({ id: OTHER_BRANCH_ID, project_ref: CHILD, ref: SIBLING })],
    },
    {
      name: "exact plus ref collision",
      branches: [branchRecord(), branchRecord({ id: OTHER_BRANCH_ID, project_ref: SIBLING, ref: CHILD })],
    },
  ];
  for (const fixture of fixtures) {
    let calls = 0;
    let deletes = 0;
    await assert.rejects(
      () => executeSupabaseProviderApiTool(
        DELETE_TOOL,
        validDeleteArgs(),
        configuration(),
        async (_url, init) => {
          calls += 1;
          if (init.method === "DELETE") deletes += 1;
          if (calls === 1) return jsonResponse(projectRecord(PARENT));
          return jsonResponse(fixture.branches || [branchRecord(fixture.patch)]);
        },
      ),
      /not uniquely bound to deletable branch.*delete preflight/,
      fixture.name,
    );
    assert.equal(calls, 2, fixture.name);
    assert.equal(deletes, 0, fixture.name);
  }
});

test("teardown binds an existing unhealthy child project to the exact parent organization before DELETE", async () => {
  for (const fixture of [
    { name: "child ref mismatch", child: projectRecord(SIBLING, ORGANIZATION, "UNHEALTHY") },
    { name: "child org mismatch", child: projectRecord(CHILD, "wrong-org", "REMOVING") },
  ]) {
    let calls = 0;
    let deletes = 0;
    await assert.rejects(
      () => executeSupabaseProviderApiTool(
        DELETE_TOOL,
        validDeleteArgs(),
        configuration(),
        async (_url, init) => {
          calls += 1;
          if (init.method === "DELETE") deletes += 1;
          if (calls === 1) return jsonResponse(projectRecord(PARENT));
          if (calls === 2) return jsonResponse([branchRecord({ status: "REMOVING" })]);
          return jsonResponse(fixture.child);
        },
      ),
      /Child project.*identity drifted.*delete preflight/,
      fixture.name,
    );
    assert.equal(calls, 3, fixture.name);
    assert.equal(deletes, 0, fixture.name);
  }
});

test("teardown never retries DELETE and returns incomplete reconciliation with its receipt", async () => {
  let calls = 0;
  let deletes = 0;
  const result = await executeSupabaseProviderApiTool(
    DELETE_TOOL,
    validDeleteArgs(),
    configuration(),
    async (url, init) => {
      calls += 1;
      if (init.method === "DELETE") {
        deletes += 1;
        return jsonResponse({ deletion_id: "receipt-pending" });
      }
      if (url.endsWith(`/projects/${PARENT}`)) return jsonResponse(projectRecord(PARENT));
      if (url.endsWith(`/projects/${PARENT}/branches`)) {
        return jsonResponse([branchRecord({ status: "REMOVING" })]);
      }
      return jsonResponse(projectRecord(CHILD, ORGANIZATION, "REMOVING"));
    },
  );
  assert.equal(deletes, 1);
  assert.deepEqual(result.deleteReceipt, { deletion_id: "receipt-pending" });
  assert.deepEqual(result.reconciliation, {
    complete: false,
    branchPresent: true,
    childProjectPresent: true,
    attempts: 4,
    parentProjectRef: PARENT,
    branchId: BRANCH_ID,
    childProjectRef: CHILD,
  });
  assert.deepEqual(result.parentSnapshot, {
    ref: PARENT,
    organizationSlug: ORGANIZATION,
    status: "ACTIVE_HEALTHY",
  });
  assert.deepEqual(result.reconciliationArgs, validReconciliationArgs());
  assert.equal(calls, 16);
});

test("read-only reconciliation can progress from incomplete to terminal absence without DELETE", async () => {
  let deletes = 0;
  let incompleteCalls = 0;
  const incomplete = await executeSupabaseProviderApiTool(
    RECONCILE_TOOL,
    validReconciliationArgs(),
    configuration(),
    async (url, init) => {
      incompleteCalls += 1;
      if (init.method === "DELETE") deletes += 1;
      if (url.endsWith(`/projects/${PARENT}`)) return jsonResponse(projectRecord(PARENT));
      if (url.endsWith(`/projects/${PARENT}/branches`)) {
        return jsonResponse([branchRecord({ status: "REMOVING" })]);
      }
      return jsonResponse(projectRecord(CHILD, ORGANIZATION, "REMOVING"));
    },
  );
  assert.deepEqual(incomplete, {
    complete: false,
    branchPresent: true,
    childProjectPresent: true,
    parentProjectRef: PARENT,
    branchId: BRANCH_ID,
    childProjectRef: CHILD,
  });
  assert.equal(incompleteCalls, 3);

  for (const fixture of [
    {
      name: "branch only",
      branches: [branchRecord({ status: "REMOVING" })],
      child: jsonResponse({ message: "not found" }, 404),
      expected: { branchPresent: true, childProjectPresent: false },
    },
    {
      name: "child only",
      branches: [],
      child: jsonResponse(projectRecord(CHILD, ORGANIZATION, "REMOVING")),
      expected: { branchPresent: false, childProjectPresent: true },
    },
  ]) {
    let calls = 0;
    const state = await executeSupabaseProviderApiTool(
      RECONCILE_TOOL,
      validReconciliationArgs(),
      configuration(),
      async (url, init) => {
        calls += 1;
        if (init.method === "DELETE") deletes += 1;
        if (url.endsWith(`/projects/${PARENT}`)) return jsonResponse(projectRecord(PARENT));
        if (url.endsWith(`/projects/${PARENT}/branches`)) return jsonResponse(fixture.branches);
        return fixture.child;
      },
    );
    assert.equal(state.complete, false, fixture.name);
    assert.equal(state.branchPresent, fixture.expected.branchPresent, fixture.name);
    assert.equal(state.childProjectPresent, fixture.expected.childProjectPresent, fixture.name);
    assert.equal(calls, 3, fixture.name);
  }

  let terminalCalls = 0;
  const terminal = await executeSupabaseProviderApiTool(
    RECONCILE_TOOL,
    validReconciliationArgs(),
    configuration(),
    async (url, init) => {
      terminalCalls += 1;
      if (init.method === "DELETE") deletes += 1;
      if (url.endsWith(`/projects/${PARENT}`)) return jsonResponse(projectRecord(PARENT));
      if (url.endsWith(`/projects/${PARENT}/branches`)) return jsonResponse([]);
      return jsonResponse({ message: "not found" }, 404);
    },
  );
  assert.deepEqual(terminal, {
    complete: true,
    branchPresent: false,
    childProjectPresent: false,
    parentProjectRef: PARENT,
    branchId: BRANCH_ID,
    childProjectRef: CHILD,
  });
  assert.equal(terminalCalls, 3);
  assert.equal(deletes, 0);
});

test("read-only reconciliation validates parent snapshot and exact collision identity", async () => {
  let deletes = 0;
  let calls = 0;
  await assert.rejects(
    () => executeSupabaseProviderApiTool(
      RECONCILE_TOOL,
      validReconciliationArgs(),
      configuration(),
      async (_url, init) => {
        calls += 1;
        if (init.method === "DELETE") deletes += 1;
        return jsonResponse(projectRecord(PARENT, ORGANIZATION, "PAUSED"));
      },
    ),
    /changed after its bound snapshot/,
  );
  assert.equal(calls, 1);

  calls = 0;
  await assert.rejects(
    () => executeSupabaseProviderApiTool(
      RECONCILE_TOOL,
      validReconciliationArgs(),
      configuration(),
      async (url, init) => {
        calls += 1;
        if (init.method === "DELETE") deletes += 1;
        if (url.endsWith(`/projects/${PARENT}`)) return jsonResponse(projectRecord(PARENT));
        return jsonResponse([
          branchRecord({ status: "REMOVING" }),
          branchRecord({ id: OTHER_BRANCH_ID, project_ref: SIBLING, ref: CHILD }),
        ]);
      },
    ),
    /reconciliation identity conflict/,
  );
  assert.equal(calls, 2);

  calls = 0;
  await assert.rejects(
    () => executeSupabaseProviderApiTool(
      RECONCILE_TOOL,
      validReconciliationArgs(),
      configuration(),
      async (url, init) => {
        calls += 1;
        if (init.method === "DELETE") deletes += 1;
        if (url.endsWith(`/projects/${PARENT}`)) return jsonResponse(projectRecord(PARENT));
        if (url.endsWith(`/projects/${PARENT}/branches`)) return jsonResponse([]);
        return jsonResponse(projectRecord(SIBLING));
      },
    ),
    /Child project.*identity drifted.*reconciliation/,
  );
  assert.equal(calls, 3);
  assert.equal(deletes, 0);
});

test("reconciliation proof substitution and malformed args fail before provider I/O", async () => {
  const issued = validReconciliationArgs();
  const malformed = [
    { ...issued, childProjectRef: SIBLING },
    { ...issued, reconciliationProof: "0".repeat(64) },
    { ...issued, branchId: "not-a-uuid" },
    { ...issued, unexpected: true },
  ];
  for (const input of malformed) {
    let calls = 0;
    await assert.rejects(
      () => executeSupabaseProviderApiTool(
        RECONCILE_TOOL,
        input,
        configuration(),
        async () => {
          calls += 1;
          return jsonResponse({});
        },
      ),
    );
    assert.equal(calls, 0);
  }
});
