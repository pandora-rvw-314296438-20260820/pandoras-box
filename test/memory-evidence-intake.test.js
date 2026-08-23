"use strict";

const test = require("node:test");
const assert = require("node:assert/strict");

const {
  EvidenceCandidateArgsSchema,
  EVIDENCE_CANDIDATE_SUBMIT_SCOPE,
  submitEvidenceCandidate,
  IDEMPOTENCY_CONFLICT_CODE,
} = require("../src/tools/memory-evidence-intake.js");
const { memoryTools } = require("../src/tools/memory.js");
const { getToolManifest } = require("../src/runtime/tool-manifest.js");
const { executeTool } = require("../src/runtime/tool-catalog.js");

const SHA40 = "0b6d32b9135e2050c4f819a8d7ac3c78e6bc1117";
const SHA256 = "4a10f26ebe4e760c984b89ecc741ba77ba0213dcad6205f3d1851a887f624545";
// Pandora Memory always resolves and returns the canonical project pair.
const CANONICAL_PROJECT_ID = "7c686cbd-d968-49d5-86cc-918f5e777bd2";
const CANONICAL_PROJECT_KEY = "mcpmaster-pandoras-box";

function validArgs() {
  return {
    namespace: "real_life",
    projectKey: "mcpmaster-pandoras-box",
    title: "Pandora Mobile owner-device read-only journey",
    summary: "Owner-operated Android journey verified installation, authentication, live reads, and primary read-only navigation.",
    proofStage: "tested",
    claim: "Physical Android authenticated read-only foundation is tested; merge, deployment, and production remain unverified.",
    evidenceRefs: [
      { type: "video_sha256", ref: SHA256, sha256: SHA256, artifact_class: "private-raw-evidence" },
      { type: "github_source", ref: "banataosystems/Pandoras-box#37@" + SHA40 },
    ],
    provenance: {
      source_type: "owner_device_recording",
      source_locator: "conversation-attachment:2908.mp4",
      source_sha: SHA40,
      observed_at: "2026-08-14T10:00:00+08:00",
    },
    idempotencyKey: "pandora-mobile:" + SHA40 + ":owner-device-readonly",
  };
}

const config = {
  baseUrl: "https://pandorasbox-memory.vercel.app",
  oidcToken: "test-oidc-xxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxx",
  allowedNamespaces: ["real_life"],
  grantedScopes: ["memory:read", EVIDENCE_CANDIDATE_SUBMIT_SCOPE],
  allowMutations: true,
  timeoutMs: 1000,
  maxResponseBytes: 100000,
};

function successBody(overrides = {}) {
  return {
    ok: true,
    candidate_id: "11111111-1111-4111-8111-111111111111",
    review_item_id: "22222222-2222-4222-8222-222222222222",
    status: "pending_review",
    idempotency_key: validArgs().idempotencyKey,
    namespace: "real_life",
    project_id: CANONICAL_PROJECT_ID,
    project_key: CANONICAL_PROJECT_KEY,
    proof_stage: "tested",
    deduplicated: false,
    created_at: "2026-08-14T11:00:00Z",
    canonical_memory_written: false,
    privacy_policy: "metadata_only_v1",
    ...overrides,
  };
}

function assertResponseContractFailure(error) {
  const failure = JSON.parse(error.message);
  assert.equal(error.status, 502);
  assert.equal(failure.safeErrorCode, "response_contract_error");
  assert.equal(failure.validationCategory, "response_contract");
  assert.equal(failure.retryable, false);
  return true;
}

test("candidate schema requires a project identity and exact proof stage", () => {
  const parsed = EvidenceCandidateArgsSchema.parse(validArgs());
  assert.equal(parsed.proofStage, "tested");
  assert.throws(() => EvidenceCandidateArgsSchema.parse({ ...validArgs(), projectKey: undefined }));
  assert.throws(() => EvidenceCandidateArgsSchema.parse({ ...validArgs(), proofStage: "done" }));
  assert.throws(() => EvidenceCandidateArgsSchema.parse({ ...validArgs(), summary: "x".repeat(1801) }));
});

test("memory tool and manifest expose candidate-scoped governed write semantics", () => {
  assert.ok(memoryTools["memory.submitEvidenceCandidate"]);
  const manifest = getToolManifest("memory.submitEvidenceCandidate");
  assert.equal(manifest.provider, "memory");
  assert.equal(manifest.risk, "write");
  assert.equal(manifest.mutation, true);
  assert.equal(EVIDENCE_CANDIDATE_SUBMIT_SCOPE, "memory:evidence-candidate:submit");
  assert.deepEqual(manifest.requiredProviderScopes, [EVIDENCE_CANDIDATE_SUBMIT_SCOPE]);
});

test("submission is bounded, OIDC-authenticated, and remains pending review", async () => {
  let observed;
  const result = await submitEvidenceCandidate(validArgs(), config, async (url, init) => {
    observed = { url, init, body: JSON.parse(init.body) };
    return new Response(JSON.stringify(successBody()), {
      status: 202,
      headers: { "content-type": "application/json" },
    });
  });

  assert.equal(observed.url, "https://pandorasbox-memory.vercel.app/api/projectos/memory/evidence-candidates");
  assert.equal(observed.init.method, "POST");
  assert.equal(observed.init.headers["x-pandora-vercel-oidc"], config.oidcToken);
  assert.equal(observed.body.proof_stage, "tested");
  assert.equal(result.status, "pending_review");
  assert.equal(result.canonicalPromoted, false);
  assert.equal(result.namespace, validArgs().namespace);
  assert.equal(result.projectKey, validArgs().projectKey);
  assert.equal(result.proofStage, validArgs().proofStage);
});

test("response identity and proof stage are bound to the submitted candidate", async () => {
  for (const [name, override] of [
    ["namespace", { namespace: "au" }],
    ["proof stage", { proof_stage: "production_verified" }],
    ["idempotency", { idempotency_key: "different-key-123456789" }],
    ["project key", { project_key: "memory" }],
  ]) {
    await assert.rejects(
      () => submitEvidenceCandidate(validArgs(), config, async () =>
        new Response(JSON.stringify(successBody(override)), { status: 202 })),
      assertResponseContractFailure,
      name,
    );
  }
});

test("server-resolved canonical project identity is returned once validated", async () => {
  const { projectKey, ...withoutKey } = validArgs();

  // projectKey-only input still learns the canonical server-resolved UUID.
  const byKey = await submitEvidenceCandidate(validArgs(), config, async () =>
    new Response(JSON.stringify(successBody()), { status: 202 }));
  assert.equal(byKey.projectId, CANONICAL_PROJECT_ID);
  assert.equal(byKey.projectKey, CANONICAL_PROJECT_KEY);

  // projectId-only input still learns the canonical server-resolved key.
  const byId = await submitEvidenceCandidate(
    { ...withoutKey, projectId: CANONICAL_PROJECT_ID },
    config,
    async () => new Response(JSON.stringify(successBody()), { status: 202 }),
  );
  assert.equal(byId.projectId, CANONICAL_PROJECT_ID);
  assert.equal(byId.projectKey, CANONICAL_PROJECT_KEY);

  // A matching id + key pair is accepted.
  const byBoth = await submitEvidenceCandidate(
    { ...validArgs(), projectId: CANONICAL_PROJECT_ID },
    config,
    async () => new Response(JSON.stringify(successBody()), { status: 202 }),
  );
  assert.equal(byBoth.projectId, CANONICAL_PROJECT_ID);
  assert.equal(byBoth.projectKey, CANONICAL_PROJECT_KEY);
});

test("substituted or malformed canonical project identity fails closed", async () => {
  const withId = { ...validArgs(), projectId: CANONICAL_PROJECT_ID };
  const { projectKey, ...idOnly } = withId;
  for (const [name, args, override] of [
    [
      "substituted project id",
      withId,
      { project_id: "43f619bb-ecc2-4a9a-bd56-424325eb81ac" },
    ],
    [
      "missing canonical project id",
      validArgs(),
      { project_id: null },
    ],
    [
      "malformed canonical project id",
      validArgs(),
      { project_id: "not-a-uuid" },
    ],
    [
      "malformed canonical project key",
      idOnly,
      { project_key: "NOT A KEY" },
    ],
    [
      "missing canonical project key",
      idOnly,
      { project_key: null },
    ],
  ]) {
    await assert.rejects(
      () => submitEvidenceCandidate(args, config, async () =>
        new Response(JSON.stringify(successBody(override)), { status: 202 })),
      assertResponseContractFailure,
      name,
    );
  }
});

test("backend 409 is classified as an explicit idempotency conflict", async () => {
  await assert.rejects(
    () => submitEvidenceCandidate(validArgs(), config, async () =>
      new Response(
        JSON.stringify({ ok: false, error: "idempotency_conflict", detail: "relation memory_capture_candidates" }),
        { status: 409 },
      )),
    (error) => {
      assert.equal(error.code, IDEMPOTENCY_CONFLICT_CODE);
      assert.match(error.message, /idempotency conflict/i);
      // The backend error body must never be echoed to the caller.
      assert.doesNotMatch(error.message, /memory_capture_candidates/);
      return true;
    },
  );

  // Transport, auth, and 5xx failures stay distinguishable from a conflict.
  for (const status of [401, 403, 500, 503]) {
    await assert.rejects(
      () => submitEvidenceCandidate(validArgs(), config, async () =>
        new Response(JSON.stringify({ ok: false, error: "nope" }), { status })),
      (error) => {
        assert.equal(error.code, undefined);
        assert.match(error.message, new RegExp(`submission failed \\(${status}\\)`));
        return true;
      },
      `status ${status}`,
    );
  }
});

test("Memory marks only contract-proven rejections as pre-side-effect outcomes", async () => {
  for (const [status, body] of [
    [408, { ok: false, error: "provider_timeout" }],
    [429, { ok: false, error: "provider_rate_limited" }],
    [500, { ok: false, error: "provider_server_error" }],
    [200, { ok: false, error: "evidence_candidate_invalid" }],
  ]) {
    await assert.rejects(
      () => submitEvidenceCandidate(validArgs(), config, async () =>
        new Response(JSON.stringify(body), { status })),
      (error) => {
        assert.equal(error.providerOutcome, "ambiguous", `HTTP ${status}`);
        return true;
      },
    );
  }

  await assert.rejects(
    () => submitEvidenceCandidate(validArgs(), config, async () =>
      new Response(JSON.stringify({ ok: false, error: "evidence_candidate_invalid" }), {
        status: 400,
      })),
    (error) => {
      assert.equal(error.providerOutcome, "failed_before_side_effects");
      return true;
    },
  );
});

test("a positive 2xx acknowledgement remains provider success when local response validation fails", async () => {
  await assert.rejects(
    () => submitEvidenceCandidate(validArgs(), config, async () =>
      new Response(JSON.stringify({ ok: true, status: "malformed" }), { status: 200 })),
    (error) => {
      assert.equal(error.providerOutcome, "succeeded");
      assertResponseContractFailure(error);
      return true;
    },
  );
});

test("direct identifiers and credential signatures are rejected before network I/O", async () => {
  let called = false;
  const fetchFn = async () => { called = true; throw new Error("must not call"); };
  await assert.rejects(
    () => submitEvidenceCandidate({ ...validArgs(), summary: "owner email owner@example.com" }, config, fetchFn),
    /direct_identifier_email/,
  );
  await assert.rejects(
    () => submitEvidenceCandidate({ ...validArgs(), summary: "token sk_example123456789012345" }, config, fetchFn),
    /credential_signature/,
  );
  assert.equal(called, false);
});

test("privacy boundary rejects broader identifiers, secrets, nesting, and encoded variants before I/O", async () => {
  const attacks = [
    [{ ...validArgs(), summary: "contact +63 917 123 4567" }, /direct_identifier_phone/],
    [{ ...validArgs(), summary: "name: Jane Doe" }, /direct_identifier_name/],
    [{ ...validArgs(), summary: "office 123 Rizal Street, Makati" }, /direct_identifier_address/],
    [{ ...validArgs(), claim: "password=hunter2-super-secret" }, /secret_assignment/],
    [{ ...validArgs(), claim: "AWS_SECRET_ACCESS_KEY=wJalrXUtnFEMI\/K7MDENG\/bPxRfiCYEXAMPLEKEY" }, /secret_assignment/],
    [{ ...validArgs(), claim: "AKIAIOSFODNN7EXAMPLE" }, /cloud_credential_signature/],
    [{ ...validArgs(), claim: "-----BEGIN PRIVATE KEY-----" }, /private_key_material/],
    [{ ...validArgs(), provenance: { ...validArgs().provenance, source_locator: "owner%40example.com" } }, /direct_identifier_email/],
    [{ ...validArgs(), provenance: { ...validArgs().provenance, source_locator: "owner＠example.com" } }, /direct_identifier_email/],
    [{ ...validArgs(), evidenceRefs: [{ ...validArgs().evidenceRefs[0], ref: "phone%3A%20%2B63%20917%20123%204567" }] }, /direct_identifier_phone/],
  ];
  for (const [args, expected] of attacks) {
    let called = false;
    await assert.rejects(
      () => submitEvidenceCandidate(args, config, async () => {
        called = true;
        throw new Error("must not call");
      }),
      expected,
    );
    assert.equal(called, false);
  }
});

test("candidate-submit scope is fail-closed and broad memory write alone is rejected", async () => {
  await assert.rejects(
    () => submitEvidenceCandidate(validArgs(), { ...config, grantedScopes: ["memory:read"] }, async () => {
      throw new Error("must not call");
    }),
    /evidence-candidate submit scope is not granted/,
  );

  await assert.rejects(
    () => submitEvidenceCandidate(validArgs(), { ...config, grantedScopes: ["memory:write"] }, async () => {
      throw new Error("must not call");
    }),
    /evidence-candidate submit scope is not granted/,
  );

  await assert.rejects(
    () => submitEvidenceCandidate(validArgs(), config, async () =>
      new Response(JSON.stringify({ ok: true, status: "hard_canon" }), { status: 200 })),
    assertResponseContractFailure,
  );
});

test("governed executeTool path requires explicit mutation plus candidate-submit scope", async () => {
  const toolConfig = { memory: { ...config } };

  await assert.rejects(
    () => executeTool("memory.submitEvidenceCandidate", validArgs(), {
      memory: { ...config, allowMutations: false },
    }),
    /Memory mutations are disabled/,
  );

  await assert.rejects(
    () => executeTool("memory.submitEvidenceCandidate", validArgs(), {
      memory: { ...config, grantedScopes: ["memory:read", "memory:write"] },
    }),
    /missing required scope.*memory:evidence-candidate:submit/,
  );

  const originalFetch = globalThis.fetch;
  let called = false;
  globalThis.fetch = async () => {
    called = true;
    return new Response(JSON.stringify(successBody()), { status: 202 });
  };
  try {
    const result = await executeTool(
      "memory.submitEvidenceCandidate",
      validArgs(),
      toolConfig,
    );
    assert.equal(result.status, "pending_review");
    assert.equal(result.canonicalPromoted, false);
    assert.equal(called, true);
  } finally {
    globalThis.fetch = originalFetch;
  }
});

test("governed namespace enforcement also covers the write path", async () => {
  await assert.rejects(
    () => executeTool("memory.submitEvidenceCandidate", validArgs(), {
      memory: { ...config, allowedNamespaces: ["au"] },
    }),
    /namespace is not allowed: real_life/,
  );
});
