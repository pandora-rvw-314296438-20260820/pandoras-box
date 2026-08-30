
'use strict';

const assert = require('node:assert/strict');
const test = require('node:test');
const path = require('node:path');
const ROOT = path.resolve(__dirname, '..');
const intelligence = require(path.join(ROOT, 'dist', 'index.js'));

const catalog = Object.freeze({
  schema_version: '1.0.0',
  catalog_version: '1.0.0',
  source_repository: 'pandora-rvw-314296438-20260820/pandoras-box',
  source_base_sha: '932c2b672787554f3f97d35035907760d34f556b',
});

const readSkill = Object.freeze({
  id: 'recovering-canonical-project-state',
  category: 'authority-memory',
  lifecycle_phase: 'all',
  risk: 'read',
  autonomy: 'autonomous',
  entrypoint: '.agents/skills/recovering-canonical-project-state/SKILL.md',
  depends_on: [],
  capabilities: ['memory', 'verification', 'governance'],
});

const sensitiveSkill = Object.freeze({
  id: 'maintaining-operational-memory',
  category: 'authority-memory',
  lifecycle_phase: 'all',
  risk: 'sensitive-write',
  autonomy: 'approval-before-side-effect',
  entrypoint: '.agents/skills/maintaining-operational-memory/SKILL.md',
  depends_on: ['recovering-canonical-project-state'],
  capabilities: ['memory', 'audit', 'governance'],
});

test('existing .agents catalog projects into trust metadata without creating execution authority', () => {
  const projected = intelligence.projectAgentCatalogSkill({
    catalog,
    entry: sensitiveSkill,
    contentDigest: '5c1d3802290baf7c4cd823c9471d53fd7a24b2fdda9e383964eb9f313dfeeff8',
  });
  assert.equal(projected.skillId, 'maintaining-operational-memory');
  assert.equal(projected.version, '1.0.0');
  assert.equal(projected.trustState, 'EXPERIMENTAL');
  assert.equal(projected.riskClass, 'PRIVILEGED');
  assert.equal(projected.executionMode, 'proposal_only');
  assert.deepEqual(projected.dependsOn, ['recovering-canonical-project-state']);
  assert.equal(projected.sourceDigest, 'sha256:5c1d3802290baf7c4cd823c9471d53fd7a24b2fdda9e383964eb9f313dfeeff8');
});

test('catalog projection requires the exact content digest and preserves trusted promotion boundary', () => {
  assert.throws(() => intelligence.projectAgentCatalogSkill({
    catalog,
    entry: readSkill,
    contentDigest: 'latest',
  }), /exact sha256 digest/);

  const registry = new intelligence.PandoraTrustedSkillRegistry();
  const [projected] = intelligence.registerAgentCatalogProjections({
    registry,
    catalog,
    entries: [readSkill],
    contentDigests: {
      '.agents/skills/recovering-canonical-project-state/SKILL.md': '9f7694392a4c90b78234d0fa61b327563839db65cd73e67704c2a433ed0b60ff',
    },
  });
  assert.equal(projected.trustState, 'EXPERIMENTAL');
  assert.equal(registry.findByCapability({ capabilities: ['memory'] }).length, 0);
  registry.certify('recovering-canonical-project-state', '1.0.0', {
    worker: 'E',
    verdict: 'PASS',
    sourceDigest: 'sha256:9f7694392a4c90b78234d0fa61b327563839db65cd73e67704c2a433ed0b60ff',
    evidenceId: 'worker-e-existing-catalog-proof',
  });
  assert.equal(registry.findByCapability({ capabilities: ['memory'] }).length, 1);
});

test('catalog risk vocabulary maps into Worker-B risk bounds deterministically', () => {
  assert.deepEqual(intelligence.AGENT_RISK_TO_TRUSTED_RISK, {
    read: 'READ_ONLY_DIAGNOSTIC',
    'reversible-write': 'SAFE_MUTATION',
    'sensitive-write': 'PRIVILEGED',
    'high-risk': 'DESTRUCTIVE',
  });
  const highRisk = { ...readSkill, id: 'high-risk-example', risk: 'high-risk', entrypoint: '.agents/skills/high-risk-example/SKILL.md' };
  const projected = intelligence.projectAgentCatalogSkill({
    catalog,
    entry: highRisk,
    contentDigest: 'aaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaa',
  });
  assert.equal(projected.riskClass, 'DESTRUCTIVE');
});

test('batch projection fails closed when a validated manifest digest is absent', () => {
  const registry = new intelligence.PandoraTrustedSkillRegistry();
  assert.throws(() => intelligence.registerAgentCatalogProjections({
    registry,
    catalog,
    entries: [readSkill, sensitiveSkill],
    contentDigests: {
      '.agents/skills/recovering-canonical-project-state/SKILL.md': '9f7694392a4c90b78234d0fa61b327563839db65cd73e67704c2a433ed0b60ff',
    },
  }), /validated content digest missing/);
});
