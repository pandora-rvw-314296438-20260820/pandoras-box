"use strict";
const test = require("node:test");
const assert = require("node:assert/strict");
const fs = require("node:fs"), path = require("node:path");
const { createHash } = require("node:crypto");
const { NativeJsonClient } = require("../packages/pandora-operations-connectors/http.cjs");
const { WorkspaceAgentClient } = require("../packages/pandora-operations-connectors/workspace-agents.cjs");
const { OperationsConnectorRuntime, createOperationsWakeHandler } = require("../packages/pandora-operations-connectors/runtime.cjs");
const binding = { organizationId: "00000000-0000-4000-8000-000000000001", projectId: "00000000-0000-4000-8000-000000000002", workerId: "fixture-worker", principalKey: "fixture-principal", channelId: "agtch_fixture" };
for (const key of ["workerId", "principalKey"]) {
  for (const value of [undefined, null, 123]) test(`Worker binding rejects coerced ${key}:${String(value)}`, () => {
    assert.throws(() => new WorkspaceAgentClient({ binding: { ...binding, [key]: value }, getAccessToken: () => "fixture-token" }), /BINDING_INVALID/);
  });
}
test("Worker envelope rejects a missing task ID instead of accepting the string undefined", () => {
  const client = new WorkspaceAgentClient({ binding, getAccessToken: () => "fixture-token" });
  assert.throws(() => client.envelope({ organizationId: binding.organizationId, projectId: binding.projectId, workerId: binding.workerId, principalKey: binding.principalKey,
    taskId: undefined, dispatchId: "00000000-0000-4000-8000-000000000003", leaseId: "00000000-0000-4000-8000-000000000004", generation: 1 }), /DISPATCH_INVALID/);
});
test("HTTP deadline actively cancels an unresponsive response stream", async () => {
  let cancelled = false;
  const client = new NativeJsonClient({ origin: "https://api.chatgpt.com", getToken: () => "fixture-token", timeoutMs: 15,
    fetchImpl: async () => new Response(new ReadableStream({ start(c) { c.enqueue(new TextEncoder().encode("{")); }, cancel() { cancelled = true; } }),
      { headers: { "content-type": "application/json" } }) });
  await assert.rejects(() => client.request("/v1/fixture", { method: "POST" }), /DEADLINE/);
  await new Promise((resolve) => setImmediate(resolve));
  assert.equal(cancelled, true);
});
test("Wake authentication requires Bearer syntax and rejects Unicode without leaking exceptions", async () => {
  const client = { async rpc() { return { data: { controls: { paused: true, noProduction: true }, workers: [], tasks: [], leases: [], foreignLeases: [], budget: { availableMicros: 0 } }, error: null }; } };
  const runtime = new OperationsConnectorRuntime({ scope: { organizationId: binding.organizationId, projectId: binding.projectId }, client });
  const token = "w".repeat(40);
  const handler = createOperationsWakeHandler({ runtime, getWakeToken: () => token });
  for (const authorization of [token, `Basic ${token}`, "Bearer " + "é".repeat(40)]) {
    const result = await handler(new Request("https://fixture.invalid/wake", { headers: { authorization } }));
    assert.equal(result.status, 401);
    assert.deepEqual(await result.json(), { code: "OPS_WAKE_DENIED" });
  }
});
test("The real CLI-generated migration is byte-identical to tested delivery SQL", () => {
  const root = path.join(__dirname, "..");
  const source = fs.readFileSync(path.join(root, "packages/pandora-operations-connectors/delivery-schema.sql"));
  const migration = fs.readFileSync(path.join(root, "supabase/migrations/20260925235431_operations_connector_delivery_v1.sql"));
  assert.deepEqual(migration, source);
  assert.equal(createHash("sha256").update(migration).digest("hex"), "472a9c0a8ddd7e3c86da5ef0604dd078a418d1489bd926466353049069db4223");
});

test("Connector CI watches native dependencies and its own workflow on PR and main", () => {
  const workflow = fs.readFileSync(path.join(__dirname, "../.github/workflows/operations-connectors.yml"), "utf8");
  const pull = workflow.split("  pull_request:\n")[1].split("  push:\n")[0];
  const push = workflow.split("  push:\n")[1].split("  workflow_dispatch:")[0];
  for (const section of [pull, push]) {
    for (const dependency of ["packages/pandora-operations-room/**", "packages/pandora-verification/**", "supabase/migrations/**", "package-lock.json", ".github/workflows/operations-connectors.yml"])
      assert.ok(section.includes(`'${dependency}'`), `Missing dependency filter ${dependency}`);
  }
});
