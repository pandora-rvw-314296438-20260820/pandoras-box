"use strict";
const assert = require("node:assert/strict");
const { test } = require("node:test");
const { readFileSync } = require("node:fs");
const path = require("node:path"), vm = require("node:vm"), ts = require("typescript");
const { randomUUID } = require("node:crypto");
function load(name) {
  const full = path.resolve(__dirname, "../supabase/functions/pandora-intelligence-chat/", name);
  const source = ts.transpileModule(readFileSync(full, "utf8"), {
    compilerOptions: { target: ts.ScriptTarget.ES2022, module: ts.ModuleKind.CommonJS },
  }).outputText;
  const exported = {};
  vm.runInNewContext(source, { exports: exported, require: file => load(path.basename(file)), TextEncoder, TextDecoder, AbortController, setInterval, clearInterval }, { filename: full });
  return exported;
}
const { classifyTurnFailure, parseTurnRequest } = load("turn-contract.ts");
const { openChatTurn } = load("turn-lifecycle.ts");
function classified(error) { return JSON.parse(JSON.stringify(classifyTurnFailure(error))); }

test("permanent adapter errors retain their audit code and do not offer Retry in either case", () => {
  for (const code of ["invalid_request", "authentication_failed", "quota_exhausted", "unsupported_capability"]) {
    for (const spelling of [code, code.toUpperCase()]) {
      assert.deepEqual(classified(Object.assign(Error("PROVIDER_UNAVAILABLE"), { code: spelling, retryable: false })), {
        status: "failed_permanently", retryable: false, code: spelling,
      });
      assert.equal(classified({ code: spelling, retryable: true }).retryable, false,
        "an inconsistent adapter flag cannot override a permanent authorization/request classification");
    }
  }
});

test("the explicit provider retryability contract survives unfamiliar and known transient codes", () => {
  for (const code of ["provider_error", "provider_unavailable", "new_adapter_terminal_condition"]) {
    const failure = classified({ code, retryable: false });
    assert.equal(failure.status, "failed_permanently");
    assert.equal(failure.retryable, false);
  }
  for (const code of ["provider_unavailable", "network_error", "timeout", "rate_limited"]) {
    assert.deepEqual(classified({ code, retryable: true }), { status: "failed_recoverably", retryable: true, code });
  }
  assert.equal(classified(Error("BACKEND_WRITE_FAILED")).status, "failed_recoverably");
});

test("cancellation and uncertain execution keep their own lifecycle ahead of adapter retryability", () => {
  for (const code of ["REQUEST_CANCELLED", "request_cancelled", "CHAT_GENERATION_STALE", "chat_generation_stale"]) {
    assert.deepEqual(classified({ code, retryable: false }), { status: "cancelled", retryable: false, code });
  }
  assert.equal(classified({ code: "provider_unavailable", message: "REQUEST_CANCELLED", retryable: true }).status, "cancelled");
  for (const code of ["CHAT_RECONCILIATION_REQUIRED", "chat_reconciliation_required", "execution_in_progress", "execution_previous_failed"]) {
    assert.deepEqual(classified({ code, retryable: false }), { status: "outcome_unknown", retryable: false, code });
  }
});

test("failure audit codes remain bounded and sanitized without returning raw error objects", () => {
  const failure = classified({ code: "timeout /" + "x".repeat(300), retryable: true, details: "internal-only" });
  assert.equal(failure.code.length, 160);
  assert.match(failure.code, /^[A-Za-z0-9_:.-]+$/);
  assert.deepEqual(Object.keys(failure).sort(), ["code", "retryable", "status"]);
  assert.deepEqual(classified(null), { status: "failed_recoverably", retryable: true, code: "CHAT_INTERNAL_FAILURE" });
});

test("uncertainty acknowledgement requires a separate explicit boolean cancel with exact attempt and generation", () => {
  const request = { protocolVersion: 2, operation: "cancel", clientTurnId: randomUUID(), clientAttemptId: randomUUID(), generation: 2, expectedGeneration: 2 };
  assert.equal(parseTurnRequest(request).acknowledgeUnknown, false);
  assert.equal(parseTurnRequest({ ...request, acknowledgeUnknown: true }).acknowledgeUnknown, true);
  for (const value of ["true", 1, null, {}, []]) {
    assert.throws(() => parseTurnRequest({ ...request, acknowledgeUnknown: value }), /ACKNOWLEDGEMENT_INVALID/);
  }
  for (const operation of ["send", "retry", "readback"]) {
    assert.throws(() => parseTurnRequest({ ...request, operation, acknowledgeUnknown: true }), /ACKNOWLEDGEMENT_INVALID/);
  }
  assert.throws(() => parseTurnRequest({ ...request, clientAttemptId: null, acknowledgeUnknown: true }), /ACKNOWLEDGEMENT_INVALID/);
  assert.throws(() => parseTurnRequest({ ...request, generation: 1, acknowledgeUnknown: true }), /GENERATION_INVALID/);
});

test("the real Edge adapter forwards acknowledgement only from its explicit parsed command", async () => {
  const organizationId = randomUUID(), clientTurnId = randomUUID(), clientAttemptId = randomUUID(), calls = [];
  const receipt = { status: "outcome_unknown", retryable: false, cancellationRequested: true, outcomeUnknownAcknowledged: true };
  const clients = { organizationId, user: { rpc: async (name, args) => { calls.push({ name, args: JSON.parse(JSON.stringify(args)) }); return { data: receipt }; } },
    admin: { rpc: async () => { assert.fail("cancellation must retain authenticated actor scope"); } } };
  for (const acknowledgeUnknown of [undefined, true]) {
    const turn = parseTurnRequest({ protocolVersion: 2, operation: "cancel", clientTurnId, clientAttemptId, generation: 2, expectedGeneration: 2, acknowledgeUnknown });
    const result = await openChatTurn(clients, { turn }, "unused");
    assert.equal(result.readback, receipt);
  }
  assert.deepEqual(calls, [false, true].map(p_acknowledge_unknown => ({ name: "pandora_chat_turn_cancel_v2", args: {
    p_organization_id: organizationId, p_turn_id: clientTurnId, p_expected_generation: 2, p_attempt_id: clientAttemptId, p_acknowledge_unknown,
  } })));
});
