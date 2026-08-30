
'use strict';

const test = require('node:test');
const assert = require('node:assert/strict');
const {
  EXTERNAL_SOURCE_CATALOG,
  PandoraKnowledgeRegistry,
  PandoraSkillRegistry,
  authorizeExternalSourceReference,
  createExternalBenchmarkReference,
  createExternalKnowledgeCandidate,
  createExternalSkillCandidate,
} = require('../src/index.js');

const digestA = `sha256:${'a'.repeat(64)}`;
const digestB = `sha256:${'b'.repeat(64)}`;

const awesome = EXTERNAL_SOURCE_CATALOG.awesome_claude_skills;
const router = EXTERNAL_SOURCE_CATALOG.router;
const book = EXTERNAL_SOURCE_CATALOG.secret_knowledge;

test('reviewed fork catalog is exact-commit pinned with explicit import modes', () => {
  assert.equal(awesome.commit, 'be2a406907dbc61b73e6827ded415c96139d13a2');
  assert.equal(awesome.mode, 'SKILL_SEED');
  assert.equal(awesome.licenseStatus, 'UNRESOLVED');
  assert.equal(awesome.contentImportAllowed, false);
  assert.equal(router.commit, '16b1480edf5d012f544516df514b1b28ee4ea83e');
  assert.equal(router.mode, 'BENCHMARK_REFERENCE');
  assert.equal(router.referenceOnly, true);
  assert.equal(book.commit, '7d37069a361d3fd9f214480755f7969744e866fa');
  assert.equal(book.mode, 'KNOWLEDGE_SEED');
  assert.equal(book.license, 'MIT');
  assert.equal(book.contentImportAllowed, true);
});

test('external source policy rejects repository drift, commit drift, traversal and unapproved content import', () => {
  const valid = {
    sourceId: 'awesome_claude_skills',
    repository: awesome.repository,
    commit: awesome.commit,
    path: 'composio-skills/README.md',
    sourceDigest: digestA,
    purpose: 'SKILL_SEED',
  };
  assert.throws(() => authorizeExternalSourceReference({ ...valid, repository: 'other/repo' }), /repository drift/);
  assert.throws(() => authorizeExternalSourceReference({ ...valid, commit: '0'.repeat(40) }), /commit drift/);
  assert.throws(() => authorizeExternalSourceReference({ ...valid, path: '../LICENSE' }), /safe repository-relative path/);
  assert.throws(
    () => authorizeExternalSourceReference({ ...valid, materializeContent: true }),
    /not licensed\/approved/,
  );
});

test('unknown-license skill seed is metadata-only BLOCKED and cannot be Worker-E certified', () => {
  const candidate = createExternalSkillCandidate({
    sourceId: 'awesome_claude_skills',
    repository: awesome.repository,
    commit: awesome.commit,
    path: 'composio-skills/README.md',
    sourceDigest: digestA,
    skillId: 'external-composio-seed',
    version: '0.1.0',
    description: 'Discovery metadata only until source licensing is resolved.',
    capabilities: ['external.skill.discovery'],
    riskClass: 'INFORMATIONAL',
  });
  assert.equal(candidate.trustState, 'BLOCKED');
  assert.equal(candidate.instructions, null);
  assert.equal(candidate.executionMode, 'proposal_only');

  const registry = new PandoraSkillRegistry();
  registry.register({ ...candidate });
  assert.throws(
    () => registry.certify(candidate.skillId, candidate.version, {
      worker: 'E',
      verdict: 'PASS',
      sourceDigest: digestA,
      evidenceId: 'worker-e-license-bypass-attempt',
    }),
    /cannot be certified from BLOCKED state/,
  );

  assert.throws(
    () => createExternalSkillCandidate({
      sourceId: 'awesome_claude_skills',
      repository: awesome.repository,
      commit: awesome.commit,
      path: 'composio-skills/README.md',
      sourceDigest: digestA,
      skillId: 'forbidden-content-copy',
      version: '0.1.0',
      capabilities: ['external.skill.discovery'],
      instructions: 'Do not allow this materialization while licensing is unresolved.',
    }),
    /not licensed\/approved/,
  );
});

test('MIT knowledge seed enters EXPERIMENTAL and becomes selectable only after exact Worker-E certification', () => {
  const candidate = createExternalKnowledgeCandidate({
    sourceId: 'secret_knowledge',
    repository: book.repository,
    commit: book.commit,
    path: 'README.md',
    sourceDigest: digestB,
    knowledgeId: 'external-operational-reference-seed',
    version: '0.1.0',
    title: 'Curated operational reference seed',
    topics: ['operations', 'diagnostics'],
    platforms: ['linux', 'networking'],
    summary: 'Curated non-executable operational reference metadata. Raw command snippets are not executed or trusted by import.',
    riskClass: 'READ_ONLY_DIAGNOSTIC',
  });
  assert.equal(candidate.trustState, 'EXPERIMENTAL');
  assert.equal(candidate.source.license, 'MIT');

  const registry = new PandoraKnowledgeRegistry();
  registry.register({ ...candidate });
  assert.deepEqual(registry.findRelevant({ topics: ['operations'] }), []);
  registry.certify(candidate.knowledgeId, candidate.version, {
    worker: 'E',
    verdict: 'PASS',
    sourceDigest: digestB,
    evidenceId: 'worker-e-curated-knowledge-pass',
  });
  assert.equal(registry.findRelevant({ topics: ['operations'] }).length, 1);
});

test('ELv2 router fork remains benchmark/reference only and never becomes runtime authority', () => {
  const reference = createExternalBenchmarkReference({
    sourceId: 'router',
    repository: router.repository,
    commit: router.commit,
    path: 'README.md',
    sourceDigest: digestA,
    referenceId: 'workweave-router-behavior-reference',
    description: 'Reference behavior only; no source dependency or code import.',
  });
  assert.equal(reference.runtimeDependency, false);
  assert.equal(reference.executionAuthority, false);
  assert.equal(reference.codeImportAllowed, false);
  assert.equal(reference.trustState, 'REFERENCE_ONLY');

  assert.throws(
    () => createExternalSkillCandidate({
      sourceId: 'router',
      repository: router.repository,
      commit: router.commit,
      path: 'README.md',
      sourceDigest: digestA,
      skillId: 'forbidden-router-copy',
      version: '0.1.0',
      capabilities: ['model.routing'],
    }),
    /purpose mismatch/,
  );
});
