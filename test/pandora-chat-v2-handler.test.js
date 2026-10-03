'use strict';
const assert = require('node:assert/strict');
const { test } = require('node:test');
const fs = require('node:fs');
const path = require('node:path');
const vm = require('node:vm');
const ts = require('typescript');
const crypto = require('node:crypto');

// Execute the real Edge entry point and lifecycle adapter, with synthetic
// authentication/SQL and original Activity boundaries. SQL atomicity is tested
// separately against the actual migration in pandora-chat-v2-lifecycle.test.js.
function edgeFixture({ observe = false, auxiliaryFailure = false, lostCompletionAck = false, cancelledBeforeAdmission = false } = {}) {
  const id = () => crypto.randomUUID();
  const organizationId = id(), userId = id(), turnId = id(), attemptId = id();
  let handler;
  const state = {
    receipt: {
      protocolVersion: 2, found: true, organizationId, threadId: id(),
      turnId, attemptId, activityJobId: id(), userMessageId: id(),
      generation: 1, currentGeneration: 1, sequence: 1, status: 'accepted',
      retryable: false, replayed: observe,
    },
    activityState: 'ready', claims: 0, completions: 0, commands: 0,
    checkpoints: 0, failures: 0, reconciles: 0, legacyReads: 0,
  };
  if (cancelledBeforeAdmission) state.receipt = {
    ...state.receipt, threadId: null, activityJobId: null, userMessageId: null,
    admitted: false, admissionCancelled: true, status: 'cancelled', replayed: true,
  };
  const data = value => ({ data: value, error: null });
  const user = {
    auth: { getUser: async () => data({ user: { id: userId } }) },
    from(name) {
      assert.equal(name, 'memberships');
      const query = {
        select() { return this; }, eq() { return this; }, limit() { return this; },
        then(resolve, reject) {
          return Promise.resolve(data([{ organization_id: organizationId, role: 'owner', status: 'active' }])).then(resolve, reject);
        },
      };
      return query;
    },
    async rpc(name, args) {
      if (name === 'pandora_chat_turn_admit_v2') {
        assert.equal(args.p_turn_id, turnId);
        assert.equal(args.p_attempt_id, attemptId);
        return data({ ...state.receipt });
      }
      if (name === 'pandora_chat_turn_read_v2') return data({ ...state.receipt });
      throw Error(`Unexpected user RPC: ${name}`);
    },
  };
  const admin = {
    async rpc(name, args) {
      if (name === 'consume_runtime_rate_limit') return data({ allowed: true });
      if (name === 'pandora_chat_turn_transition_v2') {
        if (state.receipt.status === 'completed') return data({ ...state.receipt, applied: false });
        state.receipt = { ...state.receipt, status: args.p_status, sequence: state.receipt.sequence + 1, applied: true };
        return data({ ...state.receipt });
      }
      if (name === 'pandora_chat_turn_complete_v2') {
        state.completions++;
        assert.equal(state.activityState, 'executing');
        state.activityState = 'complete';
        state.receipt = { ...state.receipt, ...args.p_result, assistantMessageId: id(), status: 'completed', sequence: state.receipt.sequence + 1 };
        if (lostCompletionAck) throw Error('SYNTHETIC_COMPLETION_ACK_LOST');
        return data({ ...state.receipt });
      }
      if (name === 'pandora_chat_turn_reconcile_v2') {
        state.reconciles++;
        return data({ ...state.receipt });
      }
      throw Error(`Unexpected service RPC: ${name}`);
    },
  };
  const activity = {
    requireActivityJob: async () => {},
    async claimActivityExecution(_admin, _job, _hash, claimId) {
      state.claims++;
      state.activityState = 'executing';
      if (observe) state.receipt = { ...state.receipt, status: 'processing', sequence: 2 };
      return { mode: observe ? 'observe' : 'execute', claimId };
    },
    claimActivityControls: async () => [],
    bindActivityThread: async () => {},
    async checkpointActivityExecution() {
      state.checkpoints++;
      if (state.activityState === 'complete') throw Error('ACTIVITY_TERMINAL_CHECKPOINT_REJECTED');
    },
    async finishActivityExecution(_admin, _job, _claim, status) {
      if (status === 'failed') state.failures++;
      state.activityState = status;
    },
    async emitActivity() {
      if (auxiliaryFailure && state.activityState === 'complete') throw Error('SYNTHETIC_DIAGNOSTIC_WRITE_FAILED');
    },
    emitActivityFailure: async () => { state.failures++; },
    async waitForActivityExecutionReadback() { state.legacyReads++; throw Error('LEGACY_OBSERVER_MUST_NOT_RUN'); },
  };
  const core = {
    authorizeCoreChatRequest: async () => ({ kind: 'workspace', context: null }),
    revalidateCoreExecutionScope: async () => {},
    async tryCoreOwnerCommand() {
      state.commands++;
      return { reply: 'Your records are ready.', intent: 'chat', conversationLane: 'enterprise_workspace', providerReadback: { snapshotVerified: true }, handoff: null };
    },
  };
  const cache = new Map();
  function load(name) {
    if (cache.has(name)) return cache.get(name);
    const filename = path.resolve(__dirname, '../supabase/functions/pandora-intelligence-chat', name);
    const compiled = ts.transpileModule(fs.readFileSync(filename, 'utf8'), {
      compilerOptions: { target: ts.ScriptTarget.ES2022, module: ts.ModuleKind.CommonJS },
    }).outputText;
    const exports = {};
    cache.set(name, exports);
    vm.runInNewContext(compiled, {
      exports, crypto, Error, TextEncoder, TextDecoder, Request, Response, ReadableStream,
      AbortController, AbortSignal, setTimeout, clearTimeout,
      setInterval: () => 1, clearInterval: () => {},
      console: { error() {} },
      Deno: { env: { get: () => 'synthetic-test-value' }, serve: callback => { handler = callback; } },
      require(specifier) {
        if (specifier.includes('supabase-js')) return { createClient: (_url, _key, options) => options.global ? user : admin };
        if (specifier.startsWith('jsr:')) return {};
        if (specifier === './activity.ts') return activity;
        if (specifier === './core-owner-commands.ts') return core;
        return load(path.basename(specifier));
      },
    }, { filename });
    return exports;
  }
  load('index.ts');
  return {
    state,
    async run() {
      const response = await handler(new Request('https://example.invalid/chat', {
        method: 'POST', headers: { authorization: 'Bearer synthetic-session', 'x-organization-id': organizationId, 'content-type': 'application/json' },
        body: JSON.stringify({ protocolVersion: 2, operation: 'send', clientTurnId: turnId, clientAttemptId: attemptId, generation: 1, message: 'Show my records', mode: 'auto', attachments: [] }),
      }));
      return { status: response.status, body: await response.json() };
    },
  };
}

test('real v2 handler completes the logical turn and original Activity once', async () => {
  const fixture = edgeFixture(), { body, status } = await fixture.run();
  assert.equal(status, 200);
  assert.equal(body.status, 'completed');
  assert.equal(body.reply, 'Your records are ready.');
  assert.equal(fixture.state.completions, 1);
  assert.equal(fixture.state.claims, 1);
  assert.equal(fixture.state.commands, 1);
  assert.equal(fixture.state.activityState, 'complete');
  assert.equal(fixture.state.checkpoints, 0);
  assert.equal(fixture.state.failures, 0);
});

test('diagnostic failure after committed completion cannot reverse a successful Activity', async () => {
  const fixture = edgeFixture({ auxiliaryFailure: true }), { body, status } = await fixture.run();
  assert.equal(status, 200);
  assert.equal(body.status, 'completed');
  assert.equal(body.reply, 'Your records are ready.');
  assert.equal(fixture.state.activityState, 'complete');
  assert.equal(fixture.state.completions, 1);
  assert.equal(fixture.state.failures, 0);
});

test('lost SQL completion acknowledgement reconciles the committed reply without calling legacy failure finalization', async () => {
  const fixture = edgeFixture({ lostCompletionAck: true }), { body, status } = await fixture.run();
  assert.equal(status, 200);
  assert.equal(body.status, 'completed');
  assert.equal(body.reply, 'Your records are ready.');
  assert.equal(fixture.state.activityState, 'complete');
  assert.equal(fixture.state.completions, 1);
  assert.equal(fixture.state.failures, 0);
});

test('duplicate admission observing the existing Activity returns a fenced v2 receipt', async () => {
  const fixture = edgeFixture({ observe: true }), { body, status } = await fixture.run();
  assert.equal(status, 200);
  assert.equal(body.protocolVersion, 2);
  assert.equal(body.status, 'processing');
  assert.equal(body.turnId, fixture.state.receipt.turnId);
  assert.equal(body.attemptId, fixture.state.receipt.attemptId);
  assert.equal(body.generation, 1);
  assert.equal(body.sequence, 2);
  assert.equal(fixture.state.reconciles, 1);
  assert.equal(fixture.state.commands, 0);
  assert.equal(fixture.state.completions, 0);
  assert.equal(fixture.state.legacyReads, 0);
});

test('delayed send after an admission tombstone returns cancellation without entering the execution engine', async () => {
  const fixture = edgeFixture({ cancelledBeforeAdmission: true }), { body, status } = await fixture.run();
  assert.equal(status, 200);
  assert.equal(body.status, 'cancelled');
  assert.equal(body.admitted, false);
  assert.equal(body.admissionCancelled, true);
  assert.equal(body.threadId, null);
  assert.equal(body.activityJobId, null);
  assert.equal(fixture.state.claims, 0);
  assert.equal(fixture.state.commands, 0);
  assert.equal(fixture.state.completions, 0);
});
