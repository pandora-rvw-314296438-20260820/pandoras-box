
'use strict';

const assert = require('node:assert/strict');
const test = require('node:test');
const path = require('node:path');
const ROOT = path.resolve(__dirname, '..');
const intelligence = require(path.join(ROOT, 'dist', 'index.js'));

function trustedSkillRegistry() {
  const registry = new intelligence.PandoraSkillRegistry();
  registry.register({
    skillId: 'pandora-deployment-diagnostics',
    version: '1.0.0',
    capabilities: ['deployment.diagnose'],
    supportedProjectTypes: ['web'],
    requiredKnowledge: ['http', 'dns', 'tls'],
    requiredTools: ['runtime.http.inspect', 'runtime.dns.inspect'],
    requiredPrimitives: ['pandora-audit'],
    instructions: 'Inspect exact provider state and produce proposals only.',
    riskClass: 'READ_ONLY_DIAGNOSTIC',
    sourceDigest: 'sha256:skill-source-1',
    modelRequirements: { reasoning: 'high', vision: false, minContextTokens: 32000 },
    source: { repository: 'pandora/pandoras-box', commit: 'abc123', path: 'skills/deployment.md', license: 'MIT' },
  });
  registry.certify('pandora-deployment-diagnostics', '1.0.0', {
    worker: 'E',
    verdict: 'PASS',
    sourceDigest: 'sha256:skill-source-1',
    evidenceId: 'worker-e-skill-proof-1',
  });
  return registry;
}

function trustedKnowledgeRegistry() {
  const registry = new intelligence.PandoraKnowledgeRegistry();
  registry.register({
    knowledgeId: 'http-diagnostics',
    version: '1.0.0',
    topics: ['http', 'deployment'],
    title: 'HTTP deployment diagnostics',
    summary: 'Use bounded HTTP status, redirect, header, and health checks before proposing repair.',
    riskClass: 'READ_ONLY_DIAGNOSTIC',
    sourceDigest: 'sha256:knowledge-source-1',
    source: { repository: 'curated/upstream', commit: 'def456', path: 'http.md', license: 'MIT', upstreamAuthority: 'official-docs' },
  });
  registry.certify('http-diagnostics', '1.0.0', {
    worker: 'E',
    verdict: 'PASS',
    sourceDigest: 'sha256:knowledge-source-1',
    evidenceId: 'worker-e-knowledge-proof-1',
    verifiedAt: '2026-08-30T00:00:00.000Z',
    expiresAt: '2027-08-30T00:00:00.000Z',
  });
  return registry;
}

test('trusted skills require exact immutable versions and Worker E exact-digest certification', () => {
  const registry = new intelligence.PandoraSkillRegistry();
  assert.throws(() => registry.register({ skillId: 'bad', version: 'latest', capabilities: ['build'] }), /exact semantic version/);
  const skill = registry.register({
    skillId: 'pandora-web-build',
    version: '1.0.0',
    capabilities: ['web.build'],
    sourceDigest: 'sha256:exact-source',
    source: { repository: 'pandora/pandoras-box', commit: 'abc', path: 'skill.md', license: 'MIT' },
  });
  assert.equal(skill.executionMode, 'proposal_only');
  assert.equal(registry.findByCapability({ capabilities: ['web.build'] }).length, 0);
  assert.throws(() => registry.certify('pandora-web-build', '1.0.0', {
    worker: 'B', verdict: 'PASS', sourceDigest: 'sha256:exact-source', evidenceId: 'wrong-worker',
  }), /only Worker E/);
  assert.throws(() => registry.certify('pandora-web-build', '1.0.0', {
    worker: 'E', verdict: 'PASS', sourceDigest: 'sha256:other', evidenceId: 'wrong-digest',
  }), /digest mismatch/);
  registry.certify('pandora-web-build', '1.0.0', {
    worker: 'E', verdict: 'PASS', sourceDigest: 'sha256:exact-source', evidenceId: 'proof-1',
  });
  assert.equal(registry.findByCapability({ capabilities: ['web.build'] }).length, 1);
});

test('trusted knowledge retrieval enforces freshness and risk bounds', () => {
  const registry = trustedKnowledgeRegistry();
  registry.register({
    knowledgeId: 'active-network-probing',
    version: '1.0.0',
    topics: ['deployment', 'network'],
    summary: 'Active network security testing knowledge.',
    riskClass: 'SECURITY_ACTIVE',
    sourceDigest: 'sha256:active-network',
    source: { repository: 'curated/upstream', commit: '123', path: 'network.md', license: 'MIT' },
  });
  registry.certify('active-network-probing', '1.0.0', {
    worker: 'E', verdict: 'PASS', sourceDigest: 'sha256:active-network', evidenceId: 'proof-active', expiresAt: '2027-08-30T00:00:00.000Z',
  });
  registry.register({
    knowledgeId: 'expired-http',
    version: '1.0.0',
    topics: ['http'],
    summary: 'An expired reference that must not be retrieved.',
    riskClass: 'READ_ONLY_DIAGNOSTIC',
    sourceDigest: 'sha256:expired',
    source: { repository: 'curated/upstream', commit: '456', path: 'old.md', license: 'MIT' },
  });
  registry.certify('expired-http', '1.0.0', {
    worker: 'E', verdict: 'PASS', sourceDigest: 'sha256:expired', evidenceId: 'proof-expired', expiresAt: '2026-08-01T00:00:00.000Z',
  });
  const results = registry.findRelevant({
    topics: ['http', 'deployment'],
    maxRisk: 'READ_ONLY_DIAGNOSTIC',
    nowMs: Date.parse('2026-08-30T00:00:00.000Z'),
  });
  assert.deepEqual(results.map((entry) => entry.knowledgeId), ['http-diagnostics']);
});

test('intelligence composer selects trusted skills and knowledge while keeping Worker C as authority', () => {
  const composer = new intelligence.IntelligenceComposer({
    skillRegistry: trustedSkillRegistry(),
    knowledgeRegistry: trustedKnowledgeRegistry(),
  });
  const composition = composer.compose({
    projectId: 'project-1',
    projectVersionId: 'version-1',
    projectType: 'web',
    task: 'diagnose failed deployment',
    capabilities: ['deployment.diagnose'],
    knowledgeTopics: ['http'],
    projectSpec: { objective: 'restore verified deployment' },
    projectContext: { deploymentId: 'dpl_test' },
    primitiveSelections: [{ id: 'pandora-audit', version: '1.0.0', digest: 'sha256:primitive' }],
    maxRisk: 'READ_ONLY_DIAGNOSTIC',
  });
  assert.equal(composition.ready, true);
  assert.equal(composition.executionAuthority, 'worker_c_only');
  assert.deepEqual(composition.skillRefs.map((ref) => `${ref.id}@${ref.version}`), ['pandora-deployment-diagnostics@1.0.0']);
  assert.deepEqual(composition.knowledgeRefs.map((ref) => `${ref.id}@${ref.version}`), ['http-diagnostics@1.0.0']);
  assert.deepEqual(composition.requiredTools, ['runtime.dns.inspect', 'runtime.http.inspect']);
  assert.equal(composition.modelRequirements.reasoning, 'high');
  assert.match(composition.compositionDigest, /^sha256:/);
  assert.throws(() => composer.compose({
    projectId: 'project-1', task: 'unsafe', capabilities: ['deployment.diagnose'], projectContext: { gemini_api_key: 'must-never-cross' },
  }), /credential material rejected/);
});

test('AI execution receipts persist digests and exact refs without raw prompt or output', () => {
  const receipt = intelligence.createAiExecutionReceipt({
    executionId: 'exec-1',
    projectId: 'project-1',
    projectVersionId: 'version-1',
    task: 'deployment.diagnose',
    input: { instruction: 'inspect deployment', nested: { a: 1, b: 2 } },
    output: { proposal: 'read logs' },
    skills: [{ id: 'pandora-deployment-diagnostics', version: '1.0.0', digest: 'sha256:skill-source-1' }],
    knowledge: [{ id: 'http-diagnostics', version: '1.0.0', digest: 'sha256:knowledge-source-1' }],
    primitives: [{ id: 'pandora-audit', version: '1.0.0', digest: 'sha256:primitive' }],
    model: { provider: 'google', modelId: 'gemini-test', routeReason: 'task fit', attempts: 1 },
    usage: { inputTokens: 10, outputTokens: 5, totalTokens: 15, estimatedCostUsd: 0.001, latencyMs: 200 },
    createdAt: '2026-08-30T00:00:00.000Z',
  });
  assert.equal(Object.hasOwn(receipt, 'input'), false);
  assert.equal(Object.hasOwn(receipt, 'output'), false);
  assert.match(receipt.inputDigest, /^sha256:/);
  assert.match(receipt.outputDigest, /^sha256:/);
  assert.match(receipt.receiptDigest, /^sha256:/);
  assert.equal(receipt.skills[0].version, '1.0.0');
  assert.throws(() => intelligence.createAiExecutionReceipt({
    executionId: 'exec-unsafe', projectId: 'project-1', task: 'unsafe', input: { github_token: 'secret' }, model: { provider: 'x', modelId: 'y' },
  }), /credential material rejected/);
});

test('model routing policy can enforce provider exclusions and verifier independence', async () => {
  const registry = new intelligence.ModelCapabilityRegistry();
  for (const provider of ['gemini', 'fallback']) {
    registry.register({
      provider,
      modelId: `${provider}-test`,
      capabilities: { reasoning: true, structuredOutput: true },
      latencyClass: 'interactive',
      costClass: 'low',
      reliabilityClass: 'high',
      maxContextTokens: 100000,
      outputModes: ['structured'],
    });
  }
  const adapters = {
    gemini: { execute: async (_request, declaration) => ({ provider: 'gemini', model: declaration.modelId, output: { provider: 'gemini' }, usage: intelligence.createModelUsage({}) }) },
    fallback: { execute: async (_request, declaration) => ({ provider: 'fallback', model: declaration.modelId, output: { provider: 'fallback' }, usage: intelligence.createModelUsage({}) }) },
  };
  const router = new intelligence.ModelRouter({ registry, adapters });
  const request = intelligence.createModelRequest({
    requestId: 'route-policy-1',
    task: 'plan_architecture',
    outputMode: 'structured',
    requiredCapabilities: ['reasoning', 'structuredOutput'],
    input: { instruction: 'plan' },
    context: { projectId: 'project-1' },
  });
  const denied = intelligence.createRoutingPolicy({ deniedProviders: ['gemini'] });
  const result = await router.execute(request, { policy: denied });
  assert.equal(result.routedProvider, 'fallback');

  const verifierPolicy = intelligence.createRoutingPolicy({
    requireIndependentVerifier: true,
    builderProvider: 'gemini',
    builderModel: 'gemini-test',
  });
  const verifier = await router.execute(request, { preferredProvider: 'gemini', policy: verifierPolicy });
  assert.equal(verifier.routedProvider, 'fallback');
});
