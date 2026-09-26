"use strict";
const test = require("node:test"), assert = require("node:assert/strict");
const { OperationsConnectorRuntime, createOperationsWakeHandler, projectStatuses } = require("../packages/pandora-operations-connectors/runtime.cjs");
const { normalizeTask, digest } = require("../packages/pandora-operations-room/contracts");
const scope = { organizationId: "00000000-0000-4000-8000-000000000001", projectId: "00000000-0000-4000-8000-000000000002" };
const spec = normalizeTask({ id: "real-shape-fixture", title: "Synthetic source integration case", lane: "backend", priority: 0,
  dependsOn: [], resources: [{ key: "source/fixture", mode: "write" }], requiredCapabilities: ["source.write"], maxCostMicros: 0,
  maxDurationSeconds: 60, maxAttempts: 2, risk: "source", acceptance: ["fixture tests"], source: { repository: "pandora-rvw-314296438-20260820/pandoras-box", baseSha: "a".repeat(40) } });
function fixture({ lostIntake = false, changedSpec = false } = {}) {
  const state = { controls: { paused: true, noProduction: true, revision: 0, maxConcurrency: 1 }, budget: { availableMicros: 0 },
    workers: [], tasks: [], leases: [], foreignLeases: [] };
  const calls = [];
  const client = { async rpc(name, args) {
    calls.push({ name, args });
    if (name === "pandora_ops_snapshot_v1") return { data: structuredClone(state), error: null };
    if (name === "pandora_ops_ingest_v1") {
      state.tasks = args.p_tasks.map((s) => ({ spec: changedSpec ? { ...s, title: "changed" } : s, status: "queued", generation: 0, revision: 0, attempt: 0, queuedAt: Date.now() }));
      if (lostIntake) throw new Error("lost committed response");
      return { data: { accepted: args.p_tasks.length }, error: null };
    }
    throw new Error(`Unexpected fixture RPC ${name}`);
  } };
  let statuses;
  const intake = { tasks: [spec], sourceDigest: digest("owner inputs"), bindingDigest: digest("fixed native target") };
  const sheets = { async ingest() { return intake; }, async writeback(sourceDigest, s) {
    statuses = s; return { verified: true, sourceDigest, bindingDigest: intake.bindingDigest };
  } };
  const runtime = new OperationsConnectorRuntime({ scope, client, sheets });
  return { runtime, state, calls, client, statuses: () => statuses };
}
test("Runtime preserves paused/no-production state and does not invent worker capacity", async () => {
  const f = fixture(); const result = await f.runtime.runOnce();
  assert.equal(result.controls.paused, true); assert.equal(result.enrolledWorkers, 0);
  assert.equal(result.configuredTransports, 0); assert.equal(result.verifiedComplete, false);
  assert.ok(f.calls.every((c) => c.name === "pandora_ops_snapshot_v1"));
});
test("Runtime executes normalized Sheet intake, immutable-spec readback and safe status writeback", async () => {
  const f = fixture(); const result = await f.runtime.synchronizeSheet();
  assert.equal(result.tasksVerified, 1); assert.equal(result.sheetReadbackVerified, true);
  assert.equal(f.statuses()[0].STATUS, "QUEUED"); assert.equal(f.statuses()[0].VERIFICATION, "Not complete");
});
test("Runtime reconciles a lost intake response by readback rather than repeat ingestion", async () => {
  const f = fixture({ lostIntake: true }); const result = await f.runtime.synchronizeSheet();
  assert.equal(result.mutationAcknowledged, false);
  assert.equal(f.calls.filter((c) => c.name === "pandora_ops_ingest_v1").length, 1);
});
test("Runtime refuses to publish status when database task content differs from Sheet intent", async () => {
  const f = fixture({ changedSpec: true });
  await assert.rejects(() => f.runtime.synchronizeSheet(), /INGEST_READBACK_MISMATCH/);
  assert.equal(f.statuses(), undefined);
});
test("Configured transport does not automatically enroll a worker", async () => {
  const f = fixture();
  const runtime = new OperationsConnectorRuntime({ scope, client: f.client, workers: [{ binding: { ...scope,
    workerId: "fixture-worker", principalKey: "fixture-principal", channelId: "agtch_fixture" },
    getAccessToken: () => "fixture-only-credential", getSigningKey: () => Buffer.alloc(32, 7),
    fetchImpl: () => { throw new Error("Must not call a provider without enrollment"); } }] });
  const result = await runtime.runOnce();
  assert.equal(result.enrolledWorkers, 0); assert.equal(result.configuredTransports, 1);
  assert.equal(result.receipts.length, 0);
});
test("Runtime rejects duplicate and foreign worker bindings", () => {
  const f = fixture();
  assert.throws(() => new OperationsConnectorRuntime({ scope, client: f.client,
    workers: [{ binding: { ...scope, projectId: "foreign" } }] }), /SCOPE_DENIED/);
  assert.throws(() => f.runtime.callback("unknown"), /NOT_CONFIGURED/);
});
test("Status projection only exposes a real canonical completion state", () => {
  const states = ["queued", "claimed", "implementing", "handed_off", "verifying", "complete", "blocked", "failed", "cancelled"];
  for (const status of states) {
    const projected = projectStatuses({ tasks: [{ spec, status, generation: 1 }], leases: [] }, [spec.id], "2026-09-26T00:00:00Z")[0];
    assert.equal(projected.STATUS, status.toUpperCase());
    assert.equal(projected.VERIFICATION === "Canonical Operations completion recorded", status === "complete");
  }
});
test("Status projection rejects unknown tasks and ambiguous active leases", () => {
  assert.throws(() => projectStatuses({ tasks: [], leases: [] }, [spec.id], "now"), /UNVERIFIED/);
  assert.throws(() => projectStatuses({ tasks: [{ spec, status: "implementing", generation: 1 }],
    leases: [{ taskId: spec.id, generation: 1 }, { taskId: spec.id, generation: 1 }] }, [spec.id], "now"), /AMBIGUOUS/);
});
test("Wake endpoint requires its own server token and cannot change the fixed scope", async () => {
  const f = fixture(), token = "w".repeat(40);
  const handler = createOperationsWakeHandler({ runtime: f.runtime, getWakeToken: () => token });
  assert.equal((await handler(new Request("https://fixture.invalid/wake"))).status, 401);
  const success = await handler(new Request("https://fixture.invalid/wake", { headers: { authorization: `Bearer ${token}` } }));
  assert.equal(success.status, 200); assert.equal((await success.json()).verifiedComplete, false);
  const unsafe = new Request("https://fixture.invalid/wake", { method: "POST", headers: { authorization: `Bearer ${token}` }, body: JSON.stringify({ projectId: "other" }) });
  assert.equal((await handler(unsafe)).status, 401);
});
test("Wake endpoint refuses a browser origin", async () => {
  const f = fixture(); const handler = createOperationsWakeHandler({ runtime: f.runtime, getWakeToken: () => "w".repeat(40) });
  assert.equal((await handler(new Request("https://fixture.invalid/wake", { headers: { origin: "https://example.invalid" } }))).status, 403);
});
