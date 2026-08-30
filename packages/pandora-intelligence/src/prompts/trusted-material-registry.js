
'use strict';

const { digestValue } = require('../lineage/ai-execution-receipt.js');
const { assertNoCredentialMaterial } = require('../security/secret-boundary.js');

const MATERIAL_TYPES = Object.freeze(['skill_instructions', 'knowledge_summary']);
const MATERIAL_TRUST_STATES = Object.freeze(['EXPERIMENTAL', 'TRUSTED', 'BLOCKED', 'DEPRECATED']);
const EXACT_SHA256 = /^sha256:[0-9a-f]{64}$/;

/** @param {unknown} value @param {string} field */
function requiredText(value, field) {
  if (typeof value !== 'string' || !value.trim()) throw new TypeError(`${field} is required`);
  return value.trim();
}

/** @param {unknown} value @param {string} field */
function exactDigest(value, field) {
  const text = requiredText(value, field).toLowerCase();
  const normalized = text.startsWith('sha256:') ? text : `sha256:${text}`;
  if (!EXACT_SHA256.test(normalized)) throw new TypeError(`${field} must be an exact sha256 digest`);
  return normalized;
}

/** @param {Record<string, unknown>} input */
function normalizePromptMaterial(input) {
  assertNoCredentialMaterial(input);
  const materialType = requiredText(input.materialType, 'materialType');
  if (!MATERIAL_TYPES.includes(materialType)) throw new TypeError('unsupported materialType');
  const trustState = input.trustState == null ? 'EXPERIMENTAL' : requiredText(input.trustState, 'trustState');
  if (!MATERIAL_TRUST_STATES.includes(trustState)) throw new TypeError('unsupported prompt material trustState');
  if (trustState === 'TRUSTED') throw new Error('prompt material cannot self-register as TRUSTED');
  const content = requiredText(input.content, 'content');
  const contentDigest = exactDigest(input.contentDigest ?? digestValue(content), 'contentDigest');
  const computed = exactDigest(digestValue(content), 'computedContentDigest');
  if (contentDigest !== computed) throw new Error('prompt material content digest mismatch');
  const material = Object.freeze({
    materialId: requiredText(input.materialId, 'materialId'),
    version: requiredText(input.version, 'version'),
    materialType,
    sourceDigest: exactDigest(input.sourceDigest, 'sourceDigest'),
    contentDigest,
    content,
    trustState,
    verificationProfile: input.verificationProfile == null ? null : requiredText(input.verificationProfile, 'verificationProfile'),
    executionAuthority: false,
    verification: null,
  });
  assertNoCredentialMaterial(material);
  return material;
}

class PandoraPromptMaterialRegistry {
  constructor() {
    /** @type {Map<string, Readonly<Record<string, unknown>>>} */
    this.material = new Map();
  }

  /** @param {Record<string, unknown>} input */
  register(input) {
    const entry = normalizePromptMaterial(input);
    const key = `${entry.materialType}:${entry.materialId}@${entry.version}`;
    if (this.material.has(key)) throw new Error(`prompt material already registered: ${key}`);
    this.material.set(key, entry);
    return entry;
  }

  /** @param {string} materialType @param {string} materialId @param {string} version */
  get(materialType, materialId, version) {
    return this.material.get(`${materialType}:${materialId}@${version}`) ?? null;
  }

  /**
   * Worker E is the only trust authority for prompt material. Both the immutable
   * source digest and the exact prompt-content digest must match.
   * @param {string} materialType
   * @param {string} materialId
   * @param {string} version
   * @param {{worker:string,verdict:string,sourceDigest:string,contentDigest:string,evidenceId:string}} evidence
   */
  certify(materialType, materialId, version, evidence) {
    const key = `${materialType}:${materialId}@${version}`;
    const existing = this.material.get(key);
    if (!existing) throw new Error(`prompt material not found: ${key}`);
    if (existing.trustState === 'BLOCKED' || existing.trustState === 'DEPRECATED') {
      throw new Error(`prompt material cannot be certified from ${existing.trustState} state`);
    }
    if (evidence.worker !== 'E' || evidence.verdict !== 'PASS') throw new Error('prompt material certification requires Worker E PASS');
    if (exactDigest(evidence.sourceDigest, 'evidence.sourceDigest') !== existing.sourceDigest) throw new Error('prompt material source digest mismatch');
    if (exactDigest(evidence.contentDigest, 'evidence.contentDigest') !== existing.contentDigest) throw new Error('prompt material content digest mismatch');
    const trusted = Object.freeze({
      ...existing,
      trustState: 'TRUSTED',
      verification: Object.freeze({
        worker: 'E',
        verdict: 'PASS',
        sourceDigest: existing.sourceDigest,
        contentDigest: existing.contentDigest,
        evidenceId: requiredText(evidence.evidenceId, 'evidence.evidenceId'),
      }),
    });
    this.material.set(key, trusted);
    return trusted;
  }

  /** @param {string} materialType @param {string} materialId @param {string} version @param {string} sourceDigest */
  getTrusted(materialType, materialId, version, sourceDigest) {
    const entry = this.get(materialType, materialId, version);
    if (!entry || entry.trustState !== 'TRUSTED') return null;
    if (entry.sourceDigest !== exactDigest(sourceDigest, 'sourceDigest')) return null;
    return entry;
  }
}

module.exports = {
  MATERIAL_TRUST_STATES,
  MATERIAL_TYPES,
  PandoraPromptMaterialRegistry,
  normalizePromptMaterial,
};
