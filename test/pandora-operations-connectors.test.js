"use strict";
const test = require("node:test");
const assert = require("node:assert/strict");
const { NativeJsonClient, bounded } = require("../packages/pandora-operations-connectors/http.cjs");
const { WorkspaceAgentClient, workerDispatch, RUN_STATES } = require("../packages/pandora-operations-connectors/workspace-agents.cjs");
const { GoogleSheetsConnector } = require("../packages/pandora-operations-connectors/google-sheets.cjs");
const { digest } = require("../packages/pandora-operations-room/contracts");
const { INPUT_COLUMNS, OUTPUT_COLUMNS } = require("../packages/pandora-operations-room/sheet-adapter");
const credential = () => "fixture-only-credential";
const json = (data, status = 200) => new Response(JSON.stringify(data), {
  status, headers: { "content-type": "application/json" },
});
function http(fetchImpl, options = {}) {
  return new NativeJsonClient({ origin: "https://api.chatgpt.com", getToken: credential,
    fetchImpl, ...options });
}
const binding = Object.freeze({ organizationId: "00000000-0000-4000-8000-000000000001",
  projectId: "00000000-0000-4000-8000-000000000002", workerId: "fixture-worker",
  principalKey: "fixture-principal", channelId: "agtch_fixture" });
const raw = Object.freeze({ organizationId: binding.organizationId, projectId: binding.projectId,
  workerId: binding.workerId, principalKey: binding.principalKey, taskId: "fixture-task",
  dispatchId: "00000000-0000-4000-8000-000000000003",
  leaseId: "00000000-0000-4000-8000-000000000004", generation: 1 });
const trigger = { agent_trigger_run_id: "apirun_fixture", conversation_url: "https://chatgpt.com/c/fixture" };
function agent(fetchImpl, options = {}) {
  return new WorkspaceAgentClient({ binding, getAccessToken: credential, fetchImpl, ...options });
}

test("HTTP accepts only the registered HTTPS origins", () => {
  for (const origin of ["http://api.chatgpt.com", "https://attacker.invalid", "https://api.chatgpt.com.attacker.invalid"])
    assert.throws(() => new NativeJsonClient({ origin, getToken: credential }), /ORIGIN_DENIED/);
});
for (const path of ["https://attacker.invalid", "//attacker.invalid", "/\\evil", "/x\nAuthorization:x", "/x#fragment"])
  test(`HTTP rejects unsafe path ${JSON.stringify(path)}`, async () => {
    let calls = 0;
    await assert.rejects(() => http(async () => { calls++; }).request(path), /DENIED/);
    assert.equal(calls, 0);
  });
test("HTTP denies caller authorization and unsupported verbs", async () => {
  const client = http(async () => json({}));
  await assert.rejects(() => client.request("/x", { headers: { Authorization: "override" } }), /HEADER_DENIED/);
  await assert.rejects(() => client.request("/x", { method: "DELETE" }), /METHOD_DENIED/);
});
test("HTTP sends token only as an authorization header and disables redirects", async () => {
  let request;
  const result = await http(async (url, init) => { request = { url, init }; return json({ ok: true }); }).request("/x");
  assert.equal(request.url, "https://api.chatgpt.com/x");
  assert.equal(request.init.redirect, "error");
  assert.equal(request.init.headers.authorization, `Bearer ${credential()}`);
  assert.deepEqual(result, { status: 200, data: { ok: true } });
  assert.ok(!JSON.stringify(result).includes(credential()));
});
test("HTTP pre-abort prevents credential use and provider execution", async () => {
  const abort = new AbortController(); abort.abort(); let calls = 0;
  await assert.rejects(() => http(async () => { calls++; }).request("/x", { signal: abort.signal }), /CANCELLED/);
  assert.equal(calls, 0);
});
test("HTTP bounds an unresponsive credential loader before dispatch", async () => {
  let calls = 0;
  const client = http(async () => { calls++; }, { getToken: () => new Promise(() => {}), timeoutMs: 15 });
  await assert.rejects(() => client.request("/x", { method: "POST" }), (e) => e.code === "CONNECTOR_DEADLINE" && !e.outcomeUnknown);
  assert.equal(calls, 0);
});
test("HTTP does not send when a credential loader resolves after the deadline", async () => {
  let calls = 0;
  await assert.rejects(() => http(async () => { calls++; }, { getToken: () => new Promise((r) => setTimeout(() => r(credential()), 35)), timeoutMs: 10 }).request("/x"), /DEADLINE/);
  await new Promise((r) => setTimeout(r, 45));
  assert.equal(calls, 0);
});
test("HTTP bounds response streaming, not only response headers", async () => {
  const client = http(async () => new Response(new ReadableStream({ start(c) { c.enqueue(new TextEncoder().encode("{")); } }), { headers: { "content-type": "application/json" } }), { timeoutMs: 15 });
  await assert.rejects(() => client.request("/x", { method: "POST" }), (e) => e.code === "CONNECTOR_DEADLINE" && e.outcomeUnknown);
});
test("HTTP preserves uncertainty after mutation network loss and does not retry", async () => {
  let calls = 0;
  const client = http(async () => { calls++; throw new Error(`secret ${credential()}`); });
  await assert.rejects(() => client.request("/x", { method: "POST" }), (e) =>
    e.code === "CONNECTOR_NETWORK_FAILURE" && e.outcomeUnknown && !e.message.includes(credential()));
  assert.equal(calls, 1);
});
test("HTTP redacts credential-loader failures", async () => {
  await assert.rejects(() => http(async () => json({}), { getToken: () => { throw new Error(credential()); } }).request("/x"),
    (e) => e.code === "CONNECTOR_CREDENTIAL_UNAVAILABLE" && !e.message.includes(credential()));
});
for (const status of [301, 401, 403, 429, 500])
  test(`HTTP rejects and redacts provider status ${status}`, async () => {
    await assert.rejects(() => http(async () => json({ secret: credential() }, status)).request("/x"),
      (e) => e.status === status && e.code === "CONNECTOR_HTTP_FAILURE" && !e.message.includes(credential()));
  });
test("HTTP enforces measured body bounds without Content-Length", async () => {
  await assert.rejects(() => http(async () => json({ big: "x".repeat(100) }), { maxBytes: 20 }).request("/x"), /TOO_LARGE/);
});
test("HTTP enforces declared response size before reading", async () => {
  await assert.rejects(() => http(async () => new Response("{}", { headers: { "content-type": "application/json", "content-length": "9000" } }), { maxBytes: 20 }).request("/x"), /TOO_LARGE/);
});
test("HTTP rejects non-JSON and malformed JSON", async () => {
  for (const response of [new Response("<html>"), new Response("{", { headers: { "content-type": "application/json" } })])
    await assert.rejects(() => http(async () => response).request("/x"), /RESPONSE_INVALID/);
});
test("HTTP supports empty 204 without JSON parsing", async () => {
  assert.deepEqual(await http(async () => new Response(null, { status: 204 })).request("/x"), { status: 204, data: null });
});
test("Bounded operation cleans up the timer on success", async () => {
  assert.equal(await bounded(async () => 4, { timeoutMs: 100 }), 4);
});

test("Workspace channel is required and a platform key is rejected", async () => {
  assert.throws(() => agent(async () => json(trigger, 202), { binding: { ...binding, channelId: "agt_fake" } }), /BINDING_INVALID/);
  await assert.rejects(() => agent(async () => json(trigger, 202), { getAccessToken: () => "sk-" + "x".repeat(40) }).trigger(raw, "task"), /CREDENTIAL_UNAVAILABLE/);
});
for (const field of ["organizationId", "projectId", "workerId", "principalKey"])
  test(`Workspace rejects a foreign ${field} before provider I/O`, async () => {
    let calls = 0;
    await assert.rejects(() => agent(async () => { calls++; }).trigger({ ...raw, [field]: "foreign" }, "task"), /SCOPE_DENIED/);
    assert.equal(calls, 0);
  });
for (const generation of [0, -1, 1.5, Number.MAX_SAFE_INTEGER + 1])
  test(`Workspace rejects generation ${generation}`, async () => {
    await assert.rejects(() => agent(async () => json(trigger, 202)).trigger({ ...raw, generation }, "task"), /GENERATION_INVALID/);
  });
test("Workspace rejects oversized input and credential material", async () => {
  const client = agent(async () => json(trigger, 202));
  for (const input of ["", "x".repeat(16385), "Bearer " + "s".repeat(40), "github_pat_" + "s".repeat(40)])
    await assert.rejects(() => client.trigger(raw, input), /INPUT_REJECTED/);
});
test("Workspace queue receipt is never a worker ACK or task completion", async () => {
  let request;
  const receipt = await agent(async (url, init) => { request = { url, init }; return json(trigger, 202); }).trigger(raw, "approved task");
  assert.equal(request.url, `https://api.chatgpt.com/v1/workspace_agents/${binding.channelId}/trigger`);
  assert.equal(request.init.headers["OpenAI-Beta"], "workspace_agent_runs=v1");
  assert.equal(receipt.state, "provider_queued");
  assert.equal(receipt.workerAcknowledged, false);
  assert.equal(receipt.taskComplete, false);
  assert.equal(receipt.runId, "apirun_fixture");
});
test("Workspace binds retry identity to scope, generation and exact input", async () => {
  const keys = [];
  const client = agent(async (_, init) => { keys.push(init.headers["Idempotency-Key"]); return json(trigger, 202); });
  await client.trigger(raw, "task A"); await client.trigger(raw, "task A");
  await client.trigger(raw, "task B"); await client.trigger({ ...raw, generation: 2 }, "task A");
  assert.equal(keys[0], keys[1]); assert.notEqual(keys[0], keys[2]); assert.notEqual(keys[0], keys[3]);
});
for (const bad of [{ ...trigger, agent_trigger_run_id: "unknown" }, { ...trigger, conversation_url: "https://attacker.invalid/c/x" }])
  test(`Workspace rejects malformed queue receipt ${Object.keys(bad).join(",")}:${bad.agent_trigger_run_id}`, async () => {
    await assert.rejects(() => agent(async () => json(bad, 202)).trigger(raw, "task"), /INVALID/);
  });
for (const state of RUN_STATES)
  test(`Workspace provider state ${state} does not establish Pandora completion`, async () => {
    const client = agent(async (url) => url.endsWith("/trigger") ? json(trigger, 202) : json({ object: "workspace_agent.trigger_run", id: trigger.agent_trigger_run_id,
      api_trigger_id: binding.channelId, status: state, conversation_url: trigger.conversation_url }));
    const receipt = await client.trigger(raw, "task");
    const result = await client.status(receipt);
    assert.equal(result.state, state); assert.equal(result.taskComplete, false);
    assert.equal(result.terminal, ["completed", "failed"].includes(state));
  });
test("Workspace status verifies channel and run identity", async () => {
  const client = agent(async (url) => url.endsWith("/trigger") ? json(trigger, 202) : json({ object: "workspace_agent.trigger_run", id: trigger.agent_trigger_run_id,
    api_trigger_id: "agtch_other", status: "completed", conversation_url: trigger.conversation_url }));
  await assert.rejects(() => client.trigger(raw, "task").then((r) => client.status(r)), /READBACK_MISMATCH/);
});
function dispatchFixture({ acknowledged = false, allowed = true, triggerFails = false } = {}) {
  let sends = 0; let record = null; let unknown = 0;
  const client = agent(async () => { sends++; if (triggerFails) throw new Error("transport loss"); return json(trigger, 202); });
  const journal = { durability: "durable", // Isolated contract fixture, never production evidence.
    async prepare(envelope, requestDigest) {
      if (!record) { record = { envelope, requestDigest }; return { canSend: true, requestDigest }; }
      return { canSend: false, requestDigest: record.requestDigest };
    },
    async recordDelivery(_, receipt) { record.receipt = receipt; },
    async markUnknown() { unknown++; }, async read() { return record; },
  };
  const run = workerDispatch({ client, journal, getInput: async () => "fixture task",
    authorizeSend: async (envelope) => ({ allowed, envelopeDigest: digest(envelope) }),
    readAcknowledgement: async (envelope, receipt) => acknowledged ? ({ authenticated: true,
      principalKey: binding.principalKey, runId: receipt.runId, envelopeDigest: digest(envelope),
      accepted: true, receiptRef: "fixture:authenticated-receipt" }) : null });
  const args = { scope: { organizationId: raw.organizationId, projectId: raw.projectId },
    claim: { workerId: raw.workerId, taskId: raw.taskId, leaseId: raw.leaseId, generation: 1 }, dispatchId: raw.dispatchId };
  return { run, args, counts: () => ({ sends, unknown }) };
}
test("Dispatch does not turn queued provider work into an ACK", async () => {
  const fixture = dispatchFixture();
  await assert.rejects(() => fixture.run(fixture.args), /ACK_PENDING/);
  await assert.rejects(() => fixture.run(fixture.args), /ACK_PENDING/);
  assert.equal(fixture.counts().sends, 1);
});
test("Dispatch returns ACK only from an authenticated exact-bound receipt", async () => {
  const fixture = dispatchFixture({ acknowledged: true });
  const ack = await fixture.run(fixture.args);
  assert.equal(ack.accepted, true); assert.equal(ack.taskId, raw.taskId);
  assert.equal(ack.generation, 1);
});
test("Dispatch refuses send after controls revoke admission", async () => {
  const fixture = dispatchFixture({ allowed: false });
  await assert.rejects(() => fixture.run(fixture.args), /RECONCILIATION_REQUIRED/);
  assert.deepEqual(fixture.counts(), { sends: 0, unknown: 1 });
});
test("Dispatch preserves an uncertain remote delivery without replay", async () => {
  const fixture = dispatchFixture({ triggerFails: true });
  await assert.rejects(() => fixture.run(fixture.args), /RECONCILIATION_REQUIRED/);
  await assert.rejects(() => fixture.run(fixture.args), /UNCONFIRMED/);
  assert.deepEqual(fixture.counts(), { sends: 1, unknown: 1 });
});

const headers = [...INPUT_COLUMNS, ...OUTPUT_COLUMNS];
function sheetFixture(options = {}) {
  const b = { spreadsheetId: "fixture_workbook_123", sheetId: 108, headerRow: 5, maxRows: 20, maxColumns: headers.length };
  const values = { TASK_ID: "T1", TITLE: "Fixture source task", LANE: "backend", PRIORITY: "0", DEPENDS_ON: "", RESOURCES: "source/fixture|write",
    CAPABILITIES: "source.write", MAX_COST_MICROS: "0", MAX_DURATION_SECONDS: "60", MAX_ATTEMPTS: "2", RISK: "source", ACCEPTANCE: "exact source tests",
    REPOSITORY: "pandora-rvw-314296438-20260820/pandoras-box", BASE_SHA: "a".repeat(40), STATUS: "QUEUED" };
  const cell = (v) => ({ userEnteredValue: { stringValue: v ?? "" } });
  const rows = [headers.map(cell), headers.map((h) => cell(values[h]))];
  let reads = 0; let writes = 0; const requests = [];
  const fetchImpl = async (url, init) => {
    const body = JSON.parse(init.body);
    if (url.includes(":getByDataFilter")) {
      reads++;
      options.onRead?.(rows, reads);
      return json({ spreadsheetId: b.spreadsheetId, sheets: [{ properties: { sheetId: b.sheetId, title: "Tasks", gridProperties: { rowCount: 100, columnCount: headers.length } },
        data: [{ startRow: b.headerRow - 1, startColumn: 0, rowData: rows.map((r) => ({ values: r })) }] }] });
    }
    assert.ok(url.endsWith(":batchUpdate")); writes++;
    for (const request of body.requests) {
      requests.push(request);
      const update = request.updateCells;
      assert.equal(update.fields, "userEnteredValue");
      assert.equal(update.start.sheetId, b.sheetId);
      rows[update.start.rowIndex - (b.headerRow - 1)][update.start.columnIndex].userEnteredValue = update.rows[0].values[0].userEnteredValue;
    }
    options.afterWrite?.(rows);
    if (options.lostResponse) throw new Error("response lost after write");
    return json({ spreadsheetId: b.spreadsheetId, replies: body.requests.map(() => ({})) });
  };
  return { client: new GoogleSheetsConnector({ binding: b, getAccessToken: credential, fetchImpl }),
    rows, requests, b, counts: () => ({ reads, writes }) };
}
test("Sheets reads fixed native sheetId and ingests the existing task contract", async () => {
  const f = sheetFixture(); const result = await f.client.ingest();
  assert.equal(result.tasks.length, 1); assert.equal(result.tasks[0].id, "T1");
  assert.equal(result.tasks[0].maxCostMicros, 0);
});
test("Sheets applies literal machine-column values with correct non-first header offset", async () => {
  const f = sheetFixture(); const before = await f.client.read();
  const result = await f.client.writeback(before.sourceDigest, [{ taskId: "T1", STATUS: "IMPLEMENTING", BLOCKER: "=not a formula" }]);
  assert.equal(result.verified, true); assert.equal(result.transactionalCompareAndSwap, false);
  assert.equal(f.requests[0].updateCells.start.rowIndex, 5);
  assert.equal(f.rows[1][headers.indexOf("BLOCKER")].userEnteredValue.stringValue, "=not a formula");
  assert.ok(!Object.hasOwn(f.rows[1][headers.indexOf("BLOCKER")].userEnteredValue, "formulaValue"));
});
test("Sheets input changes stop stale writes before mutation", async () => {
  const f = sheetFixture(); const before = await f.client.read();
  f.rows[1][headers.indexOf("TITLE")].userEnteredValue.stringValue = "Owner changed title";
  await assert.rejects(() => f.client.writeback(before.sourceDigest, [{ taskId: "T1", STATUS: "DONE" }]), /CHANGED_RECONCILE/);
  assert.equal(f.counts().writes, 0);
});
test("Sheets refuses owner-column writeback", async () => {
  const f = sheetFixture(); const before = await f.client.read();
  await assert.rejects(() => f.client.writeback(before.sourceDigest, [{ taskId: "T1", TITLE: "overwritten" }]), /OWNER_COLUMN_WRITE_DENIED/);
  assert.equal(f.counts().writes, 0);
});
test("Sheets confirms an ambiguous literal write by readback without replay", async () => {
  const f = sheetFixture({ lostResponse: true }); const before = await f.client.read();
  const result = await f.client.writeback(before.sourceDigest, [{ taskId: "T1", STATUS: "IMPLEMENTING" }]);
  assert.equal(result.verified, true); assert.equal(result.mutationAcknowledged, false);
  assert.equal(f.counts().writes, 1);
});
test("Sheets detects owner-input races after the write", async () => {
  const f = sheetFixture({ afterWrite: (rows) => { rows[1][1].userEnteredValue.stringValue = "concurrent edit"; } });
  const before = await f.client.read();
  await assert.rejects(() => f.client.writeback(before.sourceDigest, [{ taskId: "T1", STATUS: "IMPLEMENTING" }]), /CHANGED_DURING_WRITE/);
});
test("Sheets rejects output values outside native validation", async () => {
  const f = sheetFixture();
  f.rows[1][headers.indexOf("STATUS")].dataValidation = { condition: { type: "ONE_OF_LIST", values: [{ userEnteredValue: "QUEUED" }] }, strict: true };
  const before = await f.client.read();
  await assert.rejects(() => f.client.writeback(before.sourceDigest, [{ taskId: "T1", STATUS: "DONE" }]), /VALIDATION_DENIED/);
  assert.equal(f.counts().writes, 0);
});
test("Sheets preserves chips by refusing to overwrite a structured target", async () => {
  const f = sheetFixture(); f.rows[1][headers.indexOf("PR")].chipRuns = [{ chip: { richLinkProperties: { uri: "https://github.com/example" } } }];
  const before = await f.client.read();
  await assert.rejects(() => f.client.writeback(before.sourceDigest, [{ taskId: "T1", PR: "123" }]), /STRUCTURED_OUTPUT_DENIED/);
});
test("Sheets refuses formula inputs and duplicate task IDs", async () => {
  const a = sheetFixture(); a.rows[1][1].userEnteredValue = { formulaValue: "=1+1" };
  await assert.rejects(() => a.client.ingest(), /FORMULA_INPUT_DENIED/);
  const b = sheetFixture(); b.rows.push(structuredClone(b.rows[1]));
  await assert.rejects(() => b.client.ingest(), /DUPLICATE_TASK/);
});
test("Sheets does not treat owner-entered DONE as completion authority", async () => {
  const f = sheetFixture(); f.rows[1][headers.indexOf("STATUS")].userEnteredValue.stringValue = "DONE";
  const result = await f.client.ingest();
  assert.equal(result.tasks[0].status, undefined); assert.equal(result.tasks[0].verified, undefined);
});
