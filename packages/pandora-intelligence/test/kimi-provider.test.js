'use strict';
const assert = require('node:assert/strict');
const test = require('node:test');
const path = require('node:path');

const ROOT = path.resolve(__dirname, '..');
const kimi = require(path.join(ROOT, 'dist', 'index.js'));
const { assertNoCredentialMaterial } = kimi;

function request(overrides = {}) {
  return {
    requestId: 'kimi-test-1', task: 'generate_code', outputMode: 'text',
    requiredCapabilities: ['coding'], input: { instruction: 'Return a safe fixture' },
    context: {}, schema: null,
    budget: { maxAttempts: 1, remainingAttempts: 1, maxOutputTokens: 512 },
    metadata: { reasoningLevel: 'standard' }, ...overrides,
  };
}
function declaration(overrides = {}) { return { ...kimi.KIMI_K3_CAPABILITY_DECLARATION, ...overrides }; }
function successBody(overrides = {}) {
  return { id: 'cmpl-safe-1', model: 'kimi-k3', choices: [{ index: 0, message: { role: 'assistant', content: 'ok', reasoning_content: 'internal reasoning' }, finish_reason: 'stop' }], usage: { prompt_tokens: 10, completion_tokens: 5, total_tokens: 15, cached_tokens: 2 }, ...overrides };
}

test('Kimi adapter requires an injected trusted transport and exposes no secret config', () => {
  assert.throws(() => new kimi.KimiProviderAdapter({ transport: null }), /trusted server transport/);
  assert.equal(kimi.KIMI_MODEL_CONFIG.modelId, 'kimi-k3');
  assert.equal(kimi.KIMI_MODEL_CONFIG.apiBaseUrl, 'https://api.moonshot.ai/v1');
  assert.equal(kimi.KIMI_MODEL_CONFIG.maxContextTokens, 1048576);
  assert.equal(kimi.KIMI_MODEL_CONFIG.providerDefaultMaxCompletionTokens, 131072);
  assert.equal(kimi.KIMI_MODEL_CONFIG.transportDefaultMaxCompletionTokens, 8192);
  assert.equal(kimi.KIMI_MODEL_CONFIG.transportMaxCompletionTokens, 16384);
  assert.equal(kimi.KIMI_K3_CAPABILITY_DECLARATION.metadata.supportsStreaming, false);
  assert.equal(kimi.KIMI_K3_CAPABILITY_DECLARATION.metadata.providerSupportsStreaming, true);
  assert.doesNotThrow(() => assertNoCredentialMaterial(kimi.KIMI_MODEL_CONFIG));
  assert.equal(kimi.KIMI_K3_CAPABILITY_DECLARATION.capabilities.multimodal, true);
  assert.equal(kimi.KIMI_K3_CAPABILITY_DECLARATION.capabilities.toolCalling, true);
});

test('Kimi serializer creates bounded K3 request with conservative reasoning mapping', () => {
  const body = kimi.buildKimiBody(request());
  assert.equal('model' in body, false);
  assert.equal(body.reasoning_effort, 'high');
  assert.equal(body.max_completion_tokens, 512);
  assert.equal(body.stream, false);
  assert.equal(body.messages[0].role, 'system');
  assert.doesNotMatch(JSON.stringify(body), /api[_-]?key|authorization|bearer/i);
  assert.equal(kimi.mapKimiReasoningEffort(request({ metadata: { reasoningLevel: 'low' } })), 'low');
  assert.equal(kimi.mapKimiReasoningEffort(request({ metadata: { reasoningLevel: 'high' } })), 'max');
  assert.throws(() => kimi.buildKimiBody(request({ metadata: { reasoningLevel: 'ultra' } })), /reasoningLevel/);
});

test('Kimi serializer preserves chronological multi-turn assistant continuity exactly where supplied', () => {
  const messages = [
    { role: 'system', content: 'Bounded system rule' },
    { role: 'user', content: 'First turn' },
    { role: 'assistant', reasoning_content: 'preserve this provider continuation', content: 'Answer one', tool_calls: [{ id: 'call_1', type: 'function', function: { name: 'lookup', arguments: '{"id":"1"}' } }] },
    { role: 'tool', tool_call_id: 'call_1', name: 'lookup', content: '{"ok":true}' },
    { role: 'user', content: 'Continue' },
  ];
  const body = kimi.buildKimiBody(request({ context: { messages } }));
  assert.deepEqual(body.messages.map(m => m.role), ['system','user','assistant','tool','user']);
  assert.equal(body.messages[2].reasoning_content, 'preserve this provider continuation');
  assert.equal(body.messages[2].tool_calls[0].function.arguments, '{"id":"1"}');
  assert.equal(body.messages[3].tool_call_id, 'call_1');
});

test('Kimi serializer supports structured output, tools and multimodal content without executing tools', () => {
  const schema = { type: 'object', required: ['ok'], properties: { ok: { type: 'boolean' } }, additionalProperties: false };
  const body = kimi.buildKimiBody(request({
    outputMode: 'structured', schema,
    context: {
      messages: [{ role: 'user', content: [{ type: 'image_url', image_url: { url: 'https://example.test/image.png' } }, { type: 'video_url', video_url: 'ms://file-safe' }, { type: 'text', text: 'Inspect' }] }],
      tools: [{ name: 'lookup', description: 'Read bounded data', parameters: { type: 'object', properties: { id: { type: 'string' } }, required: ['id'] } }],
      toolChoice: 'auto',
    },
  }));
  assert.equal(body.response_format.type, 'json_schema');
  assert.equal(body.response_format.json_schema.strict, true);
  assert.equal(body.tools[0].function.name, 'lookup');
  assert.equal(body.tools[0].function.strict, true);
  assert.equal(body.messages[0].content[0].type, 'image_url');
  assert.equal(body.messages[0].content[1].type, 'video_url');
  assert.equal(kimi.buildKimiBody(request({ context: { messages: [{ role: 'user', content: 'x' }], toolChoice: 'required' } })).tool_choice, 'required');
  assert.throws(() => kimi.buildKimiBody(request({ context: { messages: [{ role: 'user', content: 'x' }], toolChoice: 'specific' } })), /toolChoice/);
  assert.throws(() => kimi.buildKimiBody(request({ context: { messages: [{ role: 'developer', content: 'x' }] } })), /message role/);
});

test('Kimi adapter normalizes text, usage, request id, reasoning setting and continuation state', async () => {
  let captured = null;
  const adapter = new kimi.KimiProviderAdapter({ transport: { createChatCompletion: async input => { captured = input; return { status: 200, body: successBody() }; } } });
  const result = await adapter.execute(request(), declaration());
  assert.equal(result.provider, 'kimi');
  assert.equal(result.model, 'kimi-k3');
  assert.equal(result.output, 'ok');
  assert.equal(result.usage.totalTokens, 15);
  assert.equal(result.metadata.cachedInputTokens, 2);
  assert.equal(result.metadata.providerRequestId, 'cmpl-safe-1');
  assert.equal(result.metadata.reasoningEffort, 'high');
  assert.equal(result.continuation.assistantMessage.reasoning_content, 'internal reasoning');
  assert.equal(captured.model, 'kimi-k3');
  assert.equal('model' in captured.body, false);
  assert.doesNotMatch(JSON.stringify(captured), /moonshot_api_key|kimi_api_key|authorization|bearer/i);
});

test('Kimi rejects output budgets above the current trusted transport bound before network execution', async () => {
  let calls = 0;
  const adapter = new kimi.KimiProviderAdapter({ transport: { createChatCompletion: async () => { calls += 1; return { status: 200, body: successBody() }; } } });
  await assert.rejects(() => adapter.execute(request({ budget: { maxAttempts: 1, remainingAttempts: 1, maxOutputTokens: 16385 } }), declaration()), e => e.code === 'invalid_request' && e.retryable === false);
  assert.equal(calls, 0);
});

test('Kimi consumes the deployed trusted transport safe error contract without leaking provider payloads', async () => {
  const cases = [
    [{ status: 0, ok: false, error: { kind: 'timeout', retryable: true, retryAfterMs: null } }, 'timeout', true],
    [{ status: 429, ok: false, error: { kind: 'quota_exhausted', providerCode: 'exceeded_current_quota_error', retryable: false, retryAfterMs: null } }, 'rate_limited', false],
    [{ status: 502, ok: false, error: { kind: 'response_too_large', retryable: false, retryAfterMs: null } }, 'provider_error', false],
  ];
  for (const [transportResponse, code, retryable] of cases) {
    const adapter = new kimi.KimiProviderAdapter({ transport: { createChatCompletion: async () => transportResponse } });
    await assert.rejects(() => adapter.execute(request(), declaration()), e => e.code === code && e.retryable === retryable && !/exceeded_current_quota_error/.test(e.message));
  }
});

test('Kimi rejects structured schema constraints it cannot independently validate', () => {
  const schema = { type: 'object', properties: { name: { type: 'string', minLength: 3 } } };
  assert.throws(() => kimi.buildKimiBody(request({ outputMode: 'structured', schema })), /unsupported structured schema keyword/);
});

test('Kimi structured output is parsed and schema-validated; malformed or mismatched output fails', async () => {
  const schema = { type: 'object', required: ['ok'], properties: { ok: { type: 'boolean' } }, additionalProperties: false };
  const good = new kimi.KimiProviderAdapter({ transport: { createChatCompletion: async () => ({ status: 200, body: successBody({ choices: [{ message: { role: 'assistant', content: '{"ok":true}' }, finish_reason: 'stop' }] }) }) } });
  const result = await good.execute(request({ outputMode: 'structured', schema }), declaration());
  assert.deepEqual(result.output, { ok: true });
  const badJson = new kimi.KimiProviderAdapter({ transport: { createChatCompletion: async () => ({ status: 200, body: successBody({ choices: [{ message: { role: 'assistant', content: '{bad' }, finish_reason: 'stop' }] }) }) } });
  await assert.rejects(() => badJson.execute(request({ outputMode: 'structured', schema }), declaration()), e => e.code === 'structured_output_invalid' && e.retryable === true);
  const mismatch = new kimi.KimiProviderAdapter({ transport: { createChatCompletion: async () => ({ status: 200, body: successBody({ choices: [{ message: { role: 'assistant', content: '{"ok":"yes"}' }, finish_reason: 'stop' }] }) }) } });
  await assert.rejects(() => mismatch.execute(request({ outputMode: 'structured', schema }), declaration()), e => e.code === 'structured_output_invalid');
});

test('Kimi tool calls normalize name, id and structured arguments; malformed arguments fail', async () => {
  const toolBody = successBody({ choices: [{ message: { role: 'assistant', content: '', tool_calls: [{ id: 'call_7', type: 'function', function: { name: 'lookup', arguments: '{"id":"7"}' } }] }, finish_reason: 'tool_calls' }] });
  const adapter = new kimi.KimiProviderAdapter({ transport: { createChatCompletion: async () => ({ status: 200, body: toolBody }) } });
  const result = await adapter.execute(request(), declaration());
  assert.equal(result.finishReason, 'tool_calls');
  assert.deepEqual(result.toolCalls[0], { id: 'call_7', name: 'lookup', arguments: { id: '7' } });
  const malformed = new kimi.KimiProviderAdapter({ transport: { createChatCompletion: async () => ({ status: 200, body: successBody({ choices: [{ message: { role: 'assistant', content: '', tool_calls: [{ id: 'c', function: { name: 'lookup', arguments: '{bad' } }] }, finish_reason: 'tool_calls' }] }) }) } });
  await assert.rejects(() => malformed.execute(request(), declaration()), e => e.code === 'structured_output_invalid');
});

test('Kimi finish reason length is normalized as truncation', async () => {
  const adapter = new kimi.KimiProviderAdapter({ transport: { createChatCompletion: async () => ({ status: 200, body: successBody({ choices: [{ message: { role: 'assistant', content: 'partial' }, finish_reason: 'length' }] }) }) } });
  const result = await adapter.execute(request(), declaration());
  assert.equal(result.finishReason, 'length');
  assert.equal(result.truncated, true);
});

for (const scenario of [
  [401, { type: 'invalid_authentication_error', message: 'secret raw provider message' }, 'authentication_failed', false],
  [403, { type: 'permission_denied_error', message: 'forbidden' }, 'authentication_failed', false],
  [429, { type: 'rate_limit_reached_error', message: 'limit' }, 'rate_limited', true],
  [504, { type: 'server_error', message: 'timeout' }, 'timeout', true],
  [503, { type: 'engine_overloaded_error', message: 'busy' }, 'provider_unavailable', true],
  [404, { type: 'model_not_found', message: 'model not found' }, 'unsupported_capability', false],
  [400, { type: 'invalid_request_error', message: 'Input token length too long' }, 'context_too_large', false],
  [400, { type: 'invalid_request_error', message: 'bad field' }, 'invalid_request', false],
]) {
  const [status, providerError, code, retryable] = scenario;
  test(`Kimi HTTP ${status} maps to ${code} with correct retryability`, async () => {
    const adapter = new kimi.KimiProviderAdapter({ transport: { createChatCompletion: async () => ({ status, body: { error: providerError }, retryAfterMs: status === 429 ? 1000 : null }) } });
    await assert.rejects(() => adapter.execute(request(), declaration()), e => {
      assert.equal(e.code, code); assert.equal(e.retryable, retryable);
      assert.doesNotMatch(e.message, /secret raw provider message/);
      if (status === 429) assert.equal(e.retryAfterMs, 1000);
      return true;
    });
  });
}

test('Kimi transport network and timeout failures normalize without raw transport details', async () => {
  const net = new kimi.KimiProviderAdapter({ transport: { createChatCompletion: async () => { throw Object.assign(new Error('socket private detail'), { code: 'ECONNRESET' }); } } });
  await assert.rejects(() => net.execute(request(), declaration()), e => e.code === 'provider_unavailable' && e.retryable === true && !/socket private detail/.test(e.message));
  const timeout = new kimi.KimiProviderAdapter({ transport: { createChatCompletion: async () => { throw Object.assign(new Error('deadline private detail'), { code: 'ETIMEDOUT' }); } } });
  await assert.rejects(() => timeout.execute(request(), declaration()), e => e.code === 'timeout' && e.retryable === true && !/deadline private detail/.test(e.message));
});

test('Kimi rejects credential-bearing request state before transport call', async () => {
  let calls = 0;
  const adapter = new kimi.KimiProviderAdapter({ transport: { createChatCompletion: async () => { calls += 1; return { status: 200, body: successBody() }; } } });
  await assert.rejects(() => adapter.execute(request({ context: { moonshot_api_key: 'must-never-cross' } }), declaration()), /credential material rejected/);
  await assert.rejects(() => adapter.execute(request({ context: { moonshotApiKey: 'must-never-cross-too' } }), declaration()), /credential material rejected/);
  assert.equal(calls, 0);
});

test('Kimi capability declaration registers generically and is selectable by existing registry', () => {
  const registry = new kimi.ModelCapabilityRegistry();
  const registered = registry.register(kimi.KIMI_K3_CAPABILITY_DECLARATION);
  assert.equal(registered.provider, 'kimi');
  assert.equal(registered.modelId, 'kimi-k3');
  assert.equal(registry.findCompatible({ required: ['reasoning', 'toolCalling', 'longContext'], outputMode: 'structured', minContext: 1000000 }).length, 1);
});

test('Kimi preserves tool-call-only assistant continuity and enforces JSON for tool proposals', () => {
  const toolCall = { id: 'call_1', type: 'function', function: { name: 'read_file', arguments: '{"path":"README.md"}' } };
  const req = request({
    outputMode: 'tool_proposals',
    context: { messages: [
      { role: 'user', content: 'Read the file' },
      { role: 'assistant', content: null, reasoning_content: '', tool_calls: [toolCall] },
      { role: 'tool', toolCallId: 'call_1', content: 'contents' },
    ] },
  });
  const body = kimi.buildKimiBody(req);
  assert.equal(body.response_format.type, 'json_object');
  assert.equal(body.messages[1].content, null);
  assert.equal(body.messages[1].reasoning_content, '');
  assert.deepEqual(body.messages[1].tool_calls, [toolCall]);
});

test('Kimi stream event seam normalizes content, tool delta, usage and hides reasoning text', () => {
  const event = kimi.normalizeKimiStreamEvent({ data: { choices: [{ delta: { content: 'Hi', reasoning_content: 'private reasoning', tool_calls: [{ index: 0, function: { arguments: '{' } }] }, finish_reason: null }], usage: { prompt_tokens: 2, completion_tokens: 1, total_tokens: 3 } } });
  assert.equal(event.type, 'delta');
  assert.equal(event.contentDelta, 'Hi');
  assert.equal(event.reasoningDeltaPresent, true);
  assert.equal('reasoningContent' in event, false);
  assert.equal(event.usage.totalTokens, 3);
  assert.deepEqual(kimi.normalizeKimiStreamEvent({ data: '[DONE]' }), { type: 'done' });
});
