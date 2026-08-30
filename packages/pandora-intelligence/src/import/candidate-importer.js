
'use strict';

const { normalizeKnowledgeEntry } = require('../knowledge/registry.js');
const { normalizeSkillDefinition } = require('../skills/registry.js');
const { authorizeExternalSourceReference } = require('./external-source-policy.js');

/** @param {unknown} value @param {string} field */
function requiredText(value, field) {
  if (typeof value !== 'string' || !value.trim()) throw new TypeError(`${field} is required`);
  return value.trim();
}

/** @param {unknown} value @param {string} field */
function stringList(value, field) {
  if (!Array.isArray(value)) throw new TypeError(`${field} must be an array`);
  return value.map((item, index) => requiredText(item, `${field}[${index}]`));
}

/** @param {Record<string, unknown>} input */
function createExternalSkillCandidate(input) {
  const instructions = input.instructions == null ? null : requiredText(input.instructions, 'instructions');
  const source = authorizeExternalSourceReference({
    sourceId: requiredText(input.sourceId, 'sourceId'),
    repository: requiredText(input.repository, 'repository'),
    commit: requiredText(input.commit, 'commit'),
    path: requiredText(input.path, 'path'),
    sourceDigest: requiredText(input.sourceDigest, 'sourceDigest'),
    purpose: 'SKILL_SEED',
    materializeContent: instructions != null,
  });
  const blocked = source.licenseStatus !== 'APPROVED';
  return normalizeSkillDefinition({
    skillId: requiredText(input.skillId, 'skillId'),
    version: requiredText(input.version, 'version'),
    description: input.description == null ? null : requiredText(input.description, 'description'),
    capabilities: stringList(input.capabilities, 'capabilities'),
    dependsOn: Array.isArray(input.dependsOn) ? stringList(input.dependsOn, 'dependsOn') : [],
    supportedProjectTypes: Array.isArray(input.supportedProjectTypes)
      ? stringList(input.supportedProjectTypes, 'supportedProjectTypes')
      : [],
    requiredKnowledge: [],
    requiredTools: [],
    requiredPrimitives: [],
    instructions: blocked ? null : instructions,
    riskClass: input.riskClass == null ? 'INFORMATIONAL' : requiredText(input.riskClass, 'riskClass'),
    trustState: blocked ? 'BLOCKED' : 'EXPERIMENTAL',
    verificationProfile: 'external-skill-import-v1',
    sourceDigest: source.sourceDigest,
    source: {
      repository: source.repository,
      commit: source.commit,
      path: source.path,
      license: source.license,
      url: null,
    },
    modelRequirements: { reasoning: 'standard', vision: false },
  });
}

/** @param {Record<string, unknown>} input */
function createExternalKnowledgeCandidate(input) {
  const source = authorizeExternalSourceReference({
    sourceId: requiredText(input.sourceId, 'sourceId'),
    repository: requiredText(input.repository, 'repository'),
    commit: requiredText(input.commit, 'commit'),
    path: requiredText(input.path, 'path'),
    sourceDigest: requiredText(input.sourceDigest, 'sourceDigest'),
    purpose: 'KNOWLEDGE_SEED',
    materializeContent: true,
  });
  if (source.licenseStatus !== 'APPROVED') throw new Error('knowledge source license is not approved');
  return normalizeKnowledgeEntry({
    knowledgeId: requiredText(input.knowledgeId, 'knowledgeId'),
    version: requiredText(input.version, 'version'),
    title: input.title == null ? null : requiredText(input.title, 'title'),
    topics: stringList(input.topics, 'topics'),
    summary: requiredText(input.summary, 'summary'),
    platforms: Array.isArray(input.platforms) ? stringList(input.platforms, 'platforms') : [],
    riskClass: input.riskClass == null ? 'INFORMATIONAL' : requiredText(input.riskClass, 'riskClass'),
    trustState: 'EXPERIMENTAL',
    sourceDigest: source.sourceDigest,
    source: {
      repository: source.repository,
      commit: source.commit,
      path: source.path,
      url: null,
      license: source.license,
      upstreamAuthority: source.upstreamRepository,
    },
    verifiedAt: null,
    expiresAt: input.expiresAt == null ? null : requiredText(input.expiresAt, 'expiresAt'),
  });
}

/** @param {Record<string, unknown>} input */
function createExternalBenchmarkReference(input) {
  const source = authorizeExternalSourceReference({
    sourceId: requiredText(input.sourceId, 'sourceId'),
    repository: requiredText(input.repository, 'repository'),
    commit: requiredText(input.commit, 'commit'),
    path: requiredText(input.path, 'path'),
    sourceDigest: requiredText(input.sourceDigest, 'sourceDigest'),
    purpose: 'BENCHMARK_REFERENCE',
    materializeContent: false,
  });
  return Object.freeze({
    referenceId: requiredText(input.referenceId, 'referenceId'),
    description: input.description == null ? null : requiredText(input.description, 'description'),
    source,
    executionAuthority: false,
    runtimeDependency: false,
    codeImportAllowed: false,
    trustState: 'REFERENCE_ONLY',
  });
}

module.exports = {
  createExternalBenchmarkReference,
  createExternalKnowledgeCandidate,
  createExternalSkillCandidate,
};
