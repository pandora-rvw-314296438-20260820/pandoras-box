
'use strict';

const { assertNoCredentialMaterial } = require('../security/secret-boundary.js');

const SKILL_TRUST_STATES = Object.freeze([
  'DISCOVERED',
  'IMPORTED',
  'EXPERIMENTAL',
  'VERIFIED',
  'TRUSTED',
  'DEPRECATED',
  'BLOCKED',
]);

const RISK_CLASSES = Object.freeze([
  'INFORMATIONAL',
  'READ_ONLY_DIAGNOSTIC',
  'SAFE_MUTATION',
  'PRIVILEGED',
  'SECURITY_ACTIVE',
  'DESTRUCTIVE',
  'PROHIBITED',
]);

const RISK_RANK = Object.freeze(Object.fromEntries(RISK_CLASSES.map((value, index) => [value, index])));
const EXACT_SEMVER = /^(0|[1-9]\d*)\.(0|[1-9]\d*)\.(0|[1-9]\d*)(?:-[0-9A-Za-z.-]+)?$/;

/** @param {unknown} value @param {string} field */
function requiredText(value, field) {
  if (typeof value !== 'string' || !value.trim()) throw new TypeError(`${field} is required`);
  return value.trim();
}

/** @param {unknown} value @param {string} field */
function optionalText(value, field) {
  if (value == null) return null;
  return requiredText(value, field);
}

/** @param {unknown} value @param {string} field */
function stringList(value, field) {
  if (value == null) return [];
  if (!Array.isArray(value)) throw new TypeError(`${field} must be an array`);
  return value.map((item, index) => requiredText(item, `${field}[${index}]`));
}

/** @param {unknown} value @param {readonly string[]} allowed @param {string} field */
function enumValue(value, allowed, field) {
  const parsed = requiredText(value, field);
  if (!allowed.includes(parsed)) throw new TypeError(`${field} must be one of: ${allowed.join(', ')}`);
  return parsed;
}

/** @param {unknown} value */
function sourceMetadata(value) {
  if (value == null) return Object.freeze({});
  if (!value || typeof value !== 'object' || Array.isArray(value)) throw new TypeError('source must be an object');
  const source = /** @type {Record<string, unknown>} */ (value);
  const normalized = {
    repository: optionalText(source.repository, 'source.repository'),
    commit: optionalText(source.commit, 'source.commit'),
    path: optionalText(source.path, 'source.path'),
    license: optionalText(source.license, 'source.license'),
    url: optionalText(source.url, 'source.url'),
  };
  return Object.freeze(normalized);
}

/** @param {unknown} value */
function modelRequirements(value) {
  if (value == null) return Object.freeze({ reasoning: 'standard', vision: false, minContextTokens: null });
  if (!value || typeof value !== 'object' || Array.isArray(value)) throw new TypeError('modelRequirements must be an object');
  const input = /** @type {Record<string, unknown>} */ (value);
  const reasoning = input.reasoning == null ? 'standard' : enumValue(input.reasoning, ['low', 'standard', 'high'], 'modelRequirements.reasoning');
  let minContextTokens = null;
  if (input.minContextTokens != null) {
    if (!Number.isInteger(input.minContextTokens) || Number(input.minContextTokens) <= 0) throw new TypeError('modelRequirements.minContextTokens must be positive');
    minContextTokens = Number(input.minContextTokens);
  }
  return Object.freeze({ reasoning, vision: input.vision === true, minContextTokens });
}

/** @param {Record<string, unknown>} input */
function normalizeSkillDefinition(input) {
  assertNoCredentialMaterial(input);
  const skillId = requiredText(input.skillId, 'skillId');
  const version = requiredText(input.version, 'version');
  if (!EXACT_SEMVER.test(version)) throw new TypeError('version must be an exact semantic version; mutable aliases such as latest are forbidden');
  const capabilities = stringList(input.capabilities, 'capabilities');
  if (!capabilities.length) throw new TypeError('capabilities must not be empty');
  const instructions = optionalText(input.instructions, 'instructions');
  if (instructions && instructions.length > 50000) throw new TypeError('instructions exceed the bounded skill size');
  const trustState = input.trustState == null ? 'EXPERIMENTAL' : enumValue(input.trustState, SKILL_TRUST_STATES, 'trustState');
  const riskClass = input.riskClass == null ? 'INFORMATIONAL' : enumValue(input.riskClass, RISK_CLASSES, 'riskClass');
  if (input.executionAuthority === true) throw new TypeError('skills are proposal-only and cannot hold execution authority');

  return Object.freeze({
    skillId,
    version,
    description: optionalText(input.description, 'description'),
    capabilities: Object.freeze(capabilities),
    dependsOn: Object.freeze(stringList(input.dependsOn, 'dependsOn')),
    supportedProjectTypes: Object.freeze(stringList(input.supportedProjectTypes, 'supportedProjectTypes')),
    requiredKnowledge: Object.freeze(stringList(input.requiredKnowledge, 'requiredKnowledge')),
    requiredTools: Object.freeze(stringList(input.requiredTools, 'requiredTools')),
    requiredPrimitives: Object.freeze(stringList(input.requiredPrimitives, 'requiredPrimitives')),
    instructions,
    riskClass,
    trustState,
    verificationProfile: optionalText(input.verificationProfile, 'verificationProfile'),
    sourceDigest: optionalText(input.sourceDigest, 'sourceDigest'),
    source: sourceMetadata(input.source),
    modelRequirements: modelRequirements(input.modelRequirements),
    executionMode: 'proposal_only',
    verification: null,
  });
}

/** @param {string} riskClass */
function riskRank(riskClass) {
  const value = RISK_RANK[riskClass];
  if (typeof value !== 'number') throw new TypeError('invalid risk class');
  return value;
}

class PandoraSkillRegistry {
  constructor() {
    /** @type {Map<string, Readonly<Record<string, unknown>>>} */
    this.skills = new Map();
  }

  /** @param {Record<string, unknown>} input */
  register(input) {
    const skill = normalizeSkillDefinition(input);
    const key = `${skill.skillId}@${skill.version}`;
    if (this.skills.has(key)) throw new Error(`skill already registered: ${key}`);
    this.skills.set(key, skill);
    return skill;
  }

  /** @param {string} skillId @param {string} version */
  get(skillId, version) {
    return this.skills.get(`${skillId}@${version}`) ?? null;
  }

  list() {
    return [...this.skills.values()];
  }

  /**
   * @param {{capabilities?:string[], projectType?:string, maxRisk?:string, trustedOnly?:boolean}} query
   */
  findByCapability(query = {}) {
    const capabilities = Array.isArray(query.capabilities) ? query.capabilities.map(String) : [];
    const maxRisk = query.maxRisk ?? 'DESTRUCTIVE';
    const maxRiskRank = riskRank(maxRisk);
    const trustedOnly = query.trustedOnly !== false;
    return this.list().filter((skill) => {
      const skillCapabilities = /** @type {readonly string[]} */ (skill.capabilities);
      if (capabilities.length && !capabilities.every((capability) => skillCapabilities.includes(capability))) return false;
      const supported = /** @type {readonly string[]} */ (skill.supportedProjectTypes);
      if (query.projectType && supported.length && !supported.includes(query.projectType)) return false;
      if (riskRank(String(skill.riskClass)) > maxRiskRank) return false;
      if (trustedOnly && skill.trustState !== 'TRUSTED') return false;
      if (skill.trustState === 'BLOCKED' || skill.trustState === 'DEPRECATED') return false;
      return true;
    });
  }

  /**
   * Worker E is the only authority allowed to turn an exact source digest into TRUSTED skill state.
   * @param {string} skillId
   * @param {string} version
   * @param {{worker:string, verdict:string, sourceDigest:string, evidenceId:string}} evidence
   */
  certify(skillId, version, evidence) {
    const key = `${skillId}@${version}`;
    const existing = this.skills.get(key);
    if (!existing) throw new Error(`skill not found: ${key}`);
    if (evidence.worker !== 'E') throw new Error('only Worker E verification evidence may certify a skill');
    if (evidence.verdict !== 'PASS') throw new Error('skill certification requires PASS evidence');
    const sourceDigest = String(existing.sourceDigest ?? '');
    if (!sourceDigest) throw new Error('skill sourceDigest is required before certification');
    if (evidence.sourceDigest !== sourceDigest) throw new Error('skill verification source digest mismatch');
    const evidenceId = requiredText(evidence.evidenceId, 'evidence.evidenceId');
    const trusted = Object.freeze({
      ...existing,
      trustState: 'TRUSTED',
      verification: Object.freeze({ worker: 'E', verdict: 'PASS', sourceDigest, evidenceId }),
    });
    this.skills.set(key, trusted);
    return trusted;
  }
}

const PandoraTrustedSkillRegistry = PandoraSkillRegistry;

module.exports = {
  EXACT_SEMVER,
  PandoraSkillRegistry,
  PandoraTrustedSkillRegistry,
  RISK_CLASSES,
  SKILL_TRUST_STATES,
  normalizeSkillDefinition,
  riskRank,
};
