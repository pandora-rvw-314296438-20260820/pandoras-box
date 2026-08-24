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
const {
  buildToolConfiguration,
  inspectToolConfiguration,
  sanitizeProviderConnections,
} = require("../dist/runtime/service-config.js");
const {
  createDestructiveCapabilityReservationIntent,
  destructiveCapabilityReservationDeliveryId,
  executionPayloadHash,
} = require("../dist/http-app.js");

const QUERY_TOOL = "supabase.write-child-database-query";
const PREPARE_DELETE_TOOL = "supabase.prepare-child-deletion-reconciliation";
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
const CONTROL_PROJECT = "jcyqixttuebxqqfkjonq";
const CONTROL_ORGANIZATION_ID = "2270b266-59da-4c39-bfd9-9f8d08352af0";
const LOGICAL_SCOPES = ["projects:read", "projects:write"];
const TEST_PROVIDER_TOKEN = "test-provider-token";
const TEST_SIGNING_KEY_ID = "2026-08-24-test-v1";
const TEST_RETIRED_SIGNING_KEY_ID = "2026-08-17-test-v0";
const TEST_RESERVATION_KEY_ID = "child-delete-target-v1";
const TEST_SIGNING_KEY = Buffer.alloc(32, 0x41).toString("base64url");
const TEST_RETIRED_SIGNING_KEY = Buffer.alloc(32, 0x42).toString("base64url");
const TEST_RESERVATION_KEY = Buffer.alloc(32, 0x43).toString("base64url");
const TEST_KEYRING = {
  activeKeyId: TEST_SIGNING_KEY_ID,
  reservationKeyId: TEST_RESERVATION_KEY_ID,
  keys: {
    [TEST_SIGNING_KEY_ID]: TEST_SIGNING_KEY,
    [TEST_RETIRED_SIGNING_KEY_ID]: TEST_RETIRED_SIGNING_KEY,
    [TEST_RESERVATION_KEY_ID]: TEST_RESERVATION_KEY,
  },
};

function configuration(overrides = {}) {
  const {
    childDeletionCapabilityKeyring = TEST_KEYRING,
    destructiveCapabilityReservation = async (input) => validReservationIntent(input),
    ...accountOverrides
  } = overrides;
  return {
    accounts: [{
      id: ACCOUNT_ID,
      token: TEST_PROVIDER_TOKEN,
      allowMutations: true,
      allowedOrganizationSlugs: [],
      allowedProjectRefs: [PARENT],
      grantedScopes: LOGICAL_SCOPES,
      ...accountOverrides,
    }],
    timeoutMs: 1000,
    maxResponseBytes: 2000000,
    childDeletionCapabilityKeyring,
    destructiveCapabilityReservation,
  };
}

function queryProviderBody(input) {
  return { query: input.sql, parameters: input.parameters, read_only: false };
}

function sha256(value) {
  return createHash("sha256").update(value, "utf8").digest("hex");
}

function stableValue(value) {
  if (Array.isArray(value)) return value.map(stableValue);
  if (value && typeof value === "object") {
    return Object.fromEntries(Object.entries(value)
      .sort(([left], [right]) => left.localeCompare(right))
      .map(([key, nested]) => [key, stableValue(nested)]));
  }
  return value;
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
  if (!Object.prototype.hasOwnProperty.call(overrides, "deletionCapability")) {
    value.deletionCapability = validDeletionCapability(value);
  }
  if (!Object.prototype.hasOwnProperty.call(overrides, "confirmation")) {
    value.confirmation = deleteConfirmation(value);
  }
  return value;
}

function deletionMembershipSnapshot(input = {}) {
  return {
    parent: {
      ref: input.parentProjectRef || PARENT,
      organizationSlug: input.organizationSlug || ORGANIZATION,
      status: input.parentStatus || "ACTIVE_HEALTHY",
    },
    branch: {
      id: input.branchId || BRANCH_ID,
      name: input.branchName || "disposable-child-rehearsal",
      projectRef: input.childProjectRef || CHILD,
      parentProjectRef: input.parentProjectRef || PARENT,
      ref: input.branchRef === undefined ? null : input.branchRef,
      isDefault: false,
      persistent: false,
      withData: false,
      status: input.branchStatus || "FUNCTIONS_DEPLOYED",
      previewProjectStatus: input.previewProjectStatus || "ACTIVE_HEALTHY",
      deletionScheduledAt: input.deletionScheduledAt || null,
      createdAt: input.branchCreatedAt === undefined
        ? "2026-08-24T07:00:00.000Z"
        : input.branchCreatedAt,
    },
    child: input.childAbsent ? null : {
      ref: input.childProjectRef || CHILD,
      organizationSlug: input.organizationSlug || ORGANIZATION,
      status: input.childStatus || "ACTIVE_HEALTHY",
    },
  };
}

function deletionOperationNonce(input = {}) {
  return createHmac("sha256", Buffer.from(TEST_RESERVATION_KEY, "base64url"))
    .update(JSON.stringify({
    schemaVersion: "supabase-child-deletion-target-v1",
    action: "delete-and-reconcile-child-branch",
    accountId: input.accountId || ACCOUNT_ID,
    organizationSlug: input.organizationSlug || ORGANIZATION,
    parentProjectRef: input.parentProjectRef || PARENT,
    branchId: input.branchId || BRANCH_ID,
    childProjectRef: input.childProjectRef || CHILD,
  }), "utf8")
    .digest("hex");
}

function capabilityProof(capability, keyring = TEST_KEYRING) {
  const { proof: _proof, ...payload } = capability;
  const encodedKey = keyring.keys[capability.signingKeyId];
  return createHmac("sha256", Buffer.from(encodedKey, "base64url"))
    .update(JSON.stringify(payload), "utf8")
    .digest("hex");
}

function validDeletionCapability(input = {}, overrides = {}) {
  const issuedAtMs = Object.prototype.hasOwnProperty.call(overrides, "issuedAt")
    ? Date.parse(overrides.issuedAt)
    : Date.now() - 1000;
  const value = {
    schemaVersion: "supabase-child-deletion-capability-v3",
    action: "delete-and-reconcile-child-branch",
    signingKeyId: TEST_SIGNING_KEY_ID,
    reservationKeyId: TEST_RESERVATION_KEY_ID,
    accountId: input.accountId || ACCOUNT_ID,
    organizationSlug: input.organizationSlug || ORGANIZATION,
    parentProjectRef: input.parentProjectRef || PARENT,
    parentStatus: input.parentStatus || "ACTIVE_HEALTHY",
    branchId: input.branchId || BRANCH_ID,
    childProjectRef: input.childProjectRef || CHILD,
    operationNonce: deletionOperationNonce(input),
    issuedAt: new Date(issuedAtMs).toISOString(),
    deleteAuthorizationExpiresAt: new Date(issuedAtMs + 10 * 60 * 1000).toISOString(),
    reconciliationExpiresAt: new Date(issuedAtMs + 7 * 24 * 60 * 60 * 1000).toISOString(),
    membershipSnapshotSha256: sha256(JSON.stringify(deletionMembershipSnapshot(input))),
    ...overrides,
  };
  if (!Object.prototype.hasOwnProperty.call(overrides, "proof")) {
    value.proof = capabilityProof(value);
  }
  return value;
}

function resignDeletionCapability(capability, patch = {}, keyring = TEST_KEYRING) {
  const value = { ...capability, ...patch };
  delete value.proof;
  value.proof = capabilityProof(value, keyring);
  return value;
}

function validClaimedDeletePlan(input = validDeleteArgs(), overrides = {}) {
  return {
    planId: "55555555-5555-4555-8555-555555555555",
    requestId: "77777777-7777-4777-8777-777777777777",
    intakeId: "66666666-6666-4666-8666-666666666666",
    tool: DELETE_TOOL,
    risk: "destructive",
    args: input,
    payloadHash: executionPayloadHash(DELETE_TOOL, input),
    status: "executing",
    ...overrides,
  };
}

function validReservationIntent(input = validDeleteArgs(), overrides = {}) {
  return createDestructiveCapabilityReservationIntent(validClaimedDeletePlan(input, overrides));
}

function validReservationReceipt(input = validDeleteArgs(), overrides = {}) {
  const intent = validReservationIntent(input, overrides);
  return {
    schemaVersion: "projectos-destructive-capability-reservation-receipt-v2",
    controlProjectRef: CONTROL_PROJECT,
    eventId: 901,
    provider: intent.provider,
    deliveryId: intent.deliveryId,
    eventType: intent.eventType,
    payloadHash: intent.payloadHash,
    receivedAt: "2026-08-24T12:00:00.000Z",
    processedAt: "2026-08-24T12:00:00.000Z",
  };
}

function reservationRowFromRequest(init, patch = {}) {
  const body = JSON.parse(init.body);
  assert.equal(body.query, "insert into public.projectos_external_events (organization_id,project_id,provider,delivery_id,event_type,repository,external_created_at,payload_hash,payload_redacted,process_status,processed_at) values ($1::uuid,null,$2::text,$3::text,$4::text,null,null,$5::text,$6::jsonb,'processed',clock_timestamp()) on conflict (organization_id,provider,delivery_id) do nothing returning jsonb_build_object('id',id,'organization_id',organization_id,'project_id',project_id,'provider',provider,'delivery_id',delivery_id,'event_type',event_type,'repository',repository,'external_created_at',external_created_at,'payload_hash',payload_hash,'payload_redacted',payload_redacted,'process_status',process_status,'process_error',process_error,'received_at',received_at,'processed_at',processed_at) as reservation");
  assert.equal(body.read_only, false);
  assert.equal(body.parameters.length, 6);
  const [organizationId, provider, deliveryId, eventType, payloadHash, payloadRedacted] = body.parameters;
  assert.deepEqual(Object.keys(payloadRedacted).sort(), [
    "reservationDomain", "schemaVersion", "sourcePayloadHash", "sourcePlanId",
    "sourceRequestId", "targetDigest",
  ]);
  for (const forbidden of [
    "accountId", "capability", "membershipSnapshotSha256", "operationNonce", "proof",
    "reservationKeyId", "signingKeyId", "sourceIntakeId",
  ]) {
    assert.equal(Object.prototype.hasOwnProperty.call(payloadRedacted, forbidden), false, forbidden);
  }
  return {
    id: 901,
    organization_id: organizationId,
    project_id: null,
    provider,
    delivery_id: deliveryId,
    event_type: eventType,
    repository: null,
    external_created_at: null,
    payload_hash: payloadHash,
    payload_redacted: payloadRedacted,
    process_status: "processed",
    process_error: null,
    received_at: "2026-08-24T12:00:00+00:00",
    processed_at: "2026-08-24T12:00:00+00:00",
    ...patch,
  };
}

function reservationAwareFetch(fetchFn, options = {}) {
  return async (url, init) => {
    if (url.endsWith(`/projects/${CONTROL_PROJECT}`)) {
      options.onControlRead?.();
      return jsonResponse(projectRecord(CONTROL_PROJECT));
    }
    if (url.endsWith(`/projects/${CONTROL_PROJECT}/database/query`)) {
      options.onReservation?.();
      const row = reservationRowFromRequest(init, options.reservationRowPatch || {});
      options.reservationRowMutator?.(row, init);
      return jsonResponse([{ reservation: row }]);
    }
    return fetchFn(url, init);
  };
}

function validReconciliationArgs(overrides = {}) {
  const value = {
    accountId: ACCOUNT_ID,
    parentProjectRef: PARENT,
    branchId: BRANCH_ID,
    childProjectRef: CHILD,
    ...overrides,
  };
  if (!Object.prototype.hasOwnProperty.call(overrides, "deletionCapability")) {
    value.deletionCapability = validDeletionCapability(value);
  }
  return value;
}

function validPreparationArgs(overrides = {}) {
  return {
    accountId: ACCOUNT_ID,
    parentProjectRef: PARENT,
    branchId: BRANCH_ID,
    childProjectRef: CHILD,
    ...overrides,
  };
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
    created_at: "2026-08-24T07:00:00.000Z",
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
  for (const readTool of [PREPARE_DELETE_TOOL, RECONCILE_TOOL]) {
    const readManifest = getToolManifest(readTool);
    assert.deepEqual({
      provider: readManifest.provider,
      risk: readManifest.risk,
      mutation: readManifest.mutation,
      scope: readManifest.scope,
      requiredProviderScopes: readManifest.requiredProviderScopes,
      confirmationKind: readManifest.confirmationKind,
    }, {
      provider: "supabase",
      risk: "read",
      mutation: false,
      scope: "branch",
      requiredProviderScopes: ["projects:read"],
      confirmationKind: undefined,
    });
    assert.ok(toolRegistry[readTool]);
    assert.equal(supabaseProviderApiTools[readTool].parameters.additionalProperties, false);
  }
  assert.deepEqual(supabaseProviderApiTools[QUERY_TOOL].parameters.required, [
    "accountId", "parentProjectRef", "branchId", "childProjectRef",
    "sql", "parameters", "bodySha256", "confirmation",
  ]);
  assert.deepEqual(supabaseProviderApiTools[DELETE_TOOL].parameters.required, [
    "accountId", "parentProjectRef", "branchId", "childProjectRef",
    "deletionCapability", "confirmation",
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
  const alternateCapability = resignDeletionCapability(deleteInput.deletionCapability, {
    operationNonce: "cd".repeat(32),
  });
  assert.notEqual(
    executionPayloadHash(DELETE_TOOL, validDeleteArgs({ deletionCapability: alternateCapability })),
    executionPayloadHash(DELETE_TOOL, deleteInput),
  );
  const firstDeleteDeliveryId = destructiveCapabilityReservationDeliveryId(
    DELETE_TOOL,
    deleteInput,
  );
  const replayDeleteDeliveryId = destructiveCapabilityReservationDeliveryId(
    DELETE_TOOL,
    deleteInput,
  );
  assert.match(firstDeleteDeliveryId, /^[0-9a-f]{64}$/);
  assert.equal(replayDeleteDeliveryId, firstDeleteDeliveryId);
  assert.equal(
    destructiveCapabilityReservationDeliveryId(
      DELETE_TOOL,
      validDeleteArgs({ deletionCapability: alternateCapability }),
    ),
    firstDeleteDeliveryId,
  );
  const alternateAuthorityCapability = {
    ...deleteInput.deletionCapability,
    signingKeyId: "alternate-proof-key",
    reservationKeyId: "alternate-reservation-key",
    accountId: "alternate-account-alias",
    organizationSlug: "m".repeat(20),
    operationNonce: "ef".repeat(32),
    proof: "01".repeat(32),
  };
  assert.equal(
    destructiveCapabilityReservationDeliveryId(
      DELETE_TOOL,
      validDeleteArgs({
        accountId: alternateAuthorityCapability.accountId,
        deletionCapability: alternateAuthorityCapability,
      }),
    ),
    firstDeleteDeliveryId,
  );
  const reservationIntent = validReservationIntent(deleteInput);
  assert.equal(reservationIntent.payloadRedacted.reservationDomain,
    "projectos-supabase-child-branch-delete-v1");
  assert.equal(reservationIntent.payloadBinding.capabilitySchemaVersion,
    deleteInput.deletionCapability.schemaVersion);
  assert.equal(Object.prototype.hasOwnProperty.call(
    reservationIntent.payloadRedacted,
    "capabilitySchemaVersion",
  ), false);
  assert.notEqual(
    destructiveCapabilityReservationDeliveryId(
      DELETE_TOOL,
      validDeleteArgs({ branchId: OTHER_BRANCH_ID }),
    ),
    firstDeleteDeliveryId,
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
  for (const organizationSlug of ["wrong-org", "LQVPJQBGFODMTSWXIZWF", "", null]) {
    let parentCalls = 0;
    await assert.rejects(
      () => executeSupabaseProviderApiTool(
        PREPARE_DELETE_TOOL,
        validPreparationArgs(),
        configuration(),
        async () => {
          parentCalls += 1;
          return jsonResponse(projectRecord(PARENT, organizationSlug));
        },
      ),
      /Allowed parent project.*identity drifted/,
    );
    assert.equal(parentCalls, 1);
  }
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

test("malformed branch inventories fail closed for query, prepare, delete, and reconciliation", async () => {
  const malformedInventories = [
    null,
    {},
    { branches: {} },
    { branches: [branchRecord()], total: 1 },
    [null],
    [{}],
    [branchRecord(), {}],
    [branchRecord({ id: "not-a-uuid" })],
    [branchRecord({ project_ref: "short" })],
    [branchRecord({ parent_project_ref: "short" })],
    [branchRecord({ ref: 42 })],
  ];
  const routes = [
    { tool: QUERY_TOOL, args: validQueryArgs() },
    { tool: PREPARE_DELETE_TOOL, args: validPreparationArgs() },
    { tool: DELETE_TOOL, args: validDeleteArgs() },
    { tool: RECONCILE_TOOL, args: validReconciliationArgs() },
  ];
  for (const inventory of malformedInventories) {
    for (const route of routes) {
      let calls = 0;
      let writes = 0;
      await assert.rejects(
        () => executeSupabaseProviderApiTool(
          route.tool,
          route.args,
          configuration(),
          async (url, init) => {
            calls += 1;
            if (init.method !== "GET") writes += 1;
            if (url.endsWith(`/projects/${PARENT}`)) return jsonResponse(projectRecord(PARENT));
            if (url.endsWith(`/projects/${PARENT}/branches`)) return jsonResponse(inventory);
            throw new Error("malformed inventory must stop before child-project I/O");
          },
        ),
        /child branch inventory is malformed/,
        `${route.tool}: ${JSON.stringify(inventory)}`,
      );
      assert.equal(calls, 2, route.tool);
      assert.equal(writes, 0, route.tool);
    }
  }
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
  const deleteInput = validDeleteArgs({
    deletionCapability: validDeletionCapability({ childStatus: "UNHEALTHY" }),
  });
  await assert.rejects(
    () => executeSupabaseProviderApiTool(
      DELETE_TOOL,
      deleteInput,
      configuration(),
      reservationAwareFetch(async (url, init) => {
        calls += 1;
        if (init.method === "DELETE") {
          deletes += 1;
          return jsonResponse({ message: "environment permission denied" }, 403);
        }
        if (url.endsWith(`/projects/${PARENT}`)) return jsonResponse(projectRecord(PARENT));
        if (url.endsWith(`/projects/${PARENT}/branches`)) return jsonResponse([branchRecord()]);
        return jsonResponse(projectRecord(CHILD, ORGANIZATION, "UNHEALTHY"));
      }),
    ),
    /request failed with 403/,
  );
  assert.equal(calls, 7);
  assert.equal(deletes, 1);
});

test("control-project reservation authority failures are terminal and never reach DELETE", async () => {
  const fixtures = [
    { name: "control GET 401", phase: "read", status: 401 },
    { name: "control GET 403", phase: "read", status: 403 },
    { name: "reservation POST 401", phase: "write", status: 401 },
    { name: "reservation POST 403", phase: "write", status: 403 },
    { name: "reservation POST transport loss", phase: "transport" },
  ];
  for (const fixture of fixtures) {
    let controlReads = 0;
    let reservationPosts = 0;
    let deletes = 0;
    await assert.rejects(
      () => executeSupabaseProviderApiTool(
        DELETE_TOOL,
        validDeleteArgs(),
        configuration(),
        async (url, init) => {
          if (url.endsWith(`/projects/${CONTROL_PROJECT}`)) {
            controlReads += 1;
            if (fixture.phase === "read") {
              return jsonResponse({ message: "control project permission denied" }, fixture.status);
            }
            return jsonResponse(projectRecord(CONTROL_PROJECT));
          }
          if (url.endsWith(`/projects/${CONTROL_PROJECT}/database/query`)) {
            reservationPosts += 1;
            if (fixture.phase === "transport") {
              throw new TypeError("reservation transport lost");
            }
            return jsonResponse({ message: "reservation permission denied" }, fixture.status);
          }
          if (init.method === "DELETE") {
            deletes += 1;
            return jsonResponse({ deleted: true });
          }
          if (url.endsWith(`/projects/${PARENT}`)) return jsonResponse(projectRecord(PARENT));
          if (url.endsWith(`/projects/${PARENT}/branches`)) return jsonResponse([branchRecord()]);
          return jsonResponse(projectRecord(CHILD));
        },
      ),
      fixture.phase === "transport" ? /reservation transport lost/ : /request failed with (401|403)/,
      fixture.name,
    );
    assert.equal(controlReads, 1, fixture.name);
    assert.equal(reservationPosts, fixture.phase === "read" ? 0 : 1, fixture.name);
    assert.equal(deletes, 0, fixture.name);
  }
});

test("read-only preparation pre-issues a signed target and membership capability before DELETE", async () => {
  const calls = [];
  const prepared = await executeSupabaseProviderApiTool(
    PREPARE_DELETE_TOOL,
    validPreparationArgs(),
    configuration(),
    async (url, init) => {
      calls.push({ url, method: init.method });
      if (url.endsWith(`/projects/${PARENT}`)) return jsonResponse(projectRecord(PARENT));
      if (url.endsWith(`/projects/${PARENT}/branches`)) return jsonResponse([branchRecord()]);
      return jsonResponse(projectRecord(CHILD, ORGANIZATION, "UNHEALTHY"));
    },
  );
  assert.equal(calls.length, 3);
  assert.equal(calls.every((call) => call.method === "GET"), true);
  assert.deepEqual(prepared.parentSnapshot, {
    ref: PARENT,
    organizationSlug: ORGANIZATION,
    status: "ACTIVE_HEALTHY",
  });
  assert.match(prepared.membershipSnapshotSha256, /^[a-f0-9]{64}$/);
  assert.equal(prepared.deletionCapability.membershipSnapshotSha256,
    prepared.membershipSnapshotSha256);
  assert.equal(prepared.deletionCapability.proof,
    capabilityProof(prepared.deletionCapability));
  assert.equal(
    Date.parse(prepared.deletionCapability.deleteAuthorizationExpiresAt)
      - Date.parse(prepared.deletionCapability.issuedAt),
    10 * 60 * 1000,
  );
  assert.equal(
    Date.parse(prepared.deletionCapability.reconciliationExpiresAt)
      - Date.parse(prepared.deletionCapability.issuedAt),
    7 * 24 * 60 * 60 * 1000,
  );
  assert.deepEqual(prepared.deleteArgs, {
    ...validPreparationArgs(),
    deletionCapability: prepared.deletionCapability,
    confirmation: deleteConfirmation(validPreparationArgs()),
  });
  assert.deepEqual(prepared.reconciliationArgs, {
    ...validPreparationArgs(),
    deletionCapability: prepared.deletionCapability,
  });
});

test("preparation rejects absent targets and provider authorization failure without any write", async () => {
  for (const fixture of [
    { name: "child absent", response: jsonResponse({ message: "not found" }, 404), pattern: /absent during deletion capability preparation/ },
    { name: "provider unauthorized", response: jsonResponse({ message: "unauthorized" }, 401), pattern: /request failed with 401/ },
    { name: "provider forbidden", response: jsonResponse({ message: "forbidden" }, 403), pattern: /request failed with 403/ },
  ]) {
    let calls = 0;
    let writes = 0;
    await assert.rejects(
      () => executeSupabaseProviderApiTool(
        PREPARE_DELETE_TOOL,
        validPreparationArgs(),
        configuration(),
        async (url, init) => {
          calls += 1;
          if (init.method !== "GET") writes += 1;
          if (fixture.name.startsWith("provider ")) return fixture.response;
          if (url.endsWith(`/projects/${PARENT}`)) return jsonResponse(projectRecord(PARENT));
          if (url.endsWith(`/projects/${PARENT}/branches`)) return jsonResponse([branchRecord()]);
          return fixture.response;
        },
      ),
      fixture.pattern,
      fixture.name,
    );
    assert.equal(writes, 0, fixture.name);
    assert.equal(calls, fixture.name.startsWith("provider ") ? 1 : 3, fixture.name);
  }
});

test("a capability issued before DELETE survives an accepted-but-response-lost outcome", async () => {
  const prepared = await executeSupabaseProviderApiTool(
    PREPARE_DELETE_TOOL,
    validPreparationArgs(),
    configuration(),
    async (url) => {
      if (url.endsWith(`/projects/${PARENT}`)) return jsonResponse(projectRecord(PARENT));
      if (url.endsWith(`/projects/${PARENT}/branches`)) return jsonResponse([branchRecord()]);
      return jsonResponse(projectRecord(CHILD));
    },
  );
  let deletes = 0;
  await assert.rejects(
    () => executeSupabaseProviderApiTool(
      DELETE_TOOL,
      prepared.deleteArgs,
      configuration(),
      reservationAwareFetch(async (url, init) => {
        if (init.method === "DELETE") {
          deletes += 1;
          throw new TypeError("transport lost after provider accepted DELETE");
        }
        if (url.endsWith(`/projects/${PARENT}`)) return jsonResponse(projectRecord(PARENT));
        if (url.endsWith(`/projects/${PARENT}/branches`)) return jsonResponse([branchRecord()]);
        return jsonResponse(projectRecord(CHILD));
      }),
    ),
    /transport lost after provider accepted DELETE/,
  );
  assert.equal(deletes, 1);
  const reconciled = await executeSupabaseProviderApiTool(
    RECONCILE_TOOL,
    prepared.reconciliationArgs,
    configuration(),
    async (url, init) => {
      assert.equal(init.method, "GET");
      if (url.endsWith(`/projects/${PARENT}`)) return jsonResponse(projectRecord(PARENT));
      if (url.endsWith(`/projects/${PARENT}/branches`)) return jsonResponse([]);
      return jsonResponse({ message: "not found" }, 404);
    },
  );
  assert.deepEqual(reconciled, {
    complete: true,
    branchPresent: false,
    childProjectPresent: false,
    parentProjectRef: PARENT,
    branchId: BRANCH_ID,
    childProjectRef: CHILD,
  });
  assert.equal(deletes, 1);
});

test("capability tamper, expiry, and pre-delete membership drift fail closed", async () => {
  const base = validDeletionCapability();
  const expiredDeleteIssuedAt = Date.now() - 11 * 60 * 1000;
  const expiredDelete = resignDeletionCapability(base, {
    issuedAt: new Date(expiredDeleteIssuedAt).toISOString(),
    deleteAuthorizationExpiresAt: new Date(expiredDeleteIssuedAt + 10 * 60 * 1000).toISOString(),
    reconciliationExpiresAt: new Date(expiredDeleteIssuedAt + 7 * 24 * 60 * 60 * 1000).toISOString(),
  });
  const expiredReconciliationIssuedAt = Date.now() - 8 * 24 * 60 * 60 * 1000;
  const expiredReconciliation = resignDeletionCapability(base, {
    issuedAt: new Date(expiredReconciliationIssuedAt).toISOString(),
    deleteAuthorizationExpiresAt: new Date(expiredReconciliationIssuedAt + 10 * 60 * 1000).toISOString(),
    reconciliationExpiresAt: new Date(expiredReconciliationIssuedAt + 7 * 24 * 60 * 60 * 1000).toISOString(),
  });
  const cases = [
    {
      name: "tampered proof",
      tool: DELETE_TOOL,
      args: validDeleteArgs({ deletionCapability: { ...base, proof: "0".repeat(64) } }),
      pattern: /capability proof is invalid/,
      expectedCalls: 0,
    },
    {
      name: "expired delete authorization",
      tool: DELETE_TOOL,
      args: validDeleteArgs({ deletionCapability: expiredDelete }),
      pattern: /expired for delete/,
      expectedCalls: 0,
    },
    {
      name: "expired reconciliation authorization",
      tool: RECONCILE_TOOL,
      args: validReconciliationArgs({ deletionCapability: expiredReconciliation }),
      pattern: /expired for reconciliation/,
      expectedCalls: 0,
    },
    {
      name: "membership drift",
      tool: DELETE_TOOL,
      args: validDeleteArgs({ deletionCapability: base }),
      pattern: /target drifted after capability preparation/,
      expectedCalls: 3,
    },
  ];
  for (const fixture of cases) {
    let calls = 0;
    let deletes = 0;
    let reservations = 0;
    await assert.rejects(
      () => executeSupabaseProviderApiTool(
        fixture.tool,
        fixture.args,
        configuration({
          destructiveCapabilityReservation: async () => {
            reservations += 1;
            return validReservationIntent(fixture.args);
          },
        }),
        async (url, init) => {
          calls += 1;
          if (init.method === "DELETE") deletes += 1;
          if (url.endsWith(`/projects/${PARENT}`)) return jsonResponse(projectRecord(PARENT));
          if (url.endsWith(`/projects/${PARENT}/branches`)) {
            return jsonResponse([branchRecord({ name: "drifted-child-name" })]);
          }
          return jsonResponse(projectRecord(CHILD));
        },
      ),
      fixture.pattern,
      fixture.name,
    );
    assert.equal(calls, fixture.expectedCalls, fixture.name);
    assert.equal(deletes, 0, fixture.name);
    assert.equal(reservations, 0, fixture.name);
  }
});

test("branch and child operational drift after preparation cannot reserve or duplicate DELETE", async () => {
  const fixtures = [
    { name: "branch status", branch: { status: "REMOVING" }, childStatus: "ACTIVE_HEALTHY" },
    { name: "preview status", branch: { preview_project_status: "UNHEALTHY" }, childStatus: "ACTIVE_HEALTHY" },
    { name: "deletion schedule", branch: { deletion_scheduled_at: "2026-08-24T12:00:00Z" }, childStatus: "ACTIVE_HEALTHY" },
    { name: "child status", branch: {}, childStatus: "REMOVING" },
  ];
  for (const fixture of fixtures) {
    let reservations = 0;
    let deletes = 0;
    let calls = 0;
    await assert.rejects(
      () => executeSupabaseProviderApiTool(
        DELETE_TOOL,
        validDeleteArgs(),
        configuration({
          destructiveCapabilityReservation: async () => {
            reservations += 1;
            return validReservationIntent();
          },
        }),
        async (url, init) => {
          calls += 1;
          if (init.method === "DELETE") deletes += 1;
          if (url.endsWith(`/projects/${PARENT}`)) return jsonResponse(projectRecord(PARENT));
          if (url.endsWith(`/projects/${PARENT}/branches`)) {
            return jsonResponse([branchRecord(fixture.branch)]);
          }
          return jsonResponse(projectRecord(CHILD, ORGANIZATION, fixture.childStatus));
        },
      ),
      /target drifted after capability preparation/,
      fixture.name,
    );
    assert.equal(calls, 3, fixture.name);
    assert.equal(reservations, 0, fixture.name);
    assert.equal(deletes, 0, fixture.name);
  }
});

test("target drift after the durable reservation burns the target and still prevents DELETE", async () => {
  let targetReads = 0;
  let reservations = 0;
  let deletes = 0;
  await assert.rejects(
    () => executeSupabaseProviderApiTool(
      DELETE_TOOL,
      validDeleteArgs(),
      configuration(),
      reservationAwareFetch(async (url, init) => {
        targetReads += 1;
        if (init.method === "DELETE") {
          deletes += 1;
          return jsonResponse({ deleted: true });
        }
        if (url.endsWith(`/projects/${PARENT}`)) return jsonResponse(projectRecord(PARENT));
        if (url.endsWith(`/projects/${PARENT}/branches`)) {
          return jsonResponse([branchRecord(targetReads > 3 ? { status: "REMOVING" } : {})]);
        }
        return jsonResponse(projectRecord(CHILD));
      }, {
        onReservation() {
          reservations += 1;
        },
      }),
    ),
    /target drifted after durable reservation|not uniquely bound.*post-reservation/,
  );
  assert.equal(reservations, 1);
  assert.equal(deletes, 0);
  assert.equal(targetReads, 6);
});

test("reservation intent, private binding, public receipt, and returned row reject every field omission", async () => {
  const input = validDeleteArgs();
  const baseIntent = validReservationIntent(input);
  assert.equal(baseIntent.payloadBinding.sourcePayloadHash, executionPayloadHash(DELETE_TOOL, input));
  assert.equal(baseIntent.payloadHash,
    sha256(JSON.stringify(stableValue(baseIntent.payloadBinding))));
  assert.deepEqual(Object.keys(baseIntent.payloadRedacted).sort(), [
    "reservationDomain", "schemaVersion", "sourcePayloadHash", "sourcePlanId",
    "sourceRequestId", "targetDigest",
  ]);

  const intentMutations = [];
  for (const key of Object.keys(baseIntent)) {
    intentMutations.push({
      name: `intent.${key}`,
      mutate(intent) {
        delete intent[key];
      },
    });
  }
  for (const key of Object.keys(baseIntent.payloadBinding)) {
    intentMutations.push({
      name: `payloadBinding.${key}`,
      mutate(intent) {
        delete intent.payloadBinding[key];
      },
    });
  }
  for (const key of Object.keys(baseIntent.payloadRedacted)) {
    intentMutations.push({
      name: `payloadRedacted.${key}`,
      mutate(intent) {
        delete intent.payloadRedacted[key];
      },
    });
  }
  intentMutations.push({
    name: "self-consistent but unrelated source payload hash",
    mutate(intent) {
      intent.payloadBinding.sourcePayloadHash = "0".repeat(64);
      intent.payloadRedacted.sourcePayloadHash = "0".repeat(64);
      intent.payloadHash = sha256(JSON.stringify(stableValue(intent.payloadBinding)));
    },
  });
  for (const fixture of intentMutations) {
    let deletes = 0;
    let controlCalls = 0;
    await assert.rejects(
      () => executeSupabaseProviderApiTool(
        DELETE_TOOL,
        input,
        configuration({
          destructiveCapabilityReservation: async () => {
            const intent = structuredClone(baseIntent);
            fixture.mutate(intent);
            return intent;
          },
        }),
        async (url, init) => {
          if (url.includes(CONTROL_PROJECT)) controlCalls += 1;
          if (init.method === "DELETE") deletes += 1;
          if (url.endsWith(`/projects/${PARENT}`)) return jsonResponse(projectRecord(PARENT));
          if (url.endsWith(`/projects/${PARENT}/branches`)) return jsonResponse([branchRecord()]);
          return jsonResponse(projectRecord(CHILD));
        },
      ),
      /reservation intent is missing or invalid/,
      fixture.name,
    );
    assert.equal(controlCalls, 0, fixture.name);
    assert.equal(deletes, 0, fixture.name);
  }

  const rowKeys = Object.keys(reservationRowFromRequest({
    body: JSON.stringify({
      query: "insert into public.projectos_external_events (organization_id,project_id,provider,delivery_id,event_type,repository,external_created_at,payload_hash,payload_redacted,process_status,processed_at) values ($1::uuid,null,$2::text,$3::text,$4::text,null,null,$5::text,$6::jsonb,'processed',clock_timestamp()) on conflict (organization_id,provider,delivery_id) do nothing returning jsonb_build_object('id',id,'organization_id',organization_id,'project_id',project_id,'provider',provider,'delivery_id',delivery_id,'event_type',event_type,'repository',repository,'external_created_at',external_created_at,'payload_hash',payload_hash,'payload_redacted',payload_redacted,'process_status',process_status,'process_error',process_error,'received_at',received_at,'processed_at',processed_at) as reservation",
      parameters: [
        CONTROL_ORGANIZATION_ID, baseIntent.provider, baseIntent.deliveryId,
        baseIntent.eventType, baseIntent.payloadHash, baseIntent.payloadRedacted,
      ],
      read_only: false,
    }),
  }));
  for (const key of rowKeys) {
    let deletes = 0;
    let reservationPosts = 0;
    await assert.rejects(
      () => executeSupabaseProviderApiTool(
        DELETE_TOOL,
        input,
        configuration(),
        reservationAwareFetch(async (url, init) => {
          if (init.method === "DELETE") deletes += 1;
          if (url.endsWith(`/projects/${PARENT}`)) return jsonResponse(projectRecord(PARENT));
          if (url.endsWith(`/projects/${PARENT}/branches`)) return jsonResponse([branchRecord()]);
          return jsonResponse(projectRecord(CHILD));
        }, {
          reservationRowMutator(row) {
            delete row[key];
          },
          onReservation() {
            reservationPosts += 1;
          },
        }),
      ),
      /reservation was not proven/,
      `reservation row ${key}`,
    );
    assert.equal(reservationPosts, 1, key);
    assert.equal(deletes, 0, key);
  }
});

test("reservation response shape, cardinality, and every returned field fail closed on drift", async () => {
  const invalidResponses = [
    { name: "null result", build: () => null },
    { name: "scalar result", build: () => "reservation" },
    { name: "object result", build: (row) => ({ reservation: row }) },
    { name: "conflict empty result", build: () => [] },
    { name: "multiple rows", build: (row) => [{ reservation: row }, { reservation: row }] },
    { name: "missing result key", build: (row) => [{ event: row }] },
    { name: "extra result key", build: (row) => [{ reservation: row, extra: true }] },
    { name: "null reservation", build: () => [{ reservation: null }] },
    {
      name: "extra row key",
      build(row) {
        return [{ reservation: { ...row, extra: true } }];
      },
    },
    {
      name: "processed timestamp precedes receipt",
      build(row) {
        return [{ reservation: {
          ...row,
          received_at: "2026-08-24T12:00:01.000Z",
          processed_at: "2026-08-24T12:00:00.000Z",
        } }];
      },
    },
    {
      name: "negative event id",
      build(row) {
        return [{ reservation: { ...row, id: -1 } }];
      },
    },
    {
      name: "noncanonical event id string",
      build(row) {
        return [{ reservation: { ...row, id: "01" } }];
      },
    },
  ];
  const rowDrift = {
    id: 0,
    organization_id: "00000000-0000-4000-8000-000000000000",
    project_id: CONTROL_PROJECT,
    provider: "wrong_provider",
    delivery_id: "0".repeat(64),
    event_type: "wrong_event",
    repository: "banataosystems/Pandoras-box",
    external_created_at: "2026-08-24T12:00:00.000Z",
    payload_hash: "0".repeat(64),
    payload_redacted: { schemaVersion: "wrong" },
    process_status: "pending",
    process_error: "unexpected",
    received_at: "not-a-timestamp",
    processed_at: "not-a-timestamp",
  };
  for (const [key, value] of Object.entries(rowDrift)) {
    invalidResponses.push({
      name: `row field ${key}`,
      build(row) {
        return [{ reservation: { ...row, [key]: value } }];
      },
    });
  }
  for (const fixture of invalidResponses) {
    let reservationPosts = 0;
    let deletes = 0;
    await assert.rejects(
      () => executeSupabaseProviderApiTool(
        DELETE_TOOL,
        validDeleteArgs(),
        configuration(),
        async (url, init) => {
          if (url.endsWith(`/projects/${CONTROL_PROJECT}`)) {
            return jsonResponse(projectRecord(CONTROL_PROJECT));
          }
          if (url.endsWith(`/projects/${CONTROL_PROJECT}/database/query`)) {
            reservationPosts += 1;
            const row = reservationRowFromRequest(init);
            return jsonResponse(fixture.build(row));
          }
          if (init.method === "DELETE") {
            deletes += 1;
            return jsonResponse({ deleted: true });
          }
          if (url.endsWith(`/projects/${PARENT}`)) return jsonResponse(projectRecord(PARENT));
          if (url.endsWith(`/projects/${PARENT}/branches`)) return jsonResponse([branchRecord()]);
          return jsonResponse(projectRecord(CHILD));
        },
      ),
      /reservation was not proven/,
      fixture.name,
    );
    assert.equal(reservationPosts, 1, fixture.name);
    assert.equal(deletes, 0, fixture.name);
  }
});

test("force teardown accepts unhealthy or deletion-pending exact bindings and preserves receipt", async () => {
  const calls = [];
  const deleteInput = validDeleteArgs({
    deletionCapability: validDeletionCapability({
      branchStatus: "FAILED",
      previewProjectStatus: "UNHEALTHY",
      deletionScheduledAt: "2026-08-24T07:00:00Z",
      childStatus: "UNHEALTHY",
    }),
  });
  const result = await executeSupabaseProviderApiTool(
    DELETE_TOOL,
    deleteInput,
    configuration(),
    reservationAwareFetch(async (url, init) => {
      calls.push({ url, method: init.method });
      switch (calls.length) {
        case 1:
        case 4:
        case 8:
          return jsonResponse(projectRecord(PARENT));
        case 2:
        case 5:
          return jsonResponse([branchRecord({
            status: "FAILED",
            preview_project_status: "UNHEALTHY",
            deletion_scheduled_at: "2026-08-24T07:00:00Z",
          })]);
        case 3:
        case 6:
          return jsonResponse(projectRecord(CHILD, ORGANIZATION, "UNHEALTHY"));
        case 7:
          assert.equal(url, `https://api.supabase.com/v1/branches/${BRANCH_ID}?force=true`);
          assert.equal(init.method, "DELETE");
          return jsonResponse({ deletion_id: "receipt-1" });
        case 9:
          return jsonResponse([]);
        case 10:
          assert.equal(url, `https://api.supabase.com/v1/projects/${CHILD}`);
          return jsonResponse({ message: "not found" }, 404);
        default:
          throw new Error("unexpected provider request");
      }
    }),
  );
  assert.deepEqual(result, {
    deleteReceipt: { deletion_id: "receipt-1" },
    reservationReceipt: validReservationReceipt(deleteInput),
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
    reconciliationArgs: validReconciliationArgs({
      deletionCapability: deleteInput.deletionCapability,
    }),
  });
  assert.equal(calls.length, 10);
  assert.equal(calls.filter((call) => call.method === "DELETE").length, 1);
});

test("normal no-injected-fetch teardown uses global fetch and never needs break glass", async () => {
  const originalFetch = globalThis.fetch;
  let calls = 0;
  globalThis.fetch = reservationAwareFetch(async (_url, init) => {
    calls += 1;
    if (calls === 1 || calls === 4 || calls === 8) return jsonResponse(projectRecord(PARENT));
    if (calls === 2 || calls === 5) return jsonResponse([branchRecord()]);
    if (calls === 3 || calls === 6) return jsonResponse(projectRecord(CHILD, ORGANIZATION, "REMOVING"));
    if (calls === 7) return jsonResponse({ deleted: true });
    if (calls === 9) return jsonResponse([]);
    assert.equal(init.method, "GET");
    return jsonResponse({}, 404);
  });
  try {
    const result = await executeSupabaseProviderApiTool(
      DELETE_TOOL,
      validDeleteArgs({
        deletionCapability: validDeletionCapability({ childStatus: "REMOVING" }),
      }),
      configuration(),
    );
    assert.equal(result.reconciliation.complete, true);
    assert.equal(result.deleteReceipt.deleted, true);
    assert.equal(calls, 10);
  } finally {
    globalThis.fetch = originalFetch;
  }
});

test("teardown preserves one DELETE receipt when the parent snapshot drifts during reconciliation", async () => {
  let calls = 0;
  let deletes = 0;
  const result = await executeSupabaseProviderApiTool(
    DELETE_TOOL,
    validDeleteArgs({
      deletionCapability: validDeletionCapability({ childStatus: "REMOVING" }),
    }),
    configuration(),
    reservationAwareFetch(async (_url, init) => {
      calls += 1;
      if (init.method === "DELETE") {
        deletes += 1;
        return jsonResponse({ deletion_id: "receipt-parent-drift" });
      }
      if (calls === 1 || calls === 4) return jsonResponse(projectRecord(PARENT));
      if (calls === 2 || calls === 5) return jsonResponse([branchRecord()]);
      if (calls === 3 || calls === 6) return jsonResponse(projectRecord(CHILD, ORGANIZATION, "REMOVING"));
      if (calls === 7) throw new Error("DELETE response fixture missing");
      return jsonResponse(projectRecord(PARENT, ORGANIZATION, "PAUSED"));
    }),
  );
  assert.equal(calls, 8);
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

test("present child projects require a concrete provider status before reservation or DELETE", async () => {
  const malformedChildren = [
    { ref: CHILD, organization_slug: ORGANIZATION },
    { ref: CHILD, organization_slug: ORGANIZATION, status: null },
    { ref: CHILD, organization_slug: ORGANIZATION, status: 42 },
    { ref: CHILD, organization_slug: ORGANIZATION, status: "" },
  ];
  for (const child of malformedChildren) {
    let calls = 0;
    let reservations = 0;
    let deletes = 0;
    await assert.rejects(
      () => executeSupabaseProviderApiTool(
        DELETE_TOOL,
        validDeleteArgs(),
        configuration({
          destructiveCapabilityReservation: async (input) => {
            reservations += 1;
            return validReservationIntent(input);
          },
        }),
        async (url, init) => {
          calls += 1;
          if (init.method === "DELETE") deletes += 1;
          if (url.endsWith(`/projects/${PARENT}`)) return jsonResponse(projectRecord(PARENT));
          if (url.endsWith(`/projects/${PARENT}/branches`)) return jsonResponse([branchRecord()]);
          return jsonResponse(child);
        },
      ),
      /Child project.*identity drifted.*delete preflight/,
    );
    assert.equal(calls, 3);
    assert.equal(reservations, 0);
    assert.equal(deletes, 0);
  }
});

test("deletable branch snapshots require bound name, status, preview status, and creation time", async () => {
  const malformedBranches = [];
  for (const field of ["name", "status", "preview_project_status", "created_at"]) {
    const missing = branchRecord();
    delete missing[field];
    malformedBranches.push(missing);
    malformedBranches.push(branchRecord({ [field]: null }));
    malformedBranches.push(branchRecord({ [field]: 42 }));
  }
  malformedBranches.push(branchRecord({ name: "" }));
  malformedBranches.push(branchRecord({ status: "" }));
  malformedBranches.push(branchRecord({ preview_project_status: "" }));
  malformedBranches.push(branchRecord({ created_at: "not-a-timestamp" }));
  for (const branch of malformedBranches) {
    let calls = 0;
    let reservations = 0;
    let deletes = 0;
    await assert.rejects(
      () => executeSupabaseProviderApiTool(
        DELETE_TOOL,
        validDeleteArgs(),
        configuration({
          destructiveCapabilityReservation: async (input) => {
            reservations += 1;
            return validReservationIntent(input);
          },
        }),
        async (url, init) => {
          calls += 1;
          if (init.method === "DELETE") deletes += 1;
          if (url.endsWith(`/projects/${PARENT}`)) return jsonResponse(projectRecord(PARENT));
          if (url.endsWith(`/projects/${PARENT}/branches`)) return jsonResponse([branch]);
          return jsonResponse(projectRecord(CHILD));
        },
      ),
      /child branch inventory is malformed|not uniquely bound to deletable branch/,
    );
    assert.equal(calls, 2);
    assert.equal(reservations, 0);
    assert.equal(deletes, 0);
  }
});

test("teardown never retries DELETE and returns incomplete reconciliation with its receipt", async () => {
  let calls = 0;
  let deletes = 0;
  const deleteInput = validDeleteArgs({
    deletionCapability: validDeletionCapability({
      branchStatus: "REMOVING",
      childStatus: "REMOVING",
    }),
  });
  const result = await executeSupabaseProviderApiTool(
    DELETE_TOOL,
    deleteInput,
    configuration(),
    reservationAwareFetch(async (url, init) => {
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
    }),
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
  assert.deepEqual(result.reconciliationArgs, validReconciliationArgs({
    deletionCapability: deleteInput.deletionCapability,
  }));
  assert.equal(calls, 19);
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

test("reconciliation capability substitution and malformed args fail before provider I/O", async () => {
  const issued = validReconciliationArgs();
  const malformed = [
    { ...issued, childProjectRef: SIBLING },
    {
      ...issued,
      deletionCapability: { ...issued.deletionCapability, proof: "0".repeat(64) },
    },
    {
      ...issued,
      deletionCapability: { ...issued.deletionCapability, action: "other-action" },
    },
    {
      ...issued,
      deletionCapability: { ...issued.deletionCapability, operationNonce: "1".repeat(64) },
    },
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

test("missing signing authority, missing reservation authority, and the legacy delete route fail before provider I/O", async () => {
  const invalidKeyrings = [
    null,
    {
      activeKeyId: "missing-proof-key",
      reservationKeyId: TEST_RESERVATION_KEY_ID,
      keys: { [TEST_RESERVATION_KEY_ID]: TEST_RESERVATION_KEY },
    },
    {
      activeKeyId: TEST_SIGNING_KEY_ID,
      reservationKeyId: TEST_SIGNING_KEY_ID,
      keys: { [TEST_SIGNING_KEY_ID]: TEST_SIGNING_KEY },
    },
  ];
  for (const childDeletionCapabilityKeyring of invalidKeyrings) {
    let calls = 0;
    await assert.rejects(
      () => executeSupabaseProviderApiTool(
        PREPARE_DELETE_TOOL,
        validPreparationArgs(),
        configuration({ childDeletionCapabilityKeyring }),
        async () => {
          calls += 1;
          return jsonResponse({});
        },
      ),
      /signing keyring|signing key.*unavailable/,
    );
    assert.equal(calls, 0);
  }

  let calls = 0;
  await assert.rejects(
    () => executeSupabaseProviderApiTool(
      DELETE_TOOL,
      validDeleteArgs(),
      configuration({ destructiveCapabilityReservation: null }),
      async () => {
        calls += 1;
        return jsonResponse({});
      },
    ),
    /reservation authority is missing/,
  );
  assert.equal(calls, 0);

  await assert.rejects(
    () => executeSupabaseProviderApiTool(
      "supabase.delete-branch-api",
      {
        accountId: ACCOUNT_ID,
        projectRef: PARENT,
        branchIdOrRef: BRANCH_ID,
        pathSegments: [],
        query: {},
        confirmation: `DELETE BRANCH ${PARENT}:${BRANCH_ID}`,
      },
      configuration(),
      async () => {
        calls += 1;
        return jsonResponse({});
      },
    ),
    /Generic Supabase branch deletion is disabled/,
  );
  assert.equal(calls, 0);
});

test("provider-token rotation and proof-key rotation preserve reconciliation while the reservation key stays fixed", async () => {
  const originalCapability = validDeletionCapability();
  const rotatedProofKeyId = "2026-08-24-test-v2";
  const rotatedProofKey = Buffer.alloc(32, 0x44).toString("base64url");
  const rotatedKeyring = {
    activeKeyId: rotatedProofKeyId,
    reservationKeyId: TEST_RESERVATION_KEY_ID,
    keys: {
      ...TEST_KEYRING.keys,
      [rotatedProofKeyId]: rotatedProofKey,
    },
  };
  const terminalFetch = async (url) => {
    if (url.endsWith(`/projects/${PARENT}`)) return jsonResponse(projectRecord(PARENT));
    if (url.endsWith(`/projects/${PARENT}/branches`)) return jsonResponse([]);
    return jsonResponse({ message: "not found" }, 404);
  };
  const reconciled = await executeSupabaseProviderApiTool(
    RECONCILE_TOOL,
    validReconciliationArgs({ deletionCapability: originalCapability }),
    configuration({
      token: "rotated-provider-token",
      childDeletionCapabilityKeyring: rotatedKeyring,
    }),
    terminalFetch,
  );
  assert.equal(reconciled.complete, true);

  const preparedAfterRotation = await executeSupabaseProviderApiTool(
    PREPARE_DELETE_TOOL,
    validPreparationArgs(),
    configuration({ childDeletionCapabilityKeyring: rotatedKeyring }),
    async (url) => {
      if (url.endsWith(`/projects/${PARENT}`)) return jsonResponse(projectRecord(PARENT));
      if (url.endsWith(`/projects/${PARENT}/branches`)) return jsonResponse([branchRecord()]);
      return jsonResponse(projectRecord(CHILD));
    },
  );
  assert.equal(preparedAfterRotation.deletionCapability.signingKeyId, rotatedProofKeyId);
  assert.equal(preparedAfterRotation.deletionCapability.reservationKeyId, TEST_RESERVATION_KEY_ID);
  assert.equal(preparedAfterRotation.deletionCapability.operationNonce, originalCapability.operationNonce);

  let calls = 0;
  await assert.rejects(
    () => executeSupabaseProviderApiTool(
      RECONCILE_TOOL,
      validReconciliationArgs({ deletionCapability: originalCapability }),
      configuration({
        childDeletionCapabilityKeyring: {
          ...rotatedKeyring,
          keys: {
            [rotatedProofKeyId]: rotatedProofKey,
            [TEST_RESERVATION_KEY_ID]: TEST_RESERVATION_KEY,
          },
        },
      }),
      async () => {
        calls += 1;
        return jsonResponse({});
      },
    ),
    /signing key.*unavailable/,
  );
  assert.equal(calls, 0);
});

test("reservation-key rotation preserves retained reconciliation but blocks old DELETE authority", async () => {
  const originalCapability = validDeletionCapability();
  const rotatedReservationKeyId = "child-delete-target-v2";
  const rotatedReservationKey = Buffer.alloc(32, 0x45).toString("base64url");
  const rotatedKeyring = {
    activeKeyId: TEST_SIGNING_KEY_ID,
    reservationKeyId: rotatedReservationKeyId,
    keys: {
      ...TEST_KEYRING.keys,
      [rotatedReservationKeyId]: rotatedReservationKey,
    },
  };
  const reconciled = await executeSupabaseProviderApiTool(
    RECONCILE_TOOL,
    validReconciliationArgs({ deletionCapability: originalCapability }),
    configuration({ childDeletionCapabilityKeyring: rotatedKeyring }),
    async (url) => {
      if (url.endsWith(`/projects/${PARENT}`)) return jsonResponse(projectRecord(PARENT));
      if (url.endsWith(`/projects/${PARENT}/branches`)) return jsonResponse([]);
      return jsonResponse({ message: "not found" }, 404);
    },
  );
  assert.equal(reconciled.complete, true);

  let missingRetainedKeyCalls = 0;
  await assert.rejects(
    () => executeSupabaseProviderApiTool(
      RECONCILE_TOOL,
      validReconciliationArgs({ deletionCapability: originalCapability }),
      configuration({
        childDeletionCapabilityKeyring: {
          ...rotatedKeyring,
          keys: {
            [TEST_SIGNING_KEY_ID]: TEST_SIGNING_KEY,
            [rotatedReservationKeyId]: rotatedReservationKey,
          },
        },
      }),
      async () => {
        missingRetainedKeyCalls += 1;
        return jsonResponse({});
      },
    ),
    /signing key.*unavailable/,
  );
  assert.equal(missingRetainedKeyCalls, 0);

  let calls = 0;
  await assert.rejects(
    () => executeSupabaseProviderApiTool(
      DELETE_TOOL,
      validDeleteArgs({ deletionCapability: originalCapability }),
      configuration({ childDeletionCapabilityKeyring: rotatedKeyring }),
      async () => {
        calls += 1;
        return jsonResponse({});
      },
    ),
    /reservation key is no longer authoritative/,
  );
  assert.equal(calls, 0);

  const prepared = await executeSupabaseProviderApiTool(
    PREPARE_DELETE_TOOL,
    validPreparationArgs(),
    configuration({ childDeletionCapabilityKeyring: rotatedKeyring }),
    async (url) => {
      if (url.endsWith(`/projects/${PARENT}`)) return jsonResponse(projectRecord(PARENT));
      if (url.endsWith(`/projects/${PARENT}/branches`)) return jsonResponse([branchRecord()]);
      return jsonResponse(projectRecord(CHILD));
    },
  );
  assert.equal(prepared.deletionCapability.reservationKeyId, rotatedReservationKeyId);
  assert.notEqual(prepared.deletionCapability.operationNonce, originalCapability.operationNonce);
  assert.equal(
    destructiveCapabilityReservationDeliveryId(DELETE_TOOL, prepared.deleteArgs),
    destructiveCapabilityReservationDeliveryId(DELETE_TOOL, validDeleteArgs()),
  );

  const forgedWithReservationKey = {
    ...originalCapability,
    signingKeyId: TEST_RESERVATION_KEY_ID,
    reservationKeyId: rotatedReservationKeyId,
  };
  forgedWithReservationKey.proof = capabilityProof(forgedWithReservationKey, rotatedKeyring);
  await assert.rejects(
    () => executeSupabaseProviderApiTool(
      DELETE_TOOL,
      validDeleteArgs({ deletionCapability: forgedWithReservationKey }),
      configuration({ childDeletionCapabilityKeyring: rotatedKeyring }),
      async () => {
        calls += 1;
        return jsonResponse({});
      },
    ),
    /signing key is no longer active|operation nonce is invalid/,
  );
  assert.equal(calls, 0);
});

test("future-issued, invalidly ordered, and sub-120-second capabilities never reserve or DELETE", async () => {
  const now = Date.now();
  const futureIssuedAt = now + 5 * 60 * 1000;
  const futureCapability = validDeletionCapability({}, {
    issuedAt: new Date(futureIssuedAt).toISOString(),
    deleteAuthorizationExpiresAt: new Date(futureIssuedAt + 10 * 60 * 1000).toISOString(),
    reconciliationExpiresAt: new Date(futureIssuedAt + 7 * 24 * 60 * 60 * 1000).toISOString(),
  });
  const invalidOrdering = resignDeletionCapability(validDeletionCapability(), {
    deleteAuthorizationExpiresAt: validDeletionCapability().issuedAt,
  });
  for (const capability of [futureCapability, invalidOrdering]) {
    let calls = 0;
    let reservations = 0;
    await assert.rejects(
      () => executeSupabaseProviderApiTool(
        DELETE_TOOL,
        validDeleteArgs({ deletionCapability: capability }),
        configuration({
          destructiveCapabilityReservation: async () => {
            reservations += 1;
            return validReservationIntent(validDeleteArgs({ deletionCapability: capability }));
          },
        }),
        async () => {
          calls += 1;
          return jsonResponse({});
        },
      ),
      /time bounds are invalid/,
    );
    assert.equal(calls, 0);
    assert.equal(reservations, 0);
  }

  const originalNow = Date.now;
  const fakeNow = now;
  const issuedAt = fakeNow - 8 * 60 * 1000 - 1000;
  const expiringCapability = validDeletionCapability({}, {
    issuedAt: new Date(issuedAt).toISOString(),
    deleteAuthorizationExpiresAt: new Date(issuedAt + 10 * 60 * 1000).toISOString(),
    reconciliationExpiresAt: new Date(issuedAt + 7 * 24 * 60 * 60 * 1000).toISOString(),
  });
  let reservations = 0;
  let deletes = 0;
  Date.now = () => fakeNow;
  try {
    await assert.rejects(
      () => executeSupabaseProviderApiTool(
        DELETE_TOOL,
        validDeleteArgs({ deletionCapability: expiringCapability }),
        configuration({
          destructiveCapabilityReservation: async () => {
            reservations += 1;
            return validReservationIntent(validDeleteArgs({ deletionCapability: expiringCapability }));
          },
        }),
          async (url, init) => {
            if (init.method === "DELETE") deletes += 1;
          if (url.endsWith(`/projects/${PARENT}`)) return jsonResponse(projectRecord(PARENT));
          if (url.endsWith(`/projects/${PARENT}/branches`)) return jsonResponse([branchRecord()]);
          return jsonResponse(projectRecord(CHILD));
        },
      ),
      /insufficient time remaining/,
    );
  } finally {
    Date.now = originalNow;
  }
  assert.equal(reservations, 0);
  assert.equal(deletes, 0);
});

test("two claimed plans sharing one capability produce one durable reservation winner and at most one dispatch", async () => {
  const args = validDeleteArgs();
  const claimedPlanIdentities = [
    {
      planId: "88888888-8888-4888-8888-888888888888",
      requestId: "aaaaaaaa-1111-4111-8111-111111111111",
      intakeId: "aaaaaaaa-aaaa-4aaa-8aaa-aaaaaaaaaaaa",
    },
    {
      planId: "99999999-9999-4999-8999-999999999999",
      requestId: "bbbbbbbb-2222-4222-8222-222222222222",
      intakeId: "bbbbbbbb-bbbb-4bbb-8bbb-bbbbbbbbbbbb",
    },
  ];
  const seenDeliveryIds = new Set();
  let reservationPosts = 0;
  let durableInserts = 0;
  let deletes = 0;
  const sharedFetch = async (url, init) => {
    if (url.endsWith(`/projects/${CONTROL_PROJECT}`)) {
      return jsonResponse(projectRecord(CONTROL_PROJECT));
    }
    if (url.endsWith(`/projects/${CONTROL_PROJECT}/database/query`)) {
      reservationPosts += 1;
      const row = reservationRowFromRequest(init);
      if (seenDeliveryIds.has(row.delivery_id)) return jsonResponse([]);
      seenDeliveryIds.add(row.delivery_id);
      durableInserts += 1;
      return jsonResponse([{ reservation: row }]);
    }
    if (init.method === "DELETE") {
      deletes += 1;
      return jsonResponse({ deleted: true });
    }
    if (url.endsWith(`/projects/${PARENT}`)) return jsonResponse(projectRecord(PARENT));
    if (url.endsWith(`/projects/${PARENT}/branches`)) return jsonResponse([branchRecord()]);
    return jsonResponse(projectRecord(CHILD));
  };
  const attempts = await Promise.allSettled(claimedPlanIdentities.map((identity) => (
    executeSupabaseProviderApiTool(
      DELETE_TOOL,
      args,
      configuration({
        destructiveCapabilityReservation: async (input) => validReservationIntent(input, identity),
      }),
      sharedFetch,
    )
  )));
  assert.equal(attempts.filter((result) => result.status === "fulfilled").length, 1);
  assert.equal(attempts.filter((result) => result.status === "rejected").length, 1);
  assert.match(attempts.find((result) => result.status === "rejected").reason.message,
    /reservation was not proven/);
  assert.equal(reservationPosts, 2);
  assert.equal(durableInserts, 1);
  assert.equal(seenDeliveryIds.size, 1);
  assert.equal(deletes, 1);
});

test("an accepted reservation with a lost response remains burned and cannot authorize a retry", async () => {
  const args = validDeleteArgs();
  const seenDeliveryIds = new Set();
  let reservationPosts = 0;
  let inserts = 0;
  let deletes = 0;
  const sharedFetch = async (url, init) => {
    if (url.endsWith(`/projects/${CONTROL_PROJECT}`)) {
      return jsonResponse(projectRecord(CONTROL_PROJECT));
    }
    if (url.endsWith(`/projects/${CONTROL_PROJECT}/database/query`)) {
      reservationPosts += 1;
      const row = reservationRowFromRequest(init);
      if (seenDeliveryIds.has(row.delivery_id)) return jsonResponse([]);
      seenDeliveryIds.add(row.delivery_id);
      inserts += 1;
      throw new TypeError("reservation response lost after durable insert");
    }
    if (init.method === "DELETE") {
      deletes += 1;
      return jsonResponse({ deleted: true });
    }
    if (url.endsWith(`/projects/${PARENT}`)) return jsonResponse(projectRecord(PARENT));
    if (url.endsWith(`/projects/${PARENT}/branches`)) return jsonResponse([branchRecord()]);
    return jsonResponse(projectRecord(CHILD));
  };
  await assert.rejects(
    () => executeSupabaseProviderApiTool(
      DELETE_TOOL,
      args,
      configuration({
        destructiveCapabilityReservation: async (input) => validReservationIntent(input, {
          planId: "aaaaaaaa-1111-4111-8111-111111111111",
          requestId: "cccccccc-3333-4333-8333-333333333333",
          intakeId: "bbbbbbbb-2222-4222-8222-222222222222",
        }),
      }),
      sharedFetch,
    ),
    /response lost/,
  );
  await assert.rejects(
    () => executeSupabaseProviderApiTool(
      DELETE_TOOL,
      args,
      configuration({
        destructiveCapabilityReservation: async (input) => validReservationIntent(input, {
          planId: "dddddddd-4444-4444-8444-444444444444",
          requestId: "eeeeeeee-5555-4555-8555-555555555555",
          intakeId: "ffffffff-6666-4666-8666-666666666666",
        }),
      }),
      sharedFetch,
    ),
    /reservation was not proven/,
  );
  assert.equal(inserts, 1);
  assert.equal(reservationPosts, 2);
  assert.equal(deletes, 0);
});

test("service configuration validates the dedicated keyring and exposes only non-secret key IDs", async () => {
  const names = [
    "SUPABASE_ACCOUNTS_JSON",
    "SUPABASE_TEST_PROVIDER_TOKEN",
    "SUPABASE_CHILD_DELETION_CAPABILITY_KEYS_JSON",
  ];
  const saved = Object.fromEntries(names.map((name) => [name, process.env[name]]));
  try {
    process.env.SUPABASE_TEST_PROVIDER_TOKEN = TEST_PROVIDER_TOKEN;
    process.env.SUPABASE_ACCOUNTS_JSON = JSON.stringify([{
      id: ACCOUNT_ID,
      label: "Test Supabase account",
      tokenEnv: "SUPABASE_TEST_PROVIDER_TOKEN",
      allowMutations: true,
      allowedOrganizationSlugs: [],
      allowedProjectRefs: [PARENT],
      grantedScopes: LOGICAL_SCOPES,
    }]);
    process.env.SUPABASE_CHILD_DELETION_CAPABILITY_KEYS_JSON = JSON.stringify(TEST_KEYRING);
    const reservation = async (input) => validReservationIntent(input);
    const built = await buildToolConfiguration(DELETE_TOOL, {
      destructiveCapabilityReservation: reservation,
    });
    assert.deepEqual(built.supabase.childDeletionCapabilityKeyring, TEST_KEYRING);
    assert.equal(built.supabase.destructiveCapabilityReservation, reservation);
    assert.deepEqual(inspectToolConfiguration(DELETE_TOOL), { configured: true, missing: [] });

    const connections = sanitizeProviderConnections({
      id: "github-test",
      label: "GitHub test",
      login: "github-test",
      allowMutations: false,
      grantedScopes: [],
      allowedRepositories: [],
    }, built.supabase);
    const serialized = JSON.stringify(connections);
    assert.doesNotMatch(serialized, new RegExp(TEST_SIGNING_KEY));
    assert.doesNotMatch(serialized, new RegExp(TEST_RESERVATION_KEY));
    assert.match(serialized, new RegExp(TEST_SIGNING_KEY_ID));
    assert.match(serialized, new RegExp(TEST_RESERVATION_KEY_ID));

    delete process.env.SUPABASE_CHILD_DELETION_CAPABILITY_KEYS_JSON;
    assert.deepEqual(inspectToolConfiguration(DELETE_TOOL), {
      configured: false,
      missing: ["SUPABASE_CHILD_DELETION_CAPABILITY_KEYS_JSON"],
    });

    process.env.SUPABASE_CHILD_DELETION_CAPABILITY_KEYS_JSON = JSON.stringify({
      activeKeyId: TEST_SIGNING_KEY_ID,
      reservationKeyId: TEST_SIGNING_KEY_ID,
      keys: { [TEST_SIGNING_KEY_ID]: TEST_SIGNING_KEY },
    });
    await assert.rejects(
      () => buildToolConfiguration(DELETE_TOOL),
      /Configuration missing for supabase/,
    );

    process.env.SUPABASE_CHILD_DELETION_CAPABILITY_KEYS_JSON = JSON.stringify({
      activeKeyId: TEST_SIGNING_KEY_ID,
      reservationKeyId: TEST_RESERVATION_KEY_ID,
      keys: {
        [TEST_SIGNING_KEY_ID]: TEST_SIGNING_KEY,
        [TEST_RESERVATION_KEY_ID]: TEST_SIGNING_KEY,
      },
    });
    await assert.rejects(
      () => buildToolConfiguration(DELETE_TOOL),
      /Configuration missing for supabase/,
    );
  } finally {
    for (const name of names) {
      if (saved[name] === undefined) delete process.env[name];
      else process.env[name] = saved[name];
    }
  }
});
