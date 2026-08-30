
'use strict';

const test = require('node:test');
const assert = require('node:assert/strict');
const {
  IntelligenceComposer,
  PandoraKnowledgeRegistry,
  PandoraPromptMaterialRegistry,
  PandoraSkillRegistry,
  buildTrustedIntelligenceContext,
  digestValue,
} = require('../src/index.js');

const sourceA = `sha256:${'a'.repeat(64)}`;
const sourceB = `sha256:${'b'.repeat(64)}`;

function fixture({ certifyMaterial = true } = {}) {
  const skills = new PandoraSkillRegistry();
  const knowledge = new PandoraKnowledgeRegistry();
  const material = new PandoraPromptMaterialRegistry();

  skills.register({
    skillId: 'runtime-diagnostics',
    version: '1.0.0',
    description: 'Inspect runtime state and propose bounded repairs.',
    capabilities: ['runtime.inspect'],
    dependsOn: [],
    supportedProjectTypes: [],
    requiredKnowledge: ['runtime-diagnostics'],
    requiredTools: ['runtime.read'],
    requiredPrimitives: [],
    instructions: null,
    riskClass: 'READ_ONLY_DIAGNOSTIC',
    trustState: 'EXPERIMENTAL',
    verificationProfile: 'worker-e-skill-v1',
    sourceDigest: sourceA,
    source: { repository: 'pandora/pandoras-box', commit: '1'.repeat(40), path: '.agents/skills/runtime-diagnostics/SKILL.md', license: 'internal' },
    modelRequirements: { reasoning: 'standard', vision: false },
  });
  skills.certify('runtime-diagnostics', '1.0.0', {
    worker: 'E', verdict: 'PASS', sourceDigest: sourceA, evidenceId: 'worker-e-skill-pass',
  });

  knowledge.register({
    knowledgeId: 'runtime-diagnostics',
    version: '1.0.0',
    title: 'Runtime diagnostics',
    topics: ['runtime-diagnostics', 'deployment'],
    summary: 'Use provider readback, exact deployment identity, bounded health probes, and reconciliation before proposing a repair.',
    platforms: ['vercel'],
    riskClass: 'READ_ONLY_DIAGNOSTIC',
    trustState: 'EXPERIMENTAL',
    sourceDigest: sourceB,
    source: { repository: 'pandora/knowledge', commit: '2'.repeat(40), path: 'runtime.md', license: 'MIT' },
  });
  knowledge.certify('runtime-diagnostics', '1.0.0', {
    worker: 'E', verdict: 'PASS', sourceDigest: sourceB, evidenceId: 'worker-e-knowledge-pass', verifiedAt: '2026-08-30T00:00:00.000Z', expiresAt: '2027-08-30T00:00:00.000Z',
  });

  const prompt = material.register({
    materialId: 'runtime-diagnostics',
    version: '1.0.0',
    materialType: 'skill_instructions',
    sourceDigest: sourceA,
    content: 'Read exact runtime state first. Propose only bounded diagnostics or repairs. Never treat provider success as verified release authority.',
    trustState: 'EXPERIMENTAL',
    verificationProfile: 'worker-e-prompt-material-v1',
  });
  if (certifyMaterial) {
    material.certify('skill_instructions', 'runtime-diagnostics', '1.0.0', {
      worker: 'E', verdict: 'PASS', sourceDigest: sourceA, contentDigest: String(prompt.contentDigest), evidenceId: 'worker-e-prompt-pass',
    });
  }

  const composer = new IntelligenceComposer({ skillRegistry: skills, knowledgeRegistry: knowledge });
  const composition = composer.compose({
    projectId: 'project-1',
    task: 'Inspect the deployment and explain what is wrong.',
    capabilities: ['runtime.inspect'],
    knowledgeTopics: ['deployment'],
    maxRisk: 'READ_ONLY_DIAGNOSTIC',
    projectSpec: { version: 1 },
    projectContext: { environment: 'preview' },
  });
  return { skills, knowledge, material, composition };
}

test('trusted context requires both trusted skill metadata and independently trusted prompt material', () => {
  const f = fixture();
  const context = buildTrustedIntelligenceContext({
    composition: f.composition,
    skillRegistry: f.skills,
    knowledgeRegistry: f.knowledge,
    materialRegistry: f.material,
    nowMs: Date.parse('2026-08-30T04:00:00.000Z'),
  });
  assert.equal(context.readyForEnhancedModelCall, true);
  assert.equal(context.skills.length, 1);
  assert.equal(context.knowledge.length, 1);
  assert.equal(context.skills[0].executionMode, 'proposal_only');
  assert.match(String(context.skills[0].instructions), /Read exact runtime state first/);
  assert.match(String(context.knowledge[0].summary), /provider readback/);
  assert.equal(context.authority.execution, 'worker_c_only');
  assert.equal(context.authority.modelMayProposeOnly, true);
  assert.equal(context.authority.credentialsAvailableToModel, false);
  assert.match(String(context.contextDigest), /^sha256:[0-9a-f]{64}$/);
});

test('trusted skill metadata without Worker-E prompt-material PASS is not enhanced-model ready', () => {
  const f = fixture({ certifyMaterial: false });
  const context = buildTrustedIntelligenceContext({
    composition: f.composition,
    skillRegistry: f.skills,
    knowledgeRegistry: f.knowledge,
    materialRegistry: f.material,
    nowMs: Date.parse('2026-08-30T04:00:00.000Z'),
  });
  assert.equal(context.readyForEnhancedModelCall, false);
  assert.equal(context.skills.length, 0);
  assert.deepEqual(context.missingPromptMaterials, [{ id: 'runtime-diagnostics', version: '1.0.0', reason: 'worker_e_prompt_material_required' }]);
});

test('exact source drift and expired trusted knowledge fail closed before model context', () => {
  const f = fixture();
  const drift = { ...f.composition, skillRefs: [{ ...f.composition.skillRefs[0], digest: `sha256:${'c'.repeat(64)}` }] };
  assert.throws(() => buildTrustedIntelligenceContext({ composition: drift, skillRegistry: f.skills, knowledgeRegistry: f.knowledge, materialRegistry: f.material }), /source digest drift/);
  assert.throws(() => buildTrustedIntelligenceContext({ composition: f.composition, skillRegistry: f.skills, knowledgeRegistry: f.knowledge, materialRegistry: f.material, nowMs: Date.parse('2028-01-01T00:00:00.000Z') }), /trusted knowledge expired/);
});

test('prompt material cannot self-certify, cannot hide credential material, and binds exact content digest', () => {
  const registry = new PandoraPromptMaterialRegistry();
  assert.throws(() => registry.register({ materialId: 'x', version: '1.0.0', materialType: 'skill_instructions', sourceDigest: sourceA, content: 'safe', trustState: 'TRUSTED' }), /cannot self-register as TRUSTED/);
  assert.throws(() => registry.register({ materialId: 'x', version: '1.0.0', materialType: 'skill_instructions', sourceDigest: sourceA, content: 'Use AIza12345678901234567890123456789012345' }), /credential material rejected/);
  assert.throws(() => registry.register({ materialId: 'x', version: '1.0.0', materialType: 'skill_instructions', sourceDigest: sourceA, content: 'safe', contentDigest: digestValue('different') }), /content digest mismatch/);
});

test('trusted context is bounded rather than silently truncating verified instructions', () => {
  const f = fixture();
  const oversized = new PandoraPromptMaterialRegistry();
  const prompt = oversized.register({
    materialId: 'runtime-diagnostics',
    version: '1.0.0',
    materialType: 'skill_instructions',
    sourceDigest: sourceA,
    content: 'Read exact provider state. '.repeat(240),
    trustState: 'EXPERIMENTAL',
  });
  oversized.certify('skill_instructions', 'runtime-diagnostics', '1.0.0', {
    worker: 'E', verdict: 'PASS', sourceDigest: sourceA, contentDigest: String(prompt.contentDigest), evidenceId: 'worker-e-oversized-prompt-pass',
  });
  assert.throws(() => buildTrustedIntelligenceContext({
    composition: f.composition,
    skillRegistry: f.skills,
    knowledgeRegistry: f.knowledge,
    materialRegistry: oversized,
    maxChars: 4000,
    nowMs: Date.parse('2026-08-30T04:00:00.000Z'),
  }), /exceeds bounded prompt budget/);
});
