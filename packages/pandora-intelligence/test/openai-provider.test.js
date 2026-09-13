'use strict';
const test = require('node:test');
const assert = require('node:assert/strict');
const {
  OPENAI_MODEL_CAPABILITY_DECLARATIONS,
  OPENAI_MODEL_IDS,
  OPENAI_TRANSPORT_MAX_COMPLETION_TOKENS,
  OpenAIProviderAdapter,
  buildOpenAIChatBody,
  createModelRequest,
  normalizeOpenAIHttpResponse,
} = require('../dist/index.js');

function declaration(modelId = 'gpt-5.6-terra') {
  const found = OPENAI_MODEL_CAPABILITY_DECLARATIONS.find((item) => item.modelId === modelId);
  assert.ok(found, `missing declaration for ${modelId}`);
  return found;
}

function structuredRequest(overrides = {}) {
  return createModelRequest({
    requestId: 'req-openai-test',
    task: 'classify_task',
    outputMode: 'structured',
    context: {
      messages: [
        { role: 'developer', content: 'Return a compact classification.' },
        { role: 'user', content: [{ type: 'text', text: 'Classify this.' }, { type: 'image_url', image_url: { url: 'https://example.test/image.png', detail: 'low' } }] },
      ],
      tools: [{ name: 'lookup', description: 'Read bounded data', parameters: { type: 'object', properties: { id: { type: 'string' } }, required: ['id'], additionalProperties: false } }],
      toolChoice: 'auto',
    },
    schema: { type: 'object', properties: { ok: { type: 'boolean' } }, required: ['ok'], additionalProperties: false },
    budget: { maxAttempts: 2, maxOutputTokens: 4096 },
    metadata: { reasoningLevel: 'standard' },
    ...overrides,
  });
}

test('OpenAI profiles match the currently activated Pandora models and external-provider boundary', () => {
  assert.deepEqual(OPENAI_MODEL_IDS, ['gpt-5.6-luna', 'gpt-5.6-terra', 'gpt-5.6-sol']);
  for (const item of OPENAI_MODEL_CAPABILITY_DECLARATIONS) {
    assert.equal(item.executionBoundary, 'external_provider');
    assert.equal(item.maxContextTokens, 1050000);
    assert.equal(item.capabilities.reasoning, true);
    assert.equal(item.capabilities.toolCalling, true);
    assert.equal(item.metadata.transportMaxCompletionTokens, OPENAI_TRANSPORT_MAX_COMPLETION_TOKENS);
  }
});

test('OpenAI body keeps model and credentials outside the adapter payload', () => {
  const body = buildOpenAIChatBody(structuredRequest());
  assert.equal(body.model, undefined);
  assert.equal(body.stream, false);
  assert.equal(body.reasoning_effort, 'medium');
  assert.equal(body.max_completion_tokens, 4096);
  assert.equal(body.response_format.type, 'json_schema');
  assert.equal(body.tools[0].type, 'function');
  assert.equal(body.messages[1].content[1].type, 'image_url');
  assert.doesNotMatch(JSON.stringify(body), /authorization|openai_api_key|bearer\s/i);
});

test('OpenAI adapter normalizes structured output, usage and finish state', async () => {
  let captured = null;
  const adapter = new OpenAIProviderAdapter({ transport: { async createChatCompletion(input) {
    captured = input;
    return { status: 200, ok: true, body: { model: input.model, choices: [{ message: { content: '{"ok":true}' }, finish_reason: 'stop' }], usage: { prompt_tokens: 12, completion_tokens: 5, total_tokens: 17 } } };
  } } });
  const result = await adapter.execute(structuredRequest(), declaration());
  assert.equal(captured.model, 'gpt-5.6-terra');
  assert.equal(captured.requestId, 'req-openai-test');
  assert.equal(captured.body.model, undefined);
  assert.deepEqual(result.output, { ok: true });
  assert.equal(result.usage.totalTokens, 17);
  assert.equal(result.finishReason, 'stop');
});

test('OpenAI adapter normalizes native tool calls without executing them', async () => {
  const adapter = new OpenAIProviderAdapter({ transport: { async createChatCompletion() {
    return { status: 200, ok: true, body: { choices: [{ message: { content: '', tool_calls: [{ id: 'call_1', type: 'function', function: { name: 'lookup', arguments: '{"id":"42"}' } }] }, finish_reason: 'tool_calls' }], usage: {} } };
  } } });
  const request = createModelRequest({ requestId: 'req-tool', task: 'classify_task', outputMode: 'text', context: {}, budget: { maxAttempts: 1 }, metadata: {} });
  const result = await adapter.execute(request, declaration('gpt-5.6-luna'));
  assert.equal(result.toolCalls.length, 1);
  assert.deepEqual(result.toolCalls[0], { id: 'call_1', name: 'lookup', arguments: { id: '42' } });
  assert.equal(result.finishReason, 'tool_calls');
});

test('OpenAI transport failures are classified without raw provider payload leakage', () => {
  assert.throws(() => normalizeOpenAIHttpResponse({ status: 401, ok: false, error: { kind: 'authorization', retryable: false, secret: 'do-not-copy' } }, 'gpt-5.6-terra'), (error) => {
    assert.equal(error.code, 'authentication_failed');
    assert.equal(error.retryable, false);
    assert.equal(error.safeDetails.kind, 'authorization');
    assert.doesNotMatch(error.message, /do-not-copy/);
    return true;
  });
  assert.throws(() => normalizeOpenAIHttpResponse({ status: 429, ok: false, error: { kind: 'rate_limit', retryable: true, retryAfterMs: 500 } }, 'gpt-5.6-terra'), (error) => error.code === 'rate_limited' && error.retryable === true && error.retryAfterMs === 500);
  assert.throws(() => normalizeOpenAIHttpResponse({ status: 503, ok: false, error: { kind: 'provider_unavailable', retryable: true } }, 'gpt-5.6-terra'), (error) => error.code === 'provider_unavailable' && error.retryable === true);
});

test('OpenAI adapter classifies malformed provider tool-call shapes as provider failures', async () => {
  const adapter = new OpenAIProviderAdapter({ transport: { async createChatCompletion() {
    return { status: 200, ok: true, body: { choices: [{ message: { content: '', tool_calls: [{ id: 'call_1', type: 'function', function: null }] }, finish_reason: 'tool_calls' }], usage: {} } };
  } } });
  const request = createModelRequest({ requestId: 'req-malformed-tool', task: 'classify_task', outputMode: 'text', context: {}, budget: { maxAttempts: 1 }, metadata: {} });
  await assert.rejects(() => adapter.execute(request, declaration()), (error) => error.code === 'provider_error' && error.retryable === false && error.details.kind === 'malformed_response');
});

test('OpenAI adapter rejects undeclared models, oversized output budgets and credential material', async () => {
  const adapter = new OpenAIProviderAdapter({ transport: { async createChatCompletion() { throw new Error('transport should not be called'); } } });
  await assert.rejects(() => adapter.execute(structuredRequest(), { ...declaration(), modelId: 'gpt-6-astra' }), (error) => error.code === 'unsupported_capability' && error.retryable === false);
  assert.throws(() => buildOpenAIChatBody(structuredRequest({ budget: { maxAttempts: 1, maxOutputTokens: OPENAI_TRANSPORT_MAX_COMPLETION_TOKENS + 1 } })), (error) => error.code === 'invalid_request');
  assert.throws(() => buildOpenAIChatBody(structuredRequest({ metadata: { reasoningLevel: 'standard', openai_api_key: 'not-a-real-key' } })), /credential/i);
});
