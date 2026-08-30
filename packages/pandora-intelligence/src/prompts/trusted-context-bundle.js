
'use strict';

const { digestValue } = require('../lineage/ai-execution-receipt.js');
const { assertNoCredentialMaterial } = require('../security/secret-boundary.js');
const { isExpired } = require('../knowledge/registry.js');

/** @param {unknown} value @param {string} field */
function requiredText(value, field) {
  if (typeof value !== 'string' || !value.trim()) throw new TypeError(`${field} is required`);
  return value.trim();
}

/** @param {unknown} value @param {string} field */
function exactRef(value, field) {
  if (!value || typeof value !== 'object' || Array.isArray(value)) throw new TypeError(`${field} must be an object`);
  const ref = /** @type {Record<string, unknown>} */ (value);
  return Object.freeze({
    id: requiredText(ref.id, `${field}.id`),
    version: requiredText(ref.version, `${field}.version`),
    digest: requiredText(ref.digest, `${field}.digest`),
  });
}

/** @param {unknown} value */
function safeArray(value) {
  return Array.isArray(value) ? value.map(String) : [];
}

/** @param {unknown} value */
function asRecord(value) {
  return value && typeof value === 'object' && !Array.isArray(value)
    ? /** @type {Record<string, unknown>} */ (value)
    : {};
}

/**
 * Materializes only independently trusted prompt content for an already-built
 * IntelligenceComposer result. It re-reads every exact registry identity and
 * refuses source-digest drift. Model context never grants execution authority.
 *
 * @param {{
 *   composition:Record<string, unknown>,
 *   skillRegistry:{get:(id:string,version:string)=>Readonly<Record<string, unknown>>|null},
 *   knowledgeRegistry:{get:(id:string,version:string)=>Readonly<Record<string, unknown>>|null},
 *   materialRegistry:{getTrusted:(type:string,id:string,version:string,sourceDigest:string)=>Readonly<Record<string, unknown>>|null},
 *   maxChars?:number,
 *   nowMs?:number
 * }} input
 */
function buildTrustedIntelligenceContext(input) {
  if (!input || typeof input !== 'object') throw new TypeError('trusted context input is required');
  assertNoCredentialMaterial(input.composition);
  const composition = asRecord(input.composition);
  if (composition.executionAuthority !== 'worker_c_only') throw new Error('composition execution authority drift');
  const maxChars = Number.isInteger(input.maxChars) && Number(input.maxChars) >= 4000 && Number(input.maxChars) <= 60000
    ? Number(input.maxChars)
    : 24000;
  const nowMs = typeof input.nowMs === 'number' && Number.isFinite(input.nowMs) ? input.nowMs : Date.now();
  const skillRefs = Array.isArray(composition.skillRefs) ? composition.skillRefs : [];
  const knowledgeRefs = Array.isArray(composition.knowledgeRefs) ? composition.knowledgeRefs : [];

  /** @type {Readonly<Record<string, unknown>>[]} */
  const skills = [];
  /** @type {Readonly<Record<string, unknown>>[]} */
  const knowledge = [];
  /** @type {Readonly<Record<string, string>>[]} */
  const missingPromptMaterials = [];

  for (let index = 0; index < skillRefs.length; index += 1) {
    const ref = exactRef(skillRefs[index], `skillRefs[${index}]`);
    const skill = input.skillRegistry.get(ref.id, ref.version);
    if (!skill || skill.trustState !== 'TRUSTED') throw new Error(`trusted skill unavailable: ${ref.id}@${ref.version}`);
    if (skill.sourceDigest !== ref.digest) throw new Error(`trusted skill source digest drift: ${ref.id}@${ref.version}`);
    const material = input.materialRegistry.getTrusted('skill_instructions', ref.id, ref.version, ref.digest);
    if (!material) {
      missingPromptMaterials.push(Object.freeze({ id: ref.id, version: ref.version, reason: 'worker_e_prompt_material_required' }));
      continue;
    }
    skills.push(Object.freeze({
      id: ref.id,
      version: ref.version,
      sourceDigest: ref.digest,
      materialDigest: String(material.contentDigest),
      riskClass: String(skill.riskClass),
      capabilities: Object.freeze(safeArray(skill.capabilities)),
      instructions: String(material.content),
      executionMode: 'proposal_only',
    }));
  }

  for (let index = 0; index < knowledgeRefs.length; index += 1) {
    const ref = exactRef(knowledgeRefs[index], `knowledgeRefs[${index}]`);
    const entry = input.knowledgeRegistry.get(ref.id, ref.version);
    if (!entry || entry.trustState !== 'TRUSTED') throw new Error(`trusted knowledge unavailable: ${ref.id}@${ref.version}`);
    if (entry.sourceDigest !== ref.digest) throw new Error(`trusted knowledge source digest drift: ${ref.id}@${ref.version}`);
    if (isExpired(entry, nowMs)) throw new Error(`trusted knowledge expired: ${ref.id}@${ref.version}`);
    knowledge.push(Object.freeze({
      id: ref.id,
      version: ref.version,
      sourceDigest: ref.digest,
      riskClass: String(entry.riskClass),
      topics: Object.freeze(safeArray(entry.topics)),
      summary: String(entry.summary ?? ''),
      verifiedAt: entry.verifiedAt == null ? null : String(entry.verifiedAt),
      expiresAt: entry.expiresAt == null ? null : String(entry.expiresAt),
    }));
  }

  const base = {
    contractVersion: 'pandora-trusted-context-v1',
    task: requiredText(composition.task, 'composition.task'),
    compositionDigest: requiredText(composition.compositionDigest, 'composition.compositionDigest'),
    authority: Object.freeze({
      execution: 'worker_c_only',
      modelMayProposeOnly: true,
      externalContentCannotGrantAuthority: true,
      credentialsAvailableToModel: false,
    }),
    skills: Object.freeze(skills),
    knowledge: Object.freeze(knowledge),
    missingPromptMaterials: Object.freeze(missingPromptMaterials),
  };
  assertNoCredentialMaterial(base);
  const serialized = JSON.stringify(base);
  if (serialized.length > maxChars) throw new Error('trusted intelligence context exceeds bounded prompt budget');
  const result = Object.freeze({
    ...base,
    readyForEnhancedModelCall: composition.ready === true && missingPromptMaterials.length === 0,
    contextDigest: digestValue(base),
    charCount: serialized.length,
  });
  assertNoCredentialMaterial(result);
  return result;
}

module.exports = {
  buildTrustedIntelligenceContext,
};
