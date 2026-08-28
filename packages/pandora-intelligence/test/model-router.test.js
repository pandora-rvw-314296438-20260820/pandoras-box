'use strict';

const assert = require('node:assert/strict');
const test = require('node:test');
const path = require('node:path');
const ROOT = path.resolve(__dirname, '..');
const intelligence = require(path.join(ROOT, 'dist', 'index.js'));

function registry() {
  const r = new intelligence.ModelCapabilityRegistry();
  r.register({ provider: 'gemini', modelId: 'gemini-test', capabilities: { coding: true, structuredOutput: true, reasoning: true }, latencyClass: 'interactive', costClass: 'low', reliabilityClass: 'high', maxContextTokens: 100000, outputModes: ['structured', 'json', 'text'] });
  r.register({ provider: 'fallback', modelId: 'fallback-test', capabilities: { coding: true, structuredOutput: true, reasoning: true }, latencyClass: 'standard', costClass: 'medium', reliabilityClass: 'standard', maxContextTokens: 100000, outputModes: ['structured', 'json', 'text'] });
  r.register({ provider: 'weak', modelId: 'weak-test', capabilities: { classification: true }, latencyClass: 'interactive', costClass: 'low', reliabilityClass: 'high', maxContextTokens: 100000, outputModes: ['text'] });
  return r;
}

function request(overrides = {}) {
  return intelligence.createModelRequest({ requestId: 'model-run-1', task: 'generate_code', outputMode: 'structured', requiredCapabilities: ['coding', 'structuredOutput'], input: { instruction: 'Return a safe fixture' }, context: { projectId: 'project-1' }, budget: { maxAttempts: 2, remainingAttempts: 2, maxOutputTokens: 256 }, ...overrides });
}

test('Gemini adapter sends credential-free bounded content and normalizes structured output', async () => {
  let captured = null;
  const transport = { generateContent: async input => { captured = input; return { status: 200, body: { candidates: [{ content: { parts: [{ text: '{"ok":true,"files":[]}' }] }, finishReason: 'STOP' }], usageMetadata: { promptTokenCount: 10, candidatesTokenCount: 5, totalTokenCount: 15 } } }; } };
  const router = new intelligence.ModelRouter({ registry: registry(), adapters: { gemini: new intelligence.GeminiProviderAdapter({ transport }) } });
  const result = await router.execute(request(), { preferredProvider: 'gemini' });
  assert.equal(result.routedProvider, 'gemini');
  assert.equal(result.routedModel, 'gemini-test');
  assert.deepEqual(result.output, { ok: true, files: [] });
  assert.equal(result.usage.totalTokens, 15);
  assert.ok(captured);
  const serialized = JSON.stringify(captured);
  assert.doesNotMatch(serialized, /gemini_api_key|AIza|authorization/i);
  assert.equal(captured.body.generationConfig.responseMimeType, 'application/json');
});

test('router falls back only to another capability-compatible provider', async () => {
  const gemini = new intelligence.GeminiProviderAdapter({ transport: { generateContent: async () => ({ status: 503, body: { error: { message: 'provider unavailable' } } }) } });
  let fallbackCalls = 0;
  let weakCalls = 0;
  const fallback = { execute: async (_request, declaration) => { fallbackCalls += 1; return { provider: 'fallback', model: declaration.modelId, output: { recovered: true }, usage: intelligence.createModelUsage({}) }; } };
  const weak = { execute: async () => { weakCalls += 1; return { provider: 'weak', model: 'weak-test', output: 'wrong capability', usage: intelligence.createModelUsage({}) }; } };
  const router = new intelligence.ModelRouter({ registry: registry(), adapters: { gemini, fallback, weak } });
  const result = await router.execute(request(), { preferredProvider: 'gemini' });
  assert.equal(result.routedProvider, 'fallback');
  assert.equal(result.fallbackUsed, true);
  assert.equal(result.attempts, 2);
  assert.equal(fallbackCalls, 1);
  assert.equal(weakCalls, 0);
});

test('non-retryable provider failures do not silently downgrade', async () => {
  const gemini = new intelligence.GeminiProviderAdapter({ transport: { generateContent: async () => ({ status: 403, body: { error: { message: 'denied' } } }) } });
  let fallbackCalls = 0;
  const router = new intelligence.ModelRouter({ registry: registry(), adapters: { gemini, fallback: { execute: async () => { fallbackCalls += 1; return {}; } } } });
  await assert.rejects(async () => router.execute(request(), { preferredProvider: 'gemini' }), error => error && error.code === 'authentication_failed');
  assert.equal(fallbackCalls, 0);
});

test('credential material is rejected before any provider transport call', async () => {
  let calls = 0;
  const transport = { generateContent: async () => { calls += 1; return { status: 200, body: {} }; } };
  const router = new intelligence.ModelRouter({ registry: registry(), adapters: { gemini: new intelligence.GeminiProviderAdapter({ transport }) } });
  const unsafe = request({ context: { projectId: 'project-1', gemini_api_key: 'must-never-cross' } });
  await assert.rejects(async () => router.execute(unsafe, { preferredProvider: 'gemini' }), /credential material rejected/);
  assert.equal(calls, 0);
});
