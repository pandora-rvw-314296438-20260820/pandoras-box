"use strict";

const assert = require("node:assert/strict");
const { test } = require("node:test");

const ORGANIZATION_ID = "2270b266-59da-4c39-bfd9-9f8d08352af0";
const USER_ID = "12345678-abcd-4f01-9345-6789abcdef01";
const INTAKE_ID = "a4c6e81c-89d0-4a63-9b8f-18e41bd2619a";
const PLAN_ID = "8ec3acda-4fb7-48b2-81f4-6885c005f561";
const DISPATCH_ID = "a6402a8a-4cbb-4812-80be-640028c81c5b";
const EXACT_SHA = "0123456789abcdef0123456789abcdef01234567";

async function subject() {
  return import("../supabase/functions/pandora-owner-api/command-pipeline.mjs");
}

function context(overrides = {}) {
  return {
    organizationId: ORGANIZATION_ID,
    userId: USER_ID,
    role: "owner",
    isAnonymous: false,
    ...overrides,
  };
}

function command(overrides = {}) {
  return {
    exactSha: EXACT_SHA,
    jobClass: "node_regression",
    ...overrides,
  };
}

async function exactPlan(overrides = {}) {
  const { normalizeWorkerCommand, workerPlanPayloadHash } = await subject();
  const args = normalizeWorkerCommand(command());
  return {
    planId: PLAN_ID,
    intakeId: INTAKE_ID,
    tool: "projectos.worker.verify",
    risk: "write",
    args,
    payloadHash: await workerPlanPayloadHash(args),
    status: "pending_approval",
    memoryContextRecorded: true,
    ...overrides,
  };
}

function adapter(overrides = {}) {
  const calls = { list: 0, create: 0, dispatch: 0 };
  return {
    calls,
    listPlans: async () => {
      calls.list += 1;
      return overrides.plans || [];
    },
    createPlan: async (payload) => {
      calls.create += 1;
      return {
        planId: PLAN_ID,
        status: "pending_approval",
        ...payload,
        ...(overrides.createdPlan || {}),
      };
    },
    getDispatch: async () => {
      calls.dispatch += 1;
      return overrides.dispatch || null;
    },
    ensurePlanContext: async () => overrides.contextRecorded !== false,
  };
}

async function run(adapterValue, commandValue = command()) {
  const { reconcileOwnerWorkerCommand } = await subject();
  return reconcileOwnerWorkerCommand({
    context: context(),
    intake: { id: INTAKE_ID, status: "accepted" },
    command: commandValue,
    adapter: adapterValue,
    now: new Date("2026-08-23T14:00:00.000Z"),
  });
}

test("owner worker command accepts only an explicit canonical exact-SHA job", async () => {
  const { normalizeWorkerCommand } = await subject();
  assert.deepEqual(normalizeWorkerCommand(command()), {
    exactSha: EXACT_SHA,
    jobClass: "node_regression",
    maxRuntimeSeconds: 1800,
    productionMutationAllowed: false,
    repository: "pandora-rvw-314296438-20260820/pandoras-box",
    schemaVersion: 1,
  });
  assert.throws(
    () => normalizeWorkerCommand(command({ repository: "attacker/fork" })),
    /NONCANONICAL_REPOSITORY/,
  );
  assert.throws(
    () => normalizeWorkerCommand(command({ exactSha: "main" })),
    /INVALID_EXACT_SHA/,
  );
  assert.throws(
    () => normalizeWorkerCommand(command({ jobClass: "arbitrary_shell" })),
    /INVALID_JOB_CLASS/,
  );
});

test("missing control adapter remains blocked and never claims completion", async () => {
  const result = await run(null);
  assert.equal(result.status.whereWeAre, "Blocked safely.");
  assert.equal(result.advanced.blockerCode, "WORKER_CONTROL_ADAPTER_UNAVAILABLE");
  assert.equal(result.proof.verified, false);
});

test("new command creates one write-risk plan and stops at approval", async () => {
  const control = adapter();
  const result = await run(control);
  assert.equal(control.calls.create, 1);
  assert.equal(control.calls.dispatch, 0);
  assert.equal(result.needsApproval, true);
  assert.equal(result.approvalId, PLAN_ID);
  assert.equal(result.proof.stage, "documented");
});

test("plan without fresh Pandora Memory context remains blocked before approval", async () => {
  const control = adapter({ contextRecorded: false });
  const result = await run(control);
  assert.equal(result.needsApproval, false);
  assert.equal(result.advanced.blockerCode, "MEMORY_CONTEXT_NOT_ATTACHED");
  assert.equal(result.advanced.planId, PLAN_ID);
});

test("idempotent replay finds the existing intake plan and does not create another", async () => {
  const plan = await exactPlan();
  const control = adapter({ plans: [plan] });
  const result = await run(control);
  assert.equal(control.calls.create, 0);
  assert.equal(result.approvalId, PLAN_ID);
});

test("multiple or identity-mismatched plans fail closed", async () => {
  const plan = await exactPlan();
  const duplicate = { ...plan, planId: "661f0457-30af-4470-ad19-2d915e071716" };
  const multiple = await run(adapter({ plans: [plan, duplicate] }));
  assert.equal(multiple.advanced.blockerCode, "MULTIPLE_PLANS_FOR_INTAKE");

  const mismatch = await run(adapter({
    plans: [{ ...plan, args: { ...plan.args, exactSha: "f".repeat(40) } }],
  }));
  assert.equal(mismatch.advanced.blockerCode, "PLAN_IDENTITY_MISMATCH");
});

test("approved but non-atomically-dispatched plan is reconciled, not blindly queued", async () => {
  const plan = await exactPlan({ status: "approved" });
  const control = adapter({ plans: [plan] });
  const result = await run(control);
  assert.equal(control.calls.dispatch, 0);
  assert.equal(result.advanced.blockerCode, "APPROVED_PLAN_NOT_ATOMICALLY_DISPATCHED");
});

test("executing plan requires a same-plan durable dispatch", async () => {
  const plan = await exactPlan({ status: "executing" });
  const missing = await run(adapter({ plans: [plan] }));
  assert.equal(missing.advanced.blockerCode, "PLAN_DISPATCH_BINDING_MISSING");

  const pending = await run(adapter({
    plans: [plan],
    dispatch: {
      dispatchId: DISPATCH_ID,
      planId: PLAN_ID,
      status: "queued",
    },
  }));
  assert.equal(pending.proof.stage, "implemented");
  assert.equal(pending.proof.verified, false);
  assert.equal(pending.advanced.dispatchId, DISPATCH_ID);
});

test("ambiguous dispatch blocks blind retry", async () => {
  const plan = await exactPlan({ status: "executing" });
  const result = await run(adapter({
    plans: [plan],
    dispatch: {
      dispatchId: DISPATCH_ID,
      planId: PLAN_ID,
      status: "ambiguous",
    },
  }));
  assert.equal(result.advanced.blockerCode, "AMBIGUOUS_DISPATCH");
  assert.equal(result.proof.ambiguous, true);
});

test("worker-attested results remain review-pending and never claim tested", async () => {
  const plan = await exactPlan({ status: "executing" });
  for (const status of ["result_reported", "finalizing"]) {
    const result = await run(adapter({
      plans: [plan],
      dispatch: {
        dispatchId: DISPATCH_ID,
        planId: PLAN_ID,
        status,
        evidenceSha256: "a".repeat(64),
      },
    }));
    assert.equal(result.proof.stage, "implemented");
    assert.equal(result.proof.verified, false);
    assert.equal(result.proof.attested, true);
    assert.equal(result.advanced.reviewPending, true);
    assert.equal(result.advanced.dispatchStatus, status);
    assert.match(result.reply, /attested and review-pending/i);
    assert.doesNotMatch(result.status.whereWeAre, /tested|completed/i);
    assert.equal(result.advanced.blockerCode, undefined);
  }
});

test("completed status is verified only with exact source and isolation evidence", async () => {
  const plan = await exactPlan({ status: "completed" });
  const good = await run(adapter({
    plans: [plan],
    dispatch: {
      dispatchId: DISPATCH_ID,
      planId: PLAN_ID,
      status: "completed",
      evidenceSha256: "a".repeat(64),
      verificationEvidenceId: "9f029dda-5c29-4e34-aaf1-59c20da2aa20",
      verifiedOutcome: "completed",
      verifiedAt: "2026-08-23T14:05:00.000Z",
      resultSummary: {
        repository: "pandora-rvw-314296438-20260820/pandoras-box",
        exactSha: EXACT_SHA,
        jobClass: "node_regression",
        exitCode: 0,
        isolation: "hyperv_container",
        networkPolicy: "none",
      },
    },
  }));
  assert.equal(good.proof.stage, "tested");
  assert.equal(good.proof.verified, true);
  assert.equal(good.proof.proofHash, "a".repeat(64));

  const bad = await run(adapter({
    plans: [plan],
    dispatch: {
      dispatchId: DISPATCH_ID,
      planId: PLAN_ID,
      status: "completed",
      evidenceSha256: "b".repeat(64),
      verificationEvidenceId: "9f029dda-5c29-4e34-aaf1-59c20da2aa20",
      verifiedOutcome: "completed",
      verifiedAt: "2026-08-23T14:05:00.000Z",
      resultSummary: {
        repository: "pandora-rvw-314296438-20260820/pandoras-box",
        exactSha: "f".repeat(40),
        jobClass: "node_regression",
        exitCode: 0,
        isolation: "host",
        networkPolicy: "open",
      },
    },
  }));
  assert.equal(bad.advanced.blockerCode, "COMPLETION_EVIDENCE_MISMATCH");
  assert.equal(bad.proof.verified, false);
});

test("anonymous and non-owner contexts fail before any adapter call", async () => {
  const { reconcileOwnerWorkerCommand } = await subject();
  const control = adapter();
  await assert.rejects(
    reconcileOwnerWorkerCommand({
      context: context({ isAnonymous: true }),
      intake: { id: INTAKE_ID },
      command: command(),
      adapter: control,
    }),
    /OWNER_OR_ADMIN_REQUIRED/,
  );
  assert.equal(control.calls.list, 0);
});
